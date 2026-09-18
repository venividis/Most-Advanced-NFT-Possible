// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Mul} from "./lib/Mul.sol";
import {Tick} from "./lib/Tick.sol";

interface ILaunchLedger {
    function launchedBy(address coin) external view returns (uint256);
    function launcher(address coin) external view returns (address);
    function mayActAs(uint256 token, address who) external view returns (bool);
}

interface IV4PositionManagerRead {
    function getPoolAndPositionInfo(uint256 tokenId)
        external view returns (V4PositionPlanner.PoolKey memory poolKey, uint256 info);
}

/// @notice Builds canonical Uniswap v4 PositionManager calldata without ever
///         taking custody, receiving an approval, or executing it.
/// @dev The browser deliberately has no recursive ABI encoder. This contract
///      is the narrow replacement: Solidity encodes the two-action plans and
///      the caller's wallet sends the returned bytes straight to the official
///      PositionManager. Position ownership is the authority over liquidity
///      and accrued LP fees; that owner is always an explicit input.
contract V4PositionPlanner {
    using Mul for uint256;

    struct PoolKey {
        address currency0;
        address currency1;
        uint24 fee;
        int24 tickSpacing;
        address hooks;
    }

    struct MintRequest {
        PoolKey key;
        int24 tickLower;
        int24 tickUpper;
        uint160 sqrtPriceX96;
        uint128 amount0Max;
        uint128 amount1Max;
        address positionOwner;
        uint256 deadline;
        bytes hookData;
    }

    ILaunchLedger public immutable KILN;
    address public immutable POSITION_MANAGER;
    address public immutable PERMIT2;

    uint8 private constant INCREASE_LIQUIDITY = 0x00;
    uint8 private constant DECREASE_LIQUIDITY = 0x01;
    uint8 private constant MINT_POSITION = 0x02;
    uint8 private constant BURN_POSITION = 0x03;
    uint8 private constant SETTLE_PAIR = 0x0d;
    uint8 private constant TAKE_PAIR = 0x11;

    bytes4 private constant MODIFY = bytes4(keccak256("modifyLiquidities(bytes,uint256)"));

    error NotLaunchOwner();
    error WrongCoin();
    error BadCurrencyOrder();
    error BadRange();
    error BadSpacing();
    error BadPrice();
    error ZeroLiquidity();
    error ZeroAddress();
    error DeadlinePassed();

    constructor(ILaunchLedger kiln, address positionManager, address permit2) {
        KILN = kiln;
        POSITION_MANAGER = positionManager;
        PERMIT2 = permit2;
    }

    /// @notice A complete mint plan for a coin made by this Kiln.
    /// @dev `msg.sender` must still own the IPSEITY token that signed the
    ///      launch (or be that token's Reach). This protects the advertised
    ///      launch flow. It cannot prevent strangers from making unrelated
    ///      permissionless pools with tokens they own.
    function mintPlan(uint256 token, address coin, MintRequest calldata r)
        external view returns (uint256 liquidity, uint256 value, bytes memory data)
    {
        if (KILN.launchedBy(coin) != token || token == 0) revert WrongCoin();
        if (KILN.launcher(coin) != msg.sender || !KILN.mayActAs(token, msg.sender)) {
            revert NotLaunchOwner();
        }
        _validate(r.key, r.tickLower, r.tickUpper, r.sqrtPriceX96, r.positionOwner, r.deadline);
        if (coin != r.key.currency0 && coin != r.key.currency1) revert WrongCoin();

        liquidity = liquidityForAmounts(
            r.sqrtPriceX96, r.tickLower, r.tickUpper, r.amount0Max, r.amount1Max
        );
        if (liquidity == 0) revert ZeroLiquidity();

        bytes memory actions = abi.encodePacked(MINT_POSITION, SETTLE_PAIR);
        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(
            r.key, r.tickLower, r.tickUpper, liquidity,
            r.amount0Max, r.amount1Max, r.positionOwner, r.hookData
        );
        params[1] = abi.encode(r.key.currency0, r.key.currency1);
        data = abi.encodeWithSelector(MODIFY, abi.encode(actions, params), r.deadline);
        value = _nativeValue(r.key, r.amount0Max, r.amount1Max);
    }

    /// @notice Add liquidity to a position. PositionManager itself enforces
    ///         ownership or approval of `positionId`.
    function increasePlan(
        uint256 positionId,
        uint256 liquidity,
        uint128 amount0Max,
        uint128 amount1Max,
        uint256 deadline,
        bytes calldata hookData
    ) external view returns (uint256 value, bytes memory data) {
        if (deadline < block.timestamp) revert DeadlinePassed();
        if (liquidity == 0) revert ZeroLiquidity();
        PoolKey memory key = _positionKey(positionId);
        bytes memory actions = abi.encodePacked(INCREASE_LIQUIDITY, SETTLE_PAIR);
        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(positionId, liquidity, amount0Max, amount1Max, hookData);
        params[1] = abi.encode(key.currency0, key.currency1);
        data = abi.encodeWithSelector(MODIFY, abi.encode(actions, params), deadline);
        value = _nativeValue(key, amount0Max, amount1Max);
    }

    /// @notice Remove liquidity and send principal plus collected fees to the
    ///         chosen recipient. PositionManager enforces position authority.
    function decreasePlan(
        uint256 positionId,
        uint256 liquidity,
        uint128 amount0Min,
        uint128 amount1Min,
        address recipient,
        uint256 deadline,
        bytes calldata hookData
    ) external view returns (bytes memory data) {
        if (deadline < block.timestamp) revert DeadlinePassed();
        if (liquidity == 0) revert ZeroLiquidity();
        if (recipient == address(0)) revert ZeroAddress();
        PoolKey memory key = _positionKey(positionId);
        bytes memory actions = abi.encodePacked(DECREASE_LIQUIDITY, TAKE_PAIR);
        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(positionId, liquidity, amount0Min, amount1Min, hookData);
        params[1] = abi.encode(key.currency0, key.currency1, recipient);
        data = abi.encodeWithSelector(MODIFY, abi.encode(actions, params), deadline);
    }

    /// @notice Collect accrued fees without changing the position's liquidity.
    function collectPlan(
        uint256 positionId,
        address recipient,
        uint256 deadline,
        bytes calldata hookData
    ) external view returns (bytes memory data) {
        if (deadline < block.timestamp) revert DeadlinePassed();
        if (recipient == address(0)) revert ZeroAddress();
        PoolKey memory key = _positionKey(positionId);
        bytes memory actions = abi.encodePacked(DECREASE_LIQUIDITY, TAKE_PAIR);
        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(positionId, uint256(0), uint128(0), uint128(0), hookData);
        params[1] = abi.encode(key.currency0, key.currency1, recipient);
        data = abi.encodeWithSelector(MODIFY, abi.encode(actions, params), deadline);
    }

    /// @notice Burn an emptied position and send any final principal or fees
    ///         to the chosen recipient.
    function burnPlan(
        uint256 positionId,
        uint128 amount0Min,
        uint128 amount1Min,
        address recipient,
        uint256 deadline,
        bytes calldata hookData
    ) external view returns (bytes memory data) {
        if (deadline < block.timestamp) revert DeadlinePassed();
        if (recipient == address(0)) revert ZeroAddress();
        PoolKey memory key = _positionKey(positionId);
        bytes memory actions = abi.encodePacked(BURN_POSITION, TAKE_PAIR);
        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(positionId, amount0Min, amount1Min, hookData);
        params[1] = abi.encode(key.currency0, key.currency1, recipient);
        data = abi.encodeWithSelector(MODIFY, abi.encode(actions, params), deadline);
    }

    /// @notice The greatest liquidity supported by both supplied amount caps
    ///         at the stated pool price and range.
    function liquidityForAmounts(
        uint160 sqrtPriceX96,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount0Max,
        uint128 amount1Max
    ) public pure returns (uint256 liquidity) {
        if (tickLower >= tickUpper) revert BadRange();
        uint160 a = Tick.sqrtAt(tickLower);
        uint160 b = Tick.sqrtAt(tickUpper);
        if (sqrtPriceX96 < Tick.MIN_SQRT || sqrtPriceX96 >= Tick.MAX_SQRT) revert BadPrice();

        if (sqrtPriceX96 <= a) return _for0(a, b, amount0Max);
        if (sqrtPriceX96 >= b) return Mul.mulDiv(amount1Max, 1 << 96, uint256(b) - a);

        uint256 l0 = _for0(sqrtPriceX96, b, amount0Max);
        uint256 l1 = Mul.mulDiv(amount1Max, 1 << 96, uint256(sqrtPriceX96) - a);
        return l0 < l1 ? l0 : l1;
    }

    function _for0(uint160 a, uint160 b, uint128 amount) private pure returns (uint256) {
        uint256 middle = Mul.mulDiv(a, b, 1 << 96);
        return Mul.mulDiv(amount, middle, uint256(b) - a);
    }

    function _validate(
        PoolKey calldata key,
        int24 lower,
        int24 upper,
        uint160 sqrtPriceX96,
        address owner,
        uint256 deadline
    ) private view {
        if (POSITION_MANAGER == address(0) || owner == address(0)) revert ZeroAddress();
        if (key.currency0 >= key.currency1) revert BadCurrencyOrder();
        if (key.tickSpacing <= 0 || lower >= upper) revert BadRange();
        if (lower % key.tickSpacing != 0 || upper % key.tickSpacing != 0) revert BadSpacing();
        if (sqrtPriceX96 < Tick.MIN_SQRT || sqrtPriceX96 >= Tick.MAX_SQRT) revert BadPrice();
        if (deadline < block.timestamp) revert DeadlinePassed();
    }

    function _positionKey(uint256 positionId) private view returns (PoolKey memory key) {
        (key,) = IV4PositionManagerRead(POSITION_MANAGER).getPoolAndPositionInfo(positionId);
        if (key.currency0 >= key.currency1) revert BadCurrencyOrder();
    }

    function _nativeValue(PoolKey memory key, uint128 amount0, uint128 amount1)
        private pure returns (uint256)
    {
        if (key.currency0 == address(0)) return amount0;
        if (key.currency1 == address(0)) return amount1;
        return 0;
    }
}
