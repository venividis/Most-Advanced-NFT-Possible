// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {V4PositionPlanner, ILaunchLedger} from "../src/V4PositionPlanner.sol";

contract LaunchLedgerMock is ILaunchLedger {
    mapping(address => uint256) public override launchedBy;
    mapping(address => address) public override launcher;
    mapping(uint256 => mapping(address => bool)) public allowed;

    function set(address coin, uint256 token, address actor, bool ok) external {
        launchedBy[coin] = token;
        launcher[coin] = actor;
        allowed[token][actor] = ok;
    }

    function mayActAs(uint256 token, address who) external view override returns (bool) {
        return allowed[token][who];
    }
}

contract V4PositionPlannerTest is Test {
    LaunchLedgerMock ledger;
    V4PositionPlanner planner;
    address constant COIN = address(0x1000);
    address constant QUOTE = address(0x2000);
    address constant POSM = address(0x3000);
    address constant PERMIT2 = address(0x4000);

    struct Key {
        address currency0;
        address currency1;
        uint24 fee;
        int24 tickSpacing;
        address hooks;
    }

    function setUp() public {
        ledger = new LaunchLedgerMock();
        planner = new V4PositionPlanner(ledger, POSM, PERMIT2);
        ledger.set(COIN, 7, address(this), true);
    }

    function request() private view returns (V4PositionPlanner.MintRequest memory r) {
        r.key = V4PositionPlanner.PoolKey(COIN, QUOTE, 3000, 60, address(0x5000));
        r.tickLower = -600;
        r.tickUpper = 600;
        r.sqrtPriceX96 = uint160(1 << 96);
        r.amount0Max = 10 ether;
        r.amount1Max = 10 ether;
        r.positionOwner = address(0xBEEF);
        r.deadline = block.timestamp + 20 minutes;
        r.hookData = hex"cafe";
    }

    function test_mintPlanIsCanonicalAndOwnerControlsPositionAndFees() public view {
        V4PositionPlanner.MintRequest memory r = request();
        (uint256 liquidity, uint256 value, bytes memory data) = planner.mintPlan(7, COIN, r);
        assertGt(liquidity, 0);
        assertEq(value, 0);
        assertEq(
            uint256(uint32(bytes4(data))),
            uint256(uint32(bytes4(keccak256("modifyLiquidities(bytes,uint256)"))))
        );

        (bytes memory unlocked, uint256 deadline) = this.decodeOuter(data);
        assertEq(deadline, r.deadline);
        (bytes memory actions, bytes[] memory params) = abi.decode(unlocked, (bytes, bytes[]));
        assertEq(actions, hex"020d"); // MINT_POSITION, SETTLE_PAIR
        assertEq(params.length, 2);

        (
            Key memory key, int24 lower, int24 upper, uint256 encodedLiquidity,
            uint128 max0, uint128 max1, address owner, bytes memory hookData
        ) = abi.decode(params[0], (Key, int24, int24, uint256, uint128, uint128, address, bytes));
        assertEq(key.currency0, COIN);
        assertEq(key.currency1, QUOTE);
        assertEq(lower, r.tickLower);
        assertEq(upper, r.tickUpper);
        assertEq(encodedLiquidity, liquidity);
        assertEq(max0, r.amount0Max);
        assertEq(max1, r.amount1Max);
        assertEq(owner, r.positionOwner);
        assertEq(hookData, r.hookData);

        (address settle0, address settle1) = abi.decode(params[1], (address, address));
        assertEq(settle0, COIN);
        assertEq(settle1, QUOTE);
    }

    function test_onlyCurrentLaunchTokenAuthorityCanBuildAdvertisedMint() public {
        V4PositionPlanner.MintRequest memory r = request();
        address stranger = address(0xBAD);
        vm.prank(stranger);
        vm.expectRevert(V4PositionPlanner.NotLaunchOwner.selector);
        planner.mintPlan(7, COIN, r);

        vm.expectRevert(V4PositionPlanner.WrongCoin.selector);
        planner.mintPlan(8, COIN, r);
    }

    function test_nativePairReturnsExactlyTheMaximumAsCallValue() public {
        address nativeCoin = address(0x6000);
        ledger.set(nativeCoin, 9, address(this), true);
        V4PositionPlanner.MintRequest memory r = request();
        r.key.currency0 = address(0);
        r.key.currency1 = nativeCoin;
        r.amount0Max = 3 ether;
        r.amount1Max = 7 ether;
        (, uint256 value,) = planner.mintPlan(9, nativeCoin, r);
        assertEq(value, 3 ether);
    }

    function test_decreaseChoosesWherePrincipalAndFeesGo() public view {
        V4PositionPlanner.PoolKey memory key =
            V4PositionPlanner.PoolKey(COIN, QUOTE, 3000, 60, address(0x5000));
        bytes memory data = planner.decreasePlan(
            key, 44, 123, 4, 5, address(0xCAFE), block.timestamp + 1, hex"12"
        );
        (bytes memory unlocked,) = this.decodeOuter(data);
        (bytes memory actions, bytes[] memory params) = abi.decode(unlocked, (bytes, bytes[]));
        assertEq(actions, hex"0111"); // DECREASE_LIQUIDITY, TAKE_PAIR
        (address c0, address c1, address recipient) =
            abi.decode(params[1], (address, address, address));
        assertEq(c0, COIN);
        assertEq(c1, QUOTE);
        assertEq(recipient, address(0xCAFE));
    }

    function test_collectPokesWithZeroLiquidityAndRoutesFees() public view {
        V4PositionPlanner.PoolKey memory key =
            V4PositionPlanner.PoolKey(COIN, QUOTE, 3000, 60, address(0x5000));
        bytes memory data = planner.collectPlan(
            key, 44, address(0xCAFE), block.timestamp + 1, hex"12"
        );
        (bytes memory unlocked,) = this.decodeOuter(data);
        (bytes memory actions, bytes[] memory params) = abi.decode(unlocked, (bytes, bytes[]));
        assertEq(actions, hex"0111");
        (uint256 id, uint256 liquidity, uint128 min0, uint128 min1, bytes memory hookData) =
            abi.decode(params[0], (uint256, uint256, uint128, uint128, bytes));
        assertEq(id, 44);
        assertEq(liquidity, 0);
        assertEq(min0, 0);
        assertEq(min1, 0);
        assertEq(hookData, hex"12");
        (, , address recipient) = abi.decode(params[1], (address, address, address));
        assertEq(recipient, address(0xCAFE));
    }

    function test_invalidRangeAndExpiredPlanAreRefused() public {
        V4PositionPlanner.MintRequest memory r = request();
        r.tickLower = 1;
        vm.expectRevert(V4PositionPlanner.BadSpacing.selector);
        planner.mintPlan(7, COIN, r);

        r = request();
        r.deadline = block.timestamp - 1;
        vm.expectRevert(V4PositionPlanner.DeadlinePassed.selector);
        planner.mintPlan(7, COIN, r);
    }

    function decodeOuter(bytes calldata data)
        external pure returns (bytes memory unlocked, uint256 deadline)
    {
        return abi.decode(data[4:], (bytes, uint256));
    }
}
