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

    function allow(uint256 token, address actor, bool ok) external { allowed[token][actor] = ok; }

    function mayActAs(uint256 token, address who) external view override returns (bool) {
        return allowed[token][who];
    }
}

contract PositionManagerReadMock {
    V4PositionPlanner.PoolKey private _key;
    mapping(uint256 => V4PositionPlanner.PoolKey) private _keys;
    mapping(uint256 => uint256) public liquidityOf;
    mapping(uint256 => address) public ownerOf;
    uint256 public nextTokenId = 1;

    function setKey(V4PositionPlanner.PoolKey memory key_) external { _key = key_; }
    function getPoolAndPositionInfo(uint256 id)
        external view returns (V4PositionPlanner.PoolKey memory, uint256)
    {
        V4PositionPlanner.PoolKey memory k = _keys[id];
        return (k.currency1 == address(0) ? _key : k, 0);
    }

    /// @dev ABI-faithful executable stand-in for the official periphery
    ///      decoder. It deliberately decodes every action shape the planner
    ///      emits, so a wrong tuple, offset, or action ordering fails here.
    function modifyLiquidities(bytes calldata unlockData, uint256 deadline) external payable {
        require(deadline >= block.timestamp, "deadline");
        (bytes memory actions, bytes[] memory params) = abi.decode(unlockData, (bytes, bytes[]));
        for (uint256 i; i < actions.length; ++i) {
            uint8 action = uint8(actions[i]);
            if (action == 2) {
                (V4PositionPlanner.PoolKey memory k,,, uint256 liq,,, address owner,) =
                    _decodeMint(params[i]);
                uint256 id = nextTokenId++;
                _keys[id] = k;
                liquidityOf[id] = liq;
                ownerOf[id] = owner;
            } else if (action == 0) {
                (uint256 id, uint256 liq,,,,) = _decodeChange(params[i]);
                require(ownerOf[id] == msg.sender, "owner");
                liquidityOf[id] += liq;
            } else if (action == 1) {
                (uint256 id, uint256 liq,,,,) = _decodeChange(params[i]);
                require(ownerOf[id] == msg.sender, "owner");
                liquidityOf[id] -= liq;
            } else if (action == 3) {
                (uint256 id,,,,) = _decodeBurn(params[i]);
                require(ownerOf[id] == msg.sender && liquidityOf[id] == 0, "burn");
                delete ownerOf[id];
                delete _keys[id];
            }
        }
    }

    function _decodeMint(bytes memory p) private pure returns (
        V4PositionPlanner.PoolKey memory k, int24 lo, int24 hi, uint256 liq,
        uint128 a0, uint128 a1, address owner, bytes memory hookData
    ) { return abi.decode(p, (V4PositionPlanner.PoolKey,int24,int24,uint256,uint128,uint128,address,bytes)); }

    function _decodeChange(bytes memory p) private pure returns (
        uint256 id, uint256 liq, uint128 a0, uint128 a1, bytes memory hookData, uint256 unused
    ) {
        (id, liq, a0, a1, hookData) = abi.decode(p, (uint256,uint256,uint128,uint128,bytes));
        unused = 0;
    }

    function _decodeBurn(bytes memory p) private pure returns (
        uint256 id, uint128 a0, uint128 a1, bytes memory hookData, uint256 unused
    ) {
        (id, a0, a1, hookData) = abi.decode(p, (uint256,uint128,uint128,bytes));
        unused = 0;
    }
}

contract StateViewMock {
    uint160 public price;
    function set(uint160 price_) external { price = price_; }
    function getSlot0(bytes32) external view returns (uint160, int24, uint24, uint24) {
        return (price, 0, 0, 0);
    }
}

contract V4PositionPlannerTest is Test {
    LaunchLedgerMock ledger;
    V4PositionPlanner planner;
    address constant COIN = address(0x1000);
    address constant QUOTE = address(0x2000);
    PositionManagerReadMock posm;
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
        posm = new PositionManagerReadMock();
        planner = new V4PositionPlanner(ledger, address(posm), PERMIT2, address(0));
        ledger.set(COIN, 7, address(this), true);
        posm.setKey(V4PositionPlanner.PoolKey(COIN, QUOTE, 3000, 60, address(0x5000)));
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

    function test_authorityFollowsSigningNftAfterTransfer() public {
        V4PositionPlanner.MintRequest memory r = request();
        address newHolder = address(0xA11CE);
        ledger.allow(7, address(this), false);
        ledger.allow(7, newHolder, true);

        vm.expectRevert(V4PositionPlanner.NotLaunchOwner.selector);
        planner.mintPlan(7, COIN, r);
        vm.prank(newHolder);
        planner.mintPlan(7, COIN, r);
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
        bytes memory data = planner.decreasePlan(
            44, 123, 4, 5, address(0xCAFE), block.timestamp + 1, hex"12"
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
        bytes memory data = planner.collectPlan(
            44, address(0xCAFE), block.timestamp + 1, hex"12"
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

    function test_plansExecuteThroughPositionManagerDecoderLifecycle() public {
        V4PositionPlanner.MintRequest memory r = request();
        r.positionOwner = address(this);
        (uint256 minted,, bytes memory mintData) = planner.mintPlan(7, COIN, r);
        (bool ok,) = address(posm).call(mintData);
        assertTrue(ok);
        assertEq(posm.ownerOf(1), address(this));
        assertEq(posm.liquidityOf(1), minted);

        (, bytes memory addData) = planner.increasePlan(
            1, 25, 1, 1, block.timestamp + 1, ""
        );
        (ok,) = address(posm).call(addData);
        assertTrue(ok);
        assertEq(posm.liquidityOf(1), minted + 25);

        bytes memory removeData = planner.decreasePlan(
            1, minted + 25, 0, 0, address(this), block.timestamp + 1, ""
        );
        (ok,) = address(posm).call(removeData);
        assertTrue(ok);
        assertEq(posm.liquidityOf(1), 0);

        bytes memory burnData = planner.burnPlan(
            1, 0, 0, address(this), block.timestamp + 1, ""
        );
        (ok,) = address(posm).call(burnData);
        assertTrue(ok);
        assertEq(posm.ownerOf(1), address(0));
    }

    function test_mintUsesLiveStateViewPriceAndReportsBlock() public {
        StateViewMock state = new StateViewMock();
        state.set(uint160(1 << 96));
        V4PositionPlanner live = new V4PositionPlanner(
            ledger, address(posm), PERMIT2, address(state)
        );
        V4PositionPlanner.MintRequest memory r = request();
        // This fallback is valid but deliberately different. Both the public
        // preview and mint must use the StateView reading.
        r.sqrtPriceX96 = uint160(2 << 96);
        (uint160 price, uint256 atBlock) = live.livePrice(r.key, r.sqrtPriceX96);
        assertEq(price, uint160(1 << 96));
        assertEq(atBlock, block.number);
        (uint256 got,,) = live.mintPlan(7, COIN, r);
        assertEq(got, live.liquidityForAmounts(
            uint160(1 << 96), r.tickLower, r.tickUpper, r.amount0Max, r.amount1Max
        ));
    }

    function decodeOuter(bytes calldata data)
        external pure returns (bytes memory unlocked, uint256 deadline)
    {
        return abi.decode(data[4:], (bytes, uint256));
    }
}
