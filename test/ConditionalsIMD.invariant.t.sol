// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
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
        uint256 amount = unlimited ? type(uint256).max : bound(rawAmount, 0, SUPPLY);
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
        vm.prank(spender);
        (bool success,) = address(token).call(abi.encodeCall(token.transferFrom, (from, to, amount)));
        assertFalse(success, "overspending must fail without changing the ledger");
    }
}

contract ConditionalsIMDInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;
    ConditionalsIMD internal token;
    TokenHandler internal handler;

    function setUp() public {
        token = new ConditionalsIMD();
        handler = new TokenHandler(token);
        assertTrue(token.transfer(handler.actors(0), SUPPLY));

        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = TokenHandler.transfer.selector;
        selectors[1] = TokenHandler.approve.selector;
        selectors[2] = TokenHandler.transferFrom.selector;
        selectors[3] = TokenHandler.rejectedSpend.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_SupplyBalancesAndAllowancesMatchIndependentLedger() public view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        uint256 accounted;
        for (uint256 i; i < 4; ++i) {
            address actor = handler.actors(i);
            assertEq(token.balanceOf(actor), handler.expectedBalance(actor));
            accounted += token.balanceOf(actor);
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actors(j);
                assertEq(token.allowance(actor, spender), handler.expectedAllowance(actor, spender));
            }
        }
        assertEq(accounted, SUPPLY);
    }
}

