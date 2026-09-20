// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {GateFacet, GateFacetPoolKey, GateFacetSwapParams, GateFacetModifyLiquidityParams} from "../src/GateFacet.sol";
import {IHubSection} from "../src/Facet.sol";
import {Hook} from "../src/lib/Hook.sol";
import {Kiln, IHolds} from "../src/Kiln.sol";

contract GateFacetHubMock {
    uint256 public section;
    address public owner;
    function sectionOf(uint256) external view returns (uint256) { return section; }
    function ownerOf(uint256) external view returns (address) { return owner; }
    function account(uint256) external pure returns (address) { return address(0xACCA); }
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

        // Fee collection is the zero-delta form of this callback and stays
        // available while principal remains locked.
        vm.prank(manager);
        hook.beforeRemoveLiquidity(address(this), key(), GateFacetModifyLiquidityParams(-60, 60, 0, 0), "");
    }

    function test_onlyTokenOwnerCanSyncArtworkFee() public {
        hub.set(type(uint256).max, address(0xCAFE));
        vm.expectRevert(GateFacet.NotTokenOwner.selector);
        hook.syncFee();
        vm.prank(address(0xCAFE));
        hook.syncFee();
        assertEq(hook.section(), type(uint256).max);
    }

    function test_kilnPacksMinesAndDeploysCombinedRecipe() public {
        Kiln kiln = new Kiln(IHolds(address(hub)), manager);
        bytes32 arg = kiln.gateFacetArg(7, 500, 30_000, 100, 200);
        (bytes32 hash, uint16 flags) = kiln.recipeHash(2, arg);
        (bool found, bytes32 salt, address predicted) = kiln.mine(hash, flags, 0, 100_000);
        assertTrue(found);
        address deployed = kiln.deployHook(2, salt, arg);
        assertEq(deployed, predicted);
        GateFacet made = GateFacet(deployed);
        assertEq(made.TOKEN(), 7);
        assertEq(made.FLOOR(), 500);
        assertEq(made.CEILING(), 30_000);
        assertEq(made.OPENS(), 100);
        assertEq(made.UNLOCKS(), 200);
        assertEq(uint256(made.flags()), uint256(flags));
    }
}
