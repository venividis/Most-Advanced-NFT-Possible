// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Locker} from "../src/Locker.sol";

contract CallbackToken {
    mapping(address => uint256) public balanceOf;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        (bool ok,) = from.call(abi.encodeWithSignature("tokensToSend()"));
        require(ok, "callback failed");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract LockerTest is Test {
    Locker private locker;
    CallbackToken private token;
    bool private callbackAttempted;
    bool private callbackBlocked;

    function setUp() public {
        locker = new Locker();
        token = new CallbackToken();
        token.mint(address(this), 10);
        vm.warp(1_000_000);
    }

    function tokensToSend() external {
        require(msg.sender == address(token), "not token");
        callbackAttempted = true;
        (bool ok, bytes memory reason) = address(locker).call(
            abi.encodeCall(Locker.lock, (address(token), 1, uint64(block.timestamp + 1 days)))
        );
        callbackBlocked = !ok && bytes4(reason) == Locker.Reentrant.selector;
    }

    function test_callbackCannotNestBalanceMeasurement() public {
        locker.lock(address(token), 10, uint64(block.timestamp + 1 days));

        assertTrue(callbackAttempted, "the token did not try its callback");
        assertTrue(callbackBlocked, "the nested lock was not rejected");
        assertEq(locker.count(), 1, "a nested liability was recorded");
        assertEq(locker.totalLocked(address(token)), 10, "the deposit was miscounted");
        assertEq(token.balanceOf(address(locker)), 10, "vault balance differs from its books");
    }
}
