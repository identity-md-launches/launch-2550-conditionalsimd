// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ConditionalsIMD} from "../src/ConditionalsIMD.sol";

/// @dev A closed set of holders and an independent ledger for randomized transaction sequences.
contract TokenHandler is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    ConditionalsIMD public immutable token;
    address[4] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(ConditionalsIMD token_) {
        token = token_;
        actors[0] = makeAddr("invariant holder A");
        actors[1] = makeAddr("invariant holder B");
        actors[2] = makeAddr("invariant holder C");
        actors[3] = makeAddr("invariant holder D");
        expectedBalance[actors[0]] = SUPPLY;
    }

    function transfer(uint8 fromIndex, uint8 toIndex, uint256 rawAmount) external {
        address from = actors[fromIndex % actors.length];
        address to = actors[toIndex % actors.length];
        uint256 amount = bound(rawAmount, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function approve(uint8 ownerIndex, uint8 spenderIndex, uint256 rawAmount, bool unlimited) external {
        address owner = actors[ownerIndex % actors.length];
        address spender = actors[spenderIndex % actors.length];
        // Finite approvals may exceed the entire supply; only MAX is unlimited.
        uint256 amount = unlimited ? type(uint256).max : bound(rawAmount, 0, type(uint256).max - 1);
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function transferFrom(uint8 fromIndex, uint8 toIndex, uint8 spenderIndex, uint256 rawAmount) external {
        address from = actors[fromIndex % actors.length];
        address to = actors[toIndex % actors.length];
        address spender = actors[spenderIndex % actors.length];
        uint256 allowance = expectedAllowance[from][spender];
        uint256 limit = expectedBalance[from] < allowance ? expectedBalance[from] : allowance;
        uint256 amount = bound(rawAmount, 0, limit);
        vm.prank(spender);
        assertTrue(token.transferFrom(from, to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
        if (allowance != type(uint256).max) {
            expectedAllowance[from][spender] -= amount;
        }
    }

    function rejectedSpend(uint8 fromIndex, uint8 toIndex, uint8 spenderIndex) external {
        address from = actors[fromIndex % actors.length];
        address to = actors[toIndex % actors.length];
        address spender = actors[spenderIndex % actors.length];
        uint256 allowance = expectedAllowance[from][spender];
        uint256 balance = expectedBalance[from];
        uint256 amount = (allowance < balance ? allowance : balance) + 1;
        bytes memory reason = allowance < amount
            ? abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowance, amount)
            : abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount);
        _assertRejected(spender, abi.encodeCall(token.transferFrom, (from, to, amount)), reason);
    }

    function revoke(uint8 ownerIndex, uint8 spenderIndex) external {
        address owner = actors[ownerIndex % actors.length];
        address spender = actors[spenderIndex % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, 0));
        expectedAllowance[owner][spender] = 0;
    }

    function rejectedTransfer(uint8 fromIndex, uint8 toIndex, uint256 rawAmount) external {
        address from = actors[fromIndex % actors.length];
        address to = actors[toIndex % actors.length];
        uint256 balance = expectedBalance[from];
        uint256 amount = bound(rawAmount, balance + 1, type(uint256).max);
        _assertRejected(
            from,
            abi.encodeCall(token.transfer, (to, amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount)
        );
    }

    function rejectedTransferToZero(uint8 fromIndex, uint256 rawAmount) external {
        address from = actors[fromIndex % actors.length];
        uint256 amount = bound(rawAmount, 0, expectedBalance[from]);
        _assertRejected(
            from,
            abi.encodeCall(token.transfer, (address(0), amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
        );
    }

    function rejectedApprovalToZero(uint8 ownerIndex, uint256 amount) external {
        address owner = actors[ownerIndex % actors.length];
        _assertRejected(
            owner,
            abi.encodeCall(token.approve, (address(0), amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0))
        );
    }

    function rejectedTransferFromToZero(uint8 fromIndex, uint8 spenderIndex, uint256 rawAmount) external {
        address from = actors[fromIndex % actors.length];
        address spender = actors[spenderIndex % actors.length];
        uint256 allowance = expectedAllowance[from][spender];
        uint256 balance = expectedBalance[from];
        uint256 amount = bound(rawAmount, 0, allowance < balance ? allowance : balance);
        _assertRejected(
            spender,
            abi.encodeCall(token.transferFrom, (from, address(0), amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
        );
    }

    function _assertRejected(address caller, bytes memory data, bytes memory reason) internal {
        vm.prank(caller);
        (bool success, bytes memory returned) = address(token).call(data);
        assertFalse(success, "invalid operation must revert");
        assertEq(returned, reason, "must reject for the intended reason, not an unrelated panic");
        // No ghost state changes: the invariant checks every balance and allowance
        // after this action, so a failed call must be atomic for every actor.
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract ConditionalsIMDInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;
    ConditionalsIMD internal token;
    TokenHandler internal handler;

    function setUp() public {
        token = new ConditionalsIMD();
        handler = new TokenHandler(token);
        assertTrue(token.transfer(handler.actors(0), SUPPLY));

        bytes4[] memory selectors = new bytes4[](9);
        selectors[0] = TokenHandler.transfer.selector;
        selectors[1] = TokenHandler.approve.selector;
        selectors[2] = TokenHandler.transferFrom.selector;
        selectors[3] = TokenHandler.rejectedSpend.selector;
        selectors[4] = TokenHandler.revoke.selector;
        selectors[5] = TokenHandler.rejectedTransfer.selector;
        selectors[6] = TokenHandler.rejectedTransferToZero.selector;
        selectors[7] = TokenHandler.rejectedApprovalToZero.selector;
        selectors[8] = TokenHandler.rejectedTransferFromToZero.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_SupplyBalancesAndAllowancesMatchIndependentLedger() public view {
        assertEq(token.name(), "ConditionalsIMD");
        assertEq(token.symbol(), "CONDITIONAL");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        uint256 accounted;
        for (uint256 i; i < 4; ++i) {
            address actor = handler.actors(i);
            assertEq(token.balanceOf(actor), handler.expectedBalance(actor));
            assertEq(token.allowance(actor, address(0)), 0);
            assertEq(token.allowance(address(0), actor), 0);
            accounted += token.balanceOf(actor);
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actors(j);
                assertEq(token.allowance(actor, spender), handler.expectedAllowance(actor, spender));
            }
        }
        assertEq(accounted, SUPPLY);
    }

    /// @dev Pin a productive sequence so the handler cannot pass only by moving zero.
    function test_HandlerSequenceSpendsRevokesAndRecoversAfterFailures() public {
        handler.transfer(0, 1, SUPPLY / 2);
        invariant_SupplyBalancesAndAllowancesMatchIndependentLedger();
        handler.approve(1, 2, SUPPLY / 2, false);
        invariant_SupplyBalancesAndAllowancesMatchIndependentLedger();
        handler.transferFrom(1, 3, 2, SUPPLY / 4);
        invariant_SupplyBalancesAndAllowancesMatchIndependentLedger();
        handler.rejectedTransferFromToZero(1, 2, SUPPLY / 4);
        invariant_SupplyBalancesAndAllowancesMatchIndependentLedger();
        handler.rejectedSpend(1, 3, 2);
        invariant_SupplyBalancesAndAllowancesMatchIndependentLedger();
        handler.revoke(1, 2);
        invariant_SupplyBalancesAndAllowancesMatchIndependentLedger();
        handler.rejectedSpend(1, 3, 2);
        invariant_SupplyBalancesAndAllowancesMatchIndependentLedger();
        handler.rejectedTransfer(3, 0, type(uint256).max);
        invariant_SupplyBalancesAndAllowancesMatchIndependentLedger();
        handler.rejectedTransferToZero(3, 1);
        invariant_SupplyBalancesAndAllowancesMatchIndependentLedger();
        handler.rejectedApprovalToZero(3, type(uint256).max);
        invariant_SupplyBalancesAndAllowancesMatchIndependentLedger();
        handler.approve(1, 2, 0, true);
        invariant_SupplyBalancesAndAllowancesMatchIndependentLedger();
        handler.transferFrom(1, 3, 2, SUPPLY / 4);
        invariant_SupplyBalancesAndAllowancesMatchIndependentLedger();
        handler.rejectedSpend(1, 3, 2);
        invariant_SupplyBalancesAndAllowancesMatchIndependentLedger();
        handler.approve(3, 3, type(uint256).max - 1, false);
        invariant_SupplyBalancesAndAllowancesMatchIndependentLedger();
        handler.transferFrom(3, 3, 3, 1);
        invariant_SupplyBalancesAndAllowancesMatchIndependentLedger();

        assertEq(token.balanceOf(handler.actors(1)), 0);
        assertEq(token.balanceOf(handler.actors(3)), SUPPLY / 2);
        assertEq(token.allowance(handler.actors(1), handler.actors(2)), type(uint256).max);
        assertEq(token.allowance(handler.actors(3), handler.actors(3)), type(uint256).max - 2);
    }
}

