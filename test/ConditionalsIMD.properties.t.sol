// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ConditionalsIMD} from "../src/ConditionalsIMD.sol";

/// @dev Additional boundary and sequence properties for the accepted token implementation.
/// forge-config: default.fuzz.runs = 1024
contract ConditionalsIMDPropertiesTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    ConditionalsIMD internal token;
    address internal alice = makeAddr("properties holder");
    address internal bob = makeAddr("properties recipient");
    address internal spender = makeAddr("properties spender");
    address internal secondSpender = makeAddr("properties second spender");

    function setUp() public {
        token = new ConditionalsIMD();
    }

    function test_MaximumFiniteApprovalDecrementsAndCanReplaceUnlimitedApproval() public {
        assertTrue(token.approve(spender, type(uint256).max));
        assertTrue(token.approve(spender, type(uint256).max - 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max - 2);
        assertEq(token.balanceOf(alice), 1);

        // Replacing an unlimited grant with a finite grant must restore a real limit.
        assertTrue(token.approve(spender, type(uint256).max));
        assertTrue(token.approve(spender, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(alice), 2);
        assertEq(token.balanceOf(address(this)), SUPPLY - 2);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaximumAmountCannotBeSpentEvenWithUnlimitedApproval() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, type(uint256).max);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, SUPPLY));
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
    }

    function test_UnlimitedApprovalCannotTransferToZero() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), SUPPLY);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroTransferFromToZeroStillReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(alice, address(0), 0);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroApprovalToZeroSpenderStillReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        assertEq(token.allowance(address(this), address(0)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_DelegatedSelfTransferCannotExceedBalance() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1)
        );
        vm.prank(spender);
        token.transferFrom(address(this), address(this), SUPPLY + 1);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_SelfApprovalAllowsHolderToUseTransferFrom() public {
        assertTrue(token.transfer(alice, SUPPLY));
        vm.prank(alice);
        assertTrue(token.approve(alice, SUPPLY));
        vm.prank(alice);
        assertTrue(token.transferFrom(alice, bob, SUPPLY));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), SUPPLY);
        assertEq(token.allowance(alice, alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_AllowanceDoesNotFollowTokensToAnotherHolder() public {
        assertTrue(token.transfer(alice, 1));
        vm.prank(alice);
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(alice);
        assertTrue(token.transfer(bob, 1));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(bob, spender, 1);
        assertEq(token.allowance(alice, spender), type(uint256).max);
        assertEq(token.allowance(bob, spender), 0);
        assertEq(token.balanceOf(bob), 1);
        assertEq(token.balanceOf(spender), 0);
    }

    function test_TransactionOriginCannotLendItsAllowanceToAnotherCaller() public {
        assertTrue(token.transfer(alice, 1));
        vm.prank(alice);
        assertTrue(token.approve(spender, 1));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        vm.prank(bob, spender);
        token.transferFrom(alice, bob, 1);
        assertEq(token.allowance(alice, spender), 1);
        assertEq(token.allowance(alice, bob), 0);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_TransferToTokenContractIsAccountedForWithoutBurning() public {
        assertTrue(token.transfer(address(token), SUPPLY));
        assertEq(token.balanceOf(address(token)), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_ReplacingApprovalIsIdempotent(uint256 firstGrant, uint256 replacement) public {
        vm.startPrank(alice);
        assertTrue(token.approve(spender, firstGrant));
        assertTrue(token.approve(spender, replacement));
        assertEq(token.allowance(alice, spender), replacement);
        assertTrue(token.approve(spender, replacement));
        vm.stopPrank();
        assertEq(token.allowance(alice, spender), replacement);
        assertEq(token.allowance(alice, secondSpender), 0);
        assertEq(token.allowance(bob, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_NearMaximumFiniteAllowanceStillDecrements(uint256 delta, uint256 amount) public {
        delta = bound(delta, 1, SUPPLY);
        amount = bound(amount, 0, SUPPLY);
        uint256 grant = type(uint256).max - delta;
        assertTrue(token.approve(spender, grant));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, amount));
        assertEq(token.allowance(address(this), spender), grant - amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_RevocationSurvivesRefillingTheOwnersBalance(uint256 funding, bool unlimited) public {
        funding = bound(funding, 1, SUPPLY / 2);
        assertTrue(token.transfer(alice, funding));
        vm.prank(alice);
        assertTrue(token.approve(spender, unlimited ? type(uint256).max : funding * 2));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, funding));
        vm.prank(alice);
        assertTrue(token.approve(spender, 0));
        assertTrue(token.transfer(alice, funding));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(alice, bob, 1);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), funding);
        assertEq(token.balanceOf(bob), funding);

        // Only a new explicit approval permits spending again.
        vm.prank(alice);
        assertTrue(token.approve(spender, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 1));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), funding - 1);
        assertEq(token.balanceOf(bob), funding + 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - funding * 2);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_DirectTransfersDoNotConsumeApproval(uint256 funding, bool unlimited) public {
        funding = bound(funding, 1, SUPPLY / 2);
        uint256 grant = unlimited ? type(uint256).max : funding;
        assertTrue(token.transfer(alice, funding));
        vm.prank(alice);
        assertTrue(token.approve(spender, grant));
        vm.prank(alice);
        assertTrue(token.transfer(bob, funding));
        assertEq(token.allowance(alice, spender), grant);
        assertEq(token.balanceOf(alice), 0);

        assertTrue(token.transfer(alice, funding));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, funding));
        assertEq(token.allowance(alice, spender), unlimited ? type(uint256).max : 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), funding * 2);
        assertEq(token.balanceOf(address(this)), SUPPLY - funding * 2);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_TwoSpendersCannotExceedTheSharedBalance(uint256 funding, uint256 firstSpend) public {
        funding = bound(funding, 1, SUPPLY);
        firstSpend = bound(firstSpend, 1, funding);
        assertTrue(token.transfer(alice, funding));
        vm.startPrank(alice);
        assertTrue(token.approve(spender, funding));
        assertTrue(token.approve(secondSpender, funding));
        vm.stopPrank();
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, firstSpend));

        uint256 remaining = funding - firstSpend;
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, remaining, remaining + 1)
        );
        vm.prank(secondSpender);
        token.transferFrom(alice, bob, remaining + 1);
        assertEq(token.allowance(alice, spender), remaining);
        assertEq(token.allowance(alice, secondSpender), funding);
        assertEq(token.balanceOf(alice), remaining);
        assertEq(token.balanceOf(bob), firstSpend);

        vm.prank(secondSpender);
        assertTrue(token.transferFrom(alice, bob, remaining));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), funding);
        assertEq(token.allowance(alice, secondSpender), firstSpend);
        assertEq(token.balanceOf(address(this)), SUPPLY - funding);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_TransferRoundTripRestoresBothBalances(uint256 aliceFunding, uint256 bobFunding, uint256 amount)
        public
    {
        aliceFunding = bound(aliceFunding, 0, SUPPLY);
        bobFunding = bound(bobFunding, 0, SUPPLY - aliceFunding);
        amount = bound(amount, 0, aliceFunding);
        assertTrue(token.transfer(alice, aliceFunding));
        assertTrue(token.transfer(bob, bobFunding));
        vm.prank(alice);
        assertTrue(token.transfer(bob, amount));
        assertEq(token.balanceOf(alice), aliceFunding - amount);
        assertEq(token.balanceOf(bob), bobFunding + amount);
        vm.prank(bob);
        assertTrue(token.transfer(alice, amount));
        assertEq(token.balanceOf(alice), aliceFunding);
        assertEq(token.balanceOf(bob), bobFunding);
        assertEq(token.balanceOf(address(this)), SUPPLY - aliceFunding - bobFunding);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_SplitTransfersMatchCombinedTransfer(uint256 funding, uint256 first, uint256 second) public {
        funding = bound(funding, 0, SUPPLY);
        first = bound(first, 0, funding);
        second = bound(second, 0, funding - first);
        ConditionalsIMD combined = new ConditionalsIMD();
        assertTrue(token.transfer(alice, funding));
        assertTrue(combined.transfer(alice, funding));
        vm.startPrank(alice);
        assertTrue(token.transfer(bob, first));
        assertTrue(token.transfer(bob, second));
        assertTrue(combined.transfer(bob, first + second));
        vm.stopPrank();
        assertEq(token.balanceOf(alice), combined.balanceOf(alice));
        assertEq(token.balanceOf(bob), combined.balanceOf(bob));
        assertEq(token.balanceOf(bob), first + second);
        assertEq(token.balanceOf(alice), funding - first - second);
        assertEq(token.balanceOf(address(this)), SUPPLY - funding);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(combined.totalSupply(), SUPPLY);
    }

    function testFuzz_InsufficientBalancePreservesFiniteOrUnlimitedApproval(
        uint256 funding,
        uint256 excess,
        bool unlimited
    ) public {
        funding = bound(funding, 0, SUPPLY);
        excess = bound(excess, 1, type(uint256).max - 1 - funding);
        uint256 attempted = funding + excess;
        uint256 grant = unlimited ? type(uint256).max : attempted;
        assertTrue(token.transfer(alice, funding));
        vm.prank(alice);
        assertTrue(token.approve(spender, grant));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, funding, attempted)
        );
        vm.prank(spender);
        token.transferFrom(alice, bob, attempted);
        assertEq(token.allowance(alice, spender), grant);
        assertEq(token.balanceOf(alice), funding);
        assertEq(token.balanceOf(bob), 0);

        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, funding));
        assertEq(token.allowance(alice, spender), unlimited ? type(uint256).max : grant - funding);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), funding);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_InvalidReceiverPreservesFiniteOrUnlimitedApproval(
        uint256 funding,
        uint256 amount,
        uint256 grant,
        bool unlimited
    ) public {
        funding = bound(funding, 0, SUPPLY);
        amount = bound(amount, 0, funding);
        grant = unlimited ? type(uint256).max : bound(grant, amount, type(uint256).max - 1);
        assertTrue(token.transfer(alice, funding));
        vm.prank(alice);
        assertTrue(token.approve(spender, grant));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(alice, address(0), amount);
        assertEq(token.allowance(alice, spender), grant);
        assertEq(token.balanceOf(alice), funding);
        assertEq(token.balanceOf(address(0)), 0);

        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, amount));
        assertEq(token.allowance(alice, spender), unlimited ? type(uint256).max : grant - amount);
        assertEq(token.balanceOf(alice), funding - amount);
        assertEq(token.balanceOf(bob), amount);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
