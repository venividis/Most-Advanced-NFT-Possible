// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Hook} from "./lib/Hook.sol";
import {Curve} from "./lib/Curve.sol";
import {IHubSection} from "./Facet.sol";

struct GateFacetPoolKey {
    address currency0;
    address currency1;
    uint24 fee;
    int24 tickSpacing;
    address hooks;
}

struct GateFacetSwapParams {
    bool zeroForOne;
    int256 amountSpecified;
    uint160 sqrtPriceLimitX96;
}

struct GateFacetModifyLiquidityParams {
    int24 tickLower;
    int24 tickUpper;
    int256 liquidityDelta;
    bytes32 salt;
}

/// @notice One immutable v4 hook combining a launch gate, liquidity lock and
///         artwork-driven dynamic fee. It has no admin or upgrade path.
contract GateFacet {
    address public immutable MANAGER;
    IHubSection public immutable HUB;
    uint256 public immutable TOKEN;
    uint256 public immutable INITIAL_SECTION;
    uint24 public immutable FLOOR;
    uint24 public immutable CEILING;
    uint64 public immutable OPENS;
    uint64 public immutable UNLOCKS;

    uint256 private _section;
    bool private _synced;

    error NotTheManager();
    error NotTokenOwner();
    error NotDynamic();
    error NotOpenYet(uint64 opens);
    error StillLocked(uint64 unlocks);
    error BadBand();

    constructor(
        address manager, IHubSection hub, uint256 token, uint24 floor_, uint24 ceiling_,
        uint64 opens, uint64 unlocks
    ) {
        if (floor_ > ceiling_ || ceiling_ > Hook.MAX_FEE) revert BadBand();
        MANAGER = manager;
        HUB = hub;
        TOKEN = token;
        INITIAL_SECTION = hub.sectionOf(token);
        FLOOR = floor_;
        CEILING = ceiling_;
        OPENS = opens;
        UNLOCKS = unlocks;
    }

    modifier onlyManager() {
        if (msg.sender != MANAGER) revert NotTheManager();
        _;
    }

    function section() public view returns (uint256) {
        return _synced ? _section : INITIAL_SECTION;
    }

    function syncFee() external {
        if (msg.sender != HUB.ownerOf(TOKEN)) revert NotTokenOwner();
        _section = HUB.sectionOf(TOKEN);
        _synced = true;
    }

    function fee() public view returns (uint24) {
        uint256 span = uint256(CEILING) - uint256(FLOOR);
        return uint24(uint256(FLOOR) + span * Curve.concentration(section()) / Curve.MAX_CONCENTRATION);
    }

    function beforeInitialize(address, GateFacetPoolKey calldata key, uint160)
        external view onlyManager returns (bytes4)
    {
        if (key.fee != Hook.DYNAMIC_FEE) revert NotDynamic();
        return GateFacet.beforeInitialize.selector;
    }

    function beforeSwap(address, GateFacetPoolKey calldata, GateFacetSwapParams calldata, bytes calldata)
        external view onlyManager returns (bytes4, int256, uint24)
    {
        if (block.timestamp < OPENS) revert NotOpenYet(OPENS);
        return (GateFacet.beforeSwap.selector, int256(0), fee() | Hook.OVERRIDE_FEE);
    }

    function beforeRemoveLiquidity(
        address, GateFacetPoolKey calldata, GateFacetModifyLiquidityParams calldata params, bytes calldata
    ) external view onlyManager returns (bytes4) {
        // PositionManager uses a zero-delta decrease to collect fees. Hold
        // principal until UNLOCKS without also stranding the fees it earned.
        if (params.liquidityDelta < 0 && block.timestamp < UNLOCKS) revert StillLocked(UNLOCKS);
        return GateFacet.beforeRemoveLiquidity.selector;
    }

    function status() external view returns (bool tradingOpen, bool liquidityFree) {
        return (block.timestamp >= OPENS, block.timestamp >= UNLOCKS);
    }

    function flags() external pure returns (uint16) {
        return uint16(Hook.BEFORE_INITIALIZE | Hook.BEFORE_SWAP | Hook.BEFORE_REMOVE_LIQUIDITY);
    }
}
