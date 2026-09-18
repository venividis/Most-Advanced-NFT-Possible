// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {GateFacet, GateFacetPoolKey, GateFacetSwapParams, GateFacetModifyLiquidityParams} from "../src/GateFacet.sol";
import {IHubSection} from "../src/Facet.sol";
import {Hook} from "../src/lib/Hook.sol";

contract GateFacetHubMock {
    uint256 public section;
    address public owner;
    function sectionOf(uint256) external view returns (uint256) { return section; }
    function ownerOf(uint256) external view returns (address) { return owner; }
    function set(uint256 section_, address owner_) external { section = section_; owner = owner_; }
}

contract GateFacetTest is Test {
    GateFacetHubMock hub;
    GateFacet hook;
    address manager = address(0xBEEF);

    function setUp() public {
        hub = new GateFacetHubMock();
        hub.set(0, address(this));
        hook = new GateFacet(manager, IHubSection(address(hub)), 7, 500, 30_000, 100, 200);
    }

    function key() private view returns (GateFacetPoolKey memory) {
        return GateFacetPoolKey(address(1), address(2), Hook.DYNAMIC_FEE, 60, address(hook));
    }

    function test_combinesAllThreePermissionsAndGuards() public {
        assertEq(uint256(hook.flags()), uint256(Hook.BEFORE_INITIALIZE | Hook.BEFORE_SWAP | Hook.BEFORE_REMOVE_LIQUIDITY));
        vm.prank(manager);
        assertEq(uint256(uint32(hook.beforeInitialize(address(this), key(), 1))), uint256(uint32(hook.beforeInitialize.selector)));
        vm.warp(99);
        vm.prank(manager);
        vm.expectRevert(abi.encodeWithSelector(GateFacet.NotOpenYet.selector, uint64(100)));
        hook.beforeSwap(address(this), key(), GateFacetSwapParams(false, 1, 1), "");
        vm.warp(100);
        vm.prank(manager);
        (, , uint24 fee) = hook.beforeSwap(address(this), key(), GateFacetSwapParams(false, 1, 1), "");
        assertEq(uint256(fee), uint256(hook.fee() | Hook.OVERRIDE_FEE));
        vm.prank(manager);
        vm.expectRevert(abi.encodeWithSelector(GateFacet.StillLocked.selector, uint64(200)));
        hook.beforeRemoveLiquidity(address(this), key(), GateFacetModifyLiquidityParams(-60, 60, -1, 0), "");
    }

    function test_onlyTokenOwnerCanSyncArtworkFee() public {
        hub.set(type(uint256).max, address(0xCAFE));
        vm.expectRevert(GateFacet.NotTokenOwner.selector);
        hook.syncFee();
        vm.prank(address(0xCAFE));
        hook.syncFee();
        assertEq(hook.section(), type(uint256).max);
    }
}
