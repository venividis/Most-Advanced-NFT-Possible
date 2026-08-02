// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Kiln, Coin, Gate, PoolKey, ModifyLiquidityParams, SwapParams} from "../src/Kiln.sol";
import {Hook} from "../src/lib/Hook.sol";

/*───────────────────────────────────────────────────────────────────────────
  The launchpad, and the two things about it that fail silently.

  A hook is matched BY SELECTOR and deployed BY ADDRESS, and both of those
  are hashes of things that are easy to get almost right:

    · a callback whose signature differs from v4's by one field type has a
      different selector, so the PoolManager calls a function the hook does
      not have. With no fallback that reverts — every swap, every withdrawal,
      on every pool that trusted it. The code is there, it compiles, it
      verifies on the explorer, and it never runs.

    · a hook deployed to an address missing one of its permission bits is a
      hook whose callback the pool simply never invokes. Nothing reverts.
      Nothing warns. A lock that is never consulted looks exactly like a
      lock, right up until somebody withdraws.

  Both are checked here against the canonical signature strings and the flag
  arithmetic, rather than against what this repository believes.
───────────────────────────────────────────────────────────────────────────*/
contract KilnTest is Test {
    Kiln kiln;
    address constant MANAGER = address(0x1234);

    /// @dev Gate declares these two and must be deployed somewhere carrying
    ///      exactly them: 1<<9 | 1<<7 == 0x280.
    uint16 constant GATE_FLAGS =
        uint16(Hook.BEFORE_REMOVE_LIQUIDITY | Hook.BEFORE_SWAP);

    function setUp() public {
        kiln = new Kiln(MANAGER);
    }

    /*═══════════════ the selectors v4 will actually call ═══════════════*/

    /// @dev The load-bearing test in this file. These strings are what
    ///      v4-core hashes when it calls a hook; if `Gate`'s declarations
    ///      drift from them by one field, the PoolManager calls a function
    ///      that does not exist and every pool using the hook is bricked.
    function test_theHookSelectorsAreTheOnesV4Calls() public pure {
        assertEq(
            bytes32(Gate.beforeSwap.selector),
            bytes32(bytes4(keccak256(
                "beforeSwap(address,(address,address,uint24,int24,address),"
                "(bool,int256,uint160),bytes)"
            ))),
            "beforeSwap is not the signature v4 calls"
        );
        assertEq(
            bytes32(Gate.beforeRemoveLiquidity.selector),
            bytes32(bytes4(keccak256(
                "beforeRemoveLiquidity(address,(address,address,uint24,int24,address),"
                "(int24,int24,int256,bytes32),bytes)"
            ))),
            "beforeRemoveLiquidity is not the signature v4 calls"
        );
    }

    /// @dev The control. If the string above were wrong in the same way the
    ///      declaration is wrong, the test would pass anyway — so one known
    ///      wrong shape is asserted NOT to match.
    function test_aNearlyRightSignatureIsADifferentFunction() public pure {
        // int256 liquidityDelta written as int128: one field, four bytes
        bytes4 nearly = bytes4(keccak256(
            "beforeRemoveLiquidity(address,(address,address,uint24,int24,address),"
            "(int24,int24,int128,bytes32),bytes)"
        ));
        assertTrue(nearly != Gate.beforeRemoveLiquidity.selector,
            "a wrong field type produced the same selector, so this test proves nothing");
    }

    /*═══════════════ what an address says about a hook ═══════════════*/

    function test_theFlagsAreTheOnesThePoolManagerTests() public pure {
        assertEq(uint256(Hook.BEFORE_INITIALIZE), 1 << 13);
        assertEq(uint256(Hook.BEFORE_ADD_LIQUIDITY), 1 << 11);
        assertEq(uint256(Hook.BEFORE_REMOVE_LIQUIDITY), 1 << 9);
        assertEq(uint256(Hook.BEFORE_SWAP), 1 << 7);
        assertEq(uint256(Hook.AFTER_SWAP), 1 << 6);
        assertEq(uint256(Hook.AFTER_REMOVE_LIQUIDITY_RETURNS_DELTA), 1);
        assertEq(uint256(Hook.MASK), (1 << 14) - 1, "the mask is not fourteen bits");
        assertEq(uint256(Hook.DYNAMIC_FEE), 0x800000);
        assertEq(uint256(Hook.MAX_FEE), 1_000_000);
    }

    function test_anAddressIsReadWithoutCallingIt() public pure {
        // a made-up address whose low bits say beforeSwap and afterSwap
        address h = address(uint160(uint256(0x00AAAA0000000000000000000000000000000000C0)));
        assertTrue(Hook.has(h, Hook.BEFORE_SWAP), "0x80 bit missed");
        assertTrue(Hook.has(h, Hook.AFTER_SWAP), "0x40 bit missed");
        assertFalse(Hook.has(h, Hook.BEFORE_REMOVE_LIQUIDITY));
        assertTrue(Hook.touchesSwaps(h));
        assertFalse(Hook.guardsExits(h));
        assertFalse(Hook.inert(h));
    }

    function test_anAddressWithNoBitsIsNeverCalled() public pure {
        address h = address(uint160(uint256(0x00AAAA000000000000000000000000000000000000)));
        assertTrue(Hook.inert(h), "an address with no flags claimed to be callable");
        assertTrue(Hook.inert(address(0)));
    }

    function testFuzz_theMaskNeverReadsAboveFourteenBits(address h) public pure {
        assertLt(uint256(Hook.flags(h)), 1 << 14);
        // and the high bits are irrelevant to every question asked of it
        address raised = address(uint160(h) | (uint160(1) << 159));
        assertEq(Hook.flags(raised), Hook.flags(h),
            "a bit far above the mask changed what the address was said to do");
    }

    /*═══════════════ mining ═══════════════*/

    function test_miningFindsAnAddressCarryingExactlyTheFlags() public view {
        (bytes32 h, uint16 flags) = kiln.recipeHash(0, bytes32(0));
        assertEq(flags, GATE_FLAGS, "the recipe does not declare Gate's two callbacks");

        (bool found, bytes32 salt, address at) = kiln.mine(h, flags, 0, 200_000);
        assertTrue(found, "no salt in 200,000 landed on a 14-bit pattern");
        assertEq(Hook.flags(at), flags, "the mined address does not carry the flags");
        // and it is genuinely where CREATE2 would put it
        assertEq(at, Hook.at(address(kiln), salt, h), "the miner and CREATE2 disagree");
    }

    /// @dev Exactly, not merely containing. v4 requires a hook's address bits
    ///      to EQUAL its declared permissions — a spare bit is a callback the
    ///      PoolManager will hand to a function the hook never wrote.
    function test_aSpareBitIsNotAMatch() public view {
        (bytes32 h,) = kiln.recipeHash(0, bytes32(0));
        (bool found,, address at) = kiln.mine(h, GATE_FLAGS, 0, 200_000);
        assertTrue(found);
        assertEq(uint256(uint160(at) & Hook.MASK), uint256(GATE_FLAGS),
            "the mined address carries a bit nobody asked for");
    }

    function test_miningReportsFailureRatherThanRunningForever() public view {
        (bytes32 h,) = kiln.recipeHash(0, bytes32(0));
        (bool found,,) = kiln.mine(h, GATE_FLAGS, 0, 4);
        assertFalse(found, "four tries found a one-in-sixteen-thousand pattern");
    }

    function test_movingTheWindowAlongContinuesTheSearch() public view {
        (bytes32 h,) = kiln.recipeHash(0, bytes32(0));
        (bool a, bytes32 s1,) = kiln.mine(h, GATE_FLAGS, 0, 200_000);
        (bool b, bytes32 s2,) = kiln.mine(h, GATE_FLAGS, uint256(s1) + 1, 200_000);
        assertTrue(a && b, "the second window found nothing");
        assertTrue(s2 != s1, "the same salt came back twice");
    }

    /*═══════════════ deploying ═══════════════*/

    function test_aMinedSaltDeploysAHookThatTheManagerWillCall() public {
        (bytes32 h, uint16 flags) = kiln.recipeHash(0, bytes32(0));
        (bool found, bytes32 salt, address at) = kiln.mine(h, flags, 0, 200_000);
        assertTrue(found);

        address hook = kiln.deployHook(0, salt, bytes32(0));
        assertEq(hook, at, "it did not land where the miner said it would");
        assertEq(Hook.flags(hook), flags);
        assertTrue(hook.code.length > 0, "nothing was deployed");
        assertEq(Gate(hook).MANAGER(), MANAGER, "the hook trusts the wrong manager");
    }

    /// @dev The check that stops the silent failure: a salt that lands
    ///      somewhere without the bits deploys a hook the pool never calls.
    function test_aSaltThatLandsWrongIsRefusedRatherThanDeployed() public {
        (bytes32 h, uint16 flags) = kiln.recipeHash(0, bytes32(0));
        // walk salts until one is found that does NOT match
        bytes32 bad;
        for (uint256 i = 1; i < 64; ++i) {
            address a = Hook.at(address(kiln), bytes32(i), h);
            if (Hook.flags(a) != flags) { bad = bytes32(i); break; }
        }
        assertTrue(bad != bytes32(0), "could not find a non-matching salt");

        vm.expectRevert();
        kiln.deployHook(0, bad, bytes32(0));
    }

    function test_anUnknownRecipeIsRefused() public {
        vm.expectRevert(Kiln.NothingToLaunch.selector);
        kiln.deployHook(9, bytes32(uint256(1)), bytes32(0));
    }

    /*═══════════════ the gate itself ═══════════════*/

    function _gate(uint64 opens, uint64 unlocks) internal returns (Gate g) {
        bytes32 arg = bytes32((uint256(opens) << 64) | uint256(unlocks));
        (bytes32 h, uint16 flags) = kiln.recipeHash(0, arg);
        (bool found, bytes32 salt,) = kiln.mine(h, flags, 0, 400_000);
        require(found, "no salt");
        g = Gate(kiln.deployHook(0, salt, arg));
    }

    function test_theGateRefusesEverybodyButThePoolManager() public {
        vm.warp(1_000_000);
        Gate g = _gate(1, 1);            // both already open
        PoolKey memory k;
        SwapParams memory sp;
        ModifyLiquidityParams memory mp;

        vm.expectRevert(Gate.NotTheManager.selector);
        g.beforeSwap(address(this), k, sp, "");

        vm.expectRevert(Gate.NotTheManager.selector);
        g.beforeRemoveLiquidity(address(this), k, mp, "");
    }

    function test_theGateHoldsTradingShutAndThenOpensIt() public {
        vm.warp(1_000_000);
        Gate g = _gate(1_000_500, 1_000_900);
        PoolKey memory k;
        SwapParams memory sp;

        vm.prank(MANAGER);
        vm.expectRevert(abi.encodeWithSelector(Gate.NotOpenYet.selector, uint64(1_000_500)));
        g.beforeSwap(address(1), k, sp, "");

        vm.warp(1_000_500);
        vm.prank(MANAGER);
        (bytes4 sel, int256 delta, uint24 fee) = g.beforeSwap(address(1), k, sp, "");
        assertEq(bytes32(sel), bytes32(Gate.beforeSwap.selector),
            "the wrong selector came back");
        assertEq(delta, int256(0), "a gate-only hook moved a balance");
        assertEq(uint256(fee), 0, "a gate-only hook overrode the fee");
    }

    function test_theLockOutlastsTheOpening() public {
        vm.warp(1_000_000);
        Gate g = _gate(1_000_500, 1_000_900);
        PoolKey memory k;
        ModifyLiquidityParams memory mp;

        // trading is open, and liquidity is still not free
        vm.warp(1_000_600);
        vm.prank(MANAGER);
        vm.expectRevert(abi.encodeWithSelector(Gate.StillLocked.selector, uint64(1_000_900)));
        g.beforeRemoveLiquidity(address(1), k, mp, "");

        (bool open, bool free) = g.status();
        assertTrue(open, "trading should be open");
        assertFalse(free, "liquidity should still be locked");

        vm.warp(1_000_900);
        vm.prank(MANAGER);
        assertEq(bytes32(g.beforeRemoveLiquidity(address(1), k, mp, "")),
                 bytes32(Gate.beforeRemoveLiquidity.selector));
    }

    /// @dev The timestamps are immutable, which is the whole safety argument.
    ///      Read off the compiled ABI in `verify-site.mjs`; asserted here as
    ///      the behaviour a setter would break.
    function test_theGateCannotBeReopenedOrExtended() public {
        vm.warp(1_000_000);
        Gate g = _gate(1_000_500, 1_000_900);
        assertEq(uint256(g.OPENS()), 1_000_500);
        assertEq(uint256(g.UNLOCKS()), 1_000_900);
        // and the values survive any amount of poking at the contract
        (bool ok,) = address(g).call(abi.encodeWithSignature("setUntil(uint64)", uint64(0)));
        assertFalse(ok, "something answered a setter");
    }

    /*═══════════════ the token ═══════════════*/

    function test_aLaunchLandsWhereItSaidItWould() public {
        address predicted = kiln.coinAt(
            address(this), "Test Coin", "TEST", 18, 1_000_000e18, bytes32(uint256(7)));
        address coin = kiln.launch("Test Coin", "TEST", 18, 1_000_000e18, bytes32(uint256(7)));
        assertEq(coin, predicted, "the address moved between prediction and launch");
        assertEq(Coin(coin).totalSupply(), 1_000_000e18);
        assertEq(Coin(coin).balanceOf(address(this)), 1_000_000e18, "the supply went elsewhere");
        assertEq(Coin(coin).decimals(), 18);
    }

    /// @dev Two launchers, one salt. Without mixing the sender into it, the
    ///      second `launch` collides and reverts — and worse, anybody
    ///      watching the mempool can take an announced address by re-sending
    ///      the same call with more gas.
    function test_twoPeopleMayUseTheSameSalt() public {
        address other = address(0xB0B);
        address mine_ = kiln.launch("A", "A", 18, 1e18, bytes32(uint256(1)));
        vm.prank(other);
        address theirs = kiln.launch("A", "A", 18, 1e18, bytes32(uint256(1)));
        assertTrue(mine_ != theirs, "the same salt produced the same address for two people");
        assertEq(kiln.launcher(theirs), other);
    }

    function test_aSupplyOfNothingIsNotALaunch() public {
        vm.expectRevert(Kiln.NothingToLaunch.selector);
        kiln.launch("A", "A", 18, 0, bytes32(0));
    }

    function test_theDirectoryReadsNewestFirst() public {
        kiln.launch("One", "ONE", 18, 1e18, bytes32(uint256(1)));
        address two = kiln.launch("Two", "TWO", 18, 1e18, bytes32(uint256(2)));
        address three = kiln.launch("Three", "THR", 18, 1e18, bytes32(uint256(3)));

        assertEq(kiln.coinCount(), 3);
        address[] memory r = kiln.recent(0, 2);
        assertEq(r.length, 2);
        assertEq(r[0], three, "the newest is not first");
        assertEq(r[1], two);

        address[] memory past = kiln.recent(99, 5);
        assertEq(past.length, 0, "reading past the end should be empty, not a revert");
    }

    function test_theSupplyIsFixedAndNobodyCanAddToIt() public {
        address coin = kiln.launch("Fixed", "FIX", 18, 1000e18, bytes32(0));
        uint256 before = Coin(coin).totalSupply();
        // nothing answers any of the usual levers
        string[4] memory levers = [
            "mint(address,uint256)",
            "burn(address,uint256)",
            "pause()",
            "transferOwnership(address)"
        ];
        for (uint256 i; i < 4; ++i) {
            (bool ok,) = coin.call(abi.encodeWithSignature(levers[i], address(this), 1e18));
            assertFalse(ok, "the token answered a lever it should not have");
        }
        assertEq(Coin(coin).totalSupply(), before, "the supply moved");
    }

    function testFuzz_transfersConserveTheSupply(uint128 a, uint128 b) public {
        address coin = kiln.launch("Fixed", "FIX", 18, type(uint128).max, bytes32(0));
        Coin c = Coin(coin);
        address x = address(0xAA);
        address y = address(0xBB);
        vm.assume(a <= type(uint128).max);
        c.transfer(x, a);
        uint256 send = b > a ? a : b;
        vm.prank(x);
        c.transfer(y, send);
        assertEq(
            c.balanceOf(address(this)) + c.balanceOf(x) + c.balanceOf(y),
            uint256(type(uint128).max),
            "tokens appeared or vanished"
        );
    }
}
