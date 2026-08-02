// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Venue} from "../src/Venue.sol";
import {Tick} from "../src/lib/Tick.sol";
import {Look, PoolState} from "../src/interfaces/Site.sol";
import {
    MockV3Factory, MockV3Pool, MockBook, MockQuoter, MockRouterV3, MockRouter02,
    PhantomFactory, SilentFactory, GreedyFactory, HalfPoolFactory, ImpostorPool
} from "./mocks/UniV3.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

/*───────────────────────────────────────────────────────────────────────────
  Venue reads addresses it did not choose.

  The factory comes from whoever deployed this contract and a pool address
  comes back from that factory, so every one of these calls lands in whatever
  happens to be there. That is fine as long as the failure mode is "no
  venue" — and it is worth proving rather than asserting, because the swap
  card underneath the comparison is the part that matters and a page a bad
  address can switch off is a page a bad address controls.
───────────────────────────────────────────────────────────────────────────*/
contract VenueTest is Test {
    MockV3Factory f;
    MockERC20 weth;
    MockERC20 usdc;
    Venue v;

    address constant ANY = address(0xBEEF);

    function setUp() public {
        f = new MockV3Factory();
        weth = new MockERC20("Wrapped Ether", "WETH", 18, 0, false);
        usdc = new MockERC20("USD Coin", "USDC", 6, 0, false);
        v = _venue(address(f));
    }

    function _venue(address factory) internal returns (Venue) {
        return new Venue(Venue.Wiring({
            factory: factory, quoter: ANY, router: ANY, routerKind: 0,
            positions: ANY, wrapped: address(weth), governor: ANY, govToken: ANY,
            poolManager: ANY
        }));
    }

    /*═══════════════ the wiring itself ═══════════════*/

    function test_aRouterKindNobodyCheckedIsRefused() public {
        vm.expectRevert(Venue.UnknownRouterKind.selector);
        new Venue(Venue.Wiring({
            factory: address(f), quoter: ANY, router: ANY, routerKind: 2,
            positions: ANY, wrapped: ANY, governor: ANY, govToken: ANY,
            poolManager: ANY
        }));
    }

    /// @dev The control for the above: kind 1 is legitimate and must pass,
    ///      or the check would be "refuses everything" rather than "refuses
    ///      what it does not understand".
    function test_bothRealRouterKindsAreAccepted() public {
        for (uint8 k; k < 2; ++k) {
            Venue x = new Venue(Venue.Wiring({
                factory: address(f), quoter: ANY, router: ANY, routerKind: k,
                positions: ANY, wrapped: ANY, governor: ANY, govToken: ANY,
                poolManager: ANY
            }));
            assertEq(x.ROUTER_KIND(), k);
        }
    }

    function test_aChainWithNoUniswapSaysSoRatherThanFailing() public {
        Venue none = _venue(address(0));
        assertFalse(none.present(), "claimed a venue that is not there");
        Look memory L = none.best(address(weth), address(usdc), 18);
        assertFalse(L.found);
        assertEq(L.spot, 0);
        assertEq(none.poolAt(address(weth), address(usdc), 3000), address(0));
    }

    /*═══════════════ finding the deepest pool ═══════════════*/

    function test_theDeepestPoolWinsRatherThanTheFirstOne() public {
        // 3000 is shallow, 500 is deep — and 500 is checked first, so a
        // reader that stopped at the first hit would pick the wrong one
        f.make(address(weth), address(usdc), 500, uint160(1) << 96, 0, 1e6);
        address deep = f.make(address(weth), address(usdc), 3000, uint160(1) << 96, 0, 9e18);

        Look memory L = v.best(address(weth), address(usdc), 18);
        assertTrue(L.found, "found nothing");
        assertEq(L.pool, deep, "did not take the deepest");
        assertEq(uint256(L.fee), 3000);
    }

    function test_anEmptyPoolIsNotAVenue() public {
        f.make(address(weth), address(usdc), 3000, uint160(1) << 96, 0, 0);
        Look memory L = v.best(address(weth), address(usdc), 18);
        assertFalse(L.found, "a pool with no liquidity at the tick priced something");
    }

    function test_surveyReportsTheTiersThatDoNotExist() public {
        f.make(address(weth), address(usdc), 3000, uint160(1) << 96, 0, 1e18);
        Look[4] memory all = v.survey(address(weth), address(usdc), 18);
        assertFalse(all[0].found, "0.01%");
        assertFalse(all[1].found, "0.05%");
        assertTrue(all[2].found, "0.3%");
        assertFalse(all[3].found, "1%");
    }

    function test_aPairWithItselfIsNotAPair() public {
        Look memory L = v.best(address(weth), address(weth), 18);
        assertFalse(L.found);
    }

    /*═══════════════ tiers are read, not assumed ═══════════════*/

    function test_theHundredthTierIsNotAssumedToExist() public view {
        // the real factory's constructor enables 500, 3000 and 10000 only
        assertEq(v.enabled(100), int24(0), "claimed a tier the factory never enabled");
        assertEq(v.enabled(500), int24(10));
        assertEq(v.enabled(3000), int24(60));
        assertEq(v.enabled(10000), int24(200));
    }

    function test_aTierEnabledLaterIsSeen() public {
        f.enableFeeAmount(100, 1);
        assertEq(v.enabled(100), int24(1), "did not notice a tier being turned on");
        int24[4] memory sp = v.spacings();
        assertEq(sp[0], int24(1));
    }

    /*═══════════════ the pool's own claim about itself ═══════════════*/

    function test_anImpostorPoolIsNotDescribedAsAPool() public {
        ImpostorPool imp = new ImpostorPool();
        PoolState memory s = v.state(address(imp));
        assertFalse(s.ok,
            "an address that answers every pool read but names another factory "
            "was described as a Uniswap pool");
    }

    /// @dev The control. Same reads, a real pool, and it must pass — or the
    ///      test above would be satisfied by a `state()` that never succeeds.
    function test_aRealPoolIsDescribedAsOne() public {
        address p = f.make(address(weth), address(usdc), 3000, uint160(1) << 96, 0, 1e18);
        PoolState memory s = v.state(p);
        assertTrue(s.ok, "a genuine pool was refused");
        assertEq(s.fee, uint24(3000));
        assertEq(s.spacing, int24(60));
        assertEq(s.liquidity, uint128(1e18));
    }

    /*═══════════════ addresses that misbehave ═══════════════*/

    function test_aFactoryPointingAtNothingIsNotFollowed() public {
        Venue p = _venue(address(new PhantomFactory()));
        assertEq(p.poolAt(address(weth), address(usdc), 3000), address(0),
            "followed a pool address with no code behind it");
        Look memory L = p.best(address(weth), address(usdc), 18);
        assertFalse(L.found);
    }

    function test_aFactoryThatRevertsDoesNotTakeThePageWithIt() public {
        Venue s = _venue(address(new SilentFactory()));
        Look memory L = s.best(address(weth), address(usdc), 18);
        assertFalse(L.found, "a reverting factory produced a price");
        assertEq(s.enabled(3000), int24(0));
    }

    function test_aFactoryThatBurnsEveryDropOfGasStillLeavesEnoughToRender() public {
        Venue g = _venue(address(new GreedyFactory()));
        uint256 before = gasleft();
        Look memory L = g.best(address(weth), address(usdc), 18);
        uint256 burned = before - gasleft();
        assertFalse(L.found);
        /*  Four tiers at a 60k stipend each. Without the stipend one call
            would consume 63/64 of everything and the page would die on the
            comparison rather than rendering without it.                   */
        assertLt(burned, 1_200_000, "the stipend did not bound the damage");
    }

    function test_aPoolThatAnswersHalfTheReadsPricesNothing() public {
        Venue h = _venue(address(new HalfPoolFactory()));
        Look memory L = h.best(address(weth), address(usdc), 18);
        assertFalse(L.found, "priced a pool that would not say its liquidity");
    }

    /*═══════════════ the oracle ═══════════════*/

    function test_aFreshPoolHasNoHistoryAndSaysSoRatherThanReverting() public {
        address p = f.make(address(weth), address(usdc), 3000, uint160(1) << 96, 0, 1e18);
        // depth 0: exactly what a pool is created with
        (bool ok, int24[] memory ticks,) = v.history(p, 3600, 12);
        assertFalse(ok, "claimed a chart from a pool with no memory");
        assertEq(ticks.length, 0);
    }

    function test_aPoolWithMemoryDrawsAChart() public {
        vm.warp(1_000_000);
        address p = f.make(address(weth), address(usdc), 3000, uint160(1) << 96, -201240, 1e18);
        MockV3Pool(p).setHistory(86400, 300);

        (bool ok, int24[] memory ticks, uint32 step) = v.history(p, 3600, 12);
        assertTrue(ok, "a pool with history refused to draw one");
        assertEq(ticks.length, 12);
        assertEq(uint256(step), 300);
        for (uint256 i; i < ticks.length; ++i) {
            assertEq(ticks[i], int24(-201240), "the mean of a constant tick is that tick");
        }
    }

    /// @dev The rounding guard, which is the whole reason `meanTick` exists
    ///      as a named function. Integer division truncates toward zero, so
    ///      a negative mean rounds *up* — and every point on a chart below
    ///      parity would sit one tick too high.
    function test_aNegativeMeanRoundsTowardNegativeInfinity() public pure {
        // -7 over 2 seconds is -3.5, which floors to -4 and truncates to -3
        assertEq(Tick.meanTick(0, -7, 2), int24(-4), "rounded toward zero");
        // and a positive one is unaffected
        assertEq(Tick.meanTick(0, 7, 2), int24(3));
        // exact division needs no correction in either direction
        assertEq(Tick.meanTick(0, -8, 2), int24(-4));
    }

    function test_anAbsurdNumberOfPointsIsRefusedRatherThanAttempted() public {
        address p = f.make(address(weth), address(usdc), 3000, uint160(1) << 96, 0, 1e18);
        MockV3Pool(p).setHistory(86400, 300);
        (bool ok,,) = v.history(p, 3600, 200);
        assertFalse(ok, "accepted a request that would not fit in an eth_call");
    }

    function test_aWindowShorterThanItsOwnStepIsRefused() public {
        address p = f.make(address(weth), address(usdc), 3000, uint160(1) << 96, 0, 1e18);
        MockV3Pool(p).setHistory(86400, 300);
        (bool ok,,) = v.history(p, 5, 12);       // 5 seconds in 12 pieces
        assertFalse(ok);
    }

    /*═══════════════ the tick ladder ═══════════════*/

    function test_theTickLadderAgreesWithUniswapAtTheEdges() public pure {
        assertEq(Tick.sqrtAt(0), uint160(1) << 96, "tick zero is not parity");
        assertEq(Tick.sqrtAt(Tick.MIN_TICK), Tick.MIN_SQRT, "the floor moved");
        assertEq(Tick.sqrtAt(Tick.MAX_TICK), Tick.MAX_SQRT, "the ceiling moved");
    }

    function test_aTickPastTheEndIsRefused() public {
        vm.expectRevert(Tick.TickOutOfRange.selector);
        Tick.sqrtAt(Tick.MAX_TICK + 1);
    }

    function testFuzz_theLadderOnlyEverGoesUp(int24 a, int24 b) public pure {
        a = int24(bound(int256(a), Tick.MIN_TICK, Tick.MAX_TICK - 1));
        b = int24(bound(int256(b), int256(a) + 1, Tick.MAX_TICK));
        assertLt(Tick.sqrtAt(a), Tick.sqrtAt(b), "a higher tick priced lower");
    }

    function test_snappingToTheGridLandsOnTheGrid() public pure {
        assertEq(Tick.usable(-201240, 60), int24(-201240), "already on it");
        assertEq(Tick.usable(-201250, 60), int24(-201240), "nearest is up");
        assertEq(Tick.usable(-201270, 60), int24(-201300), "nearest is down");
        assertEq(Tick.usable(31, 60), int24(60), "past the halfway point");
        assertEq(Tick.usable(29, 60), int24(0), "short of it");
    }

    function testFuzz_aSnappedTickIsAlwaysUsable(int24 t, uint8 which) public pure {
        int24[4] memory sps = [int24(1), int24(10), int24(60), int24(200)];
        int24 sp = sps[which % 4];
        int24 r = Tick.usable(t, sp);
        assertEq(r % sp, int24(0), "not a multiple of the spacing");
        assertTrue(r <= Tick.MAX_TICK && r >= Tick.MIN_TICK, "snapped outside the ladder");
        // and it must still be a tick the ladder can price
        Tick.sqrtAt(r);
    }

    function test_theRealPairAgain() public view {
        /*  WETH/USDC around 3000: token0 is WETH with 18 decimals, token1 is
            USDC with 6, and the raw price is 3e-9. The tick nearest that is
            -201240, and what matters is that the price this contract reports
            for that tick is a number a person would recognise.            */
        uint256 p = v.priceAt(-196256, 1e18, true);
        assertApproxEqAbs(int256(p), int256(uint256(3000e6)), 60e6,
            "tick -201240 did not price near 3000 USDC");
    }
}
