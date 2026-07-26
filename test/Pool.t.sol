// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {Engine} from "../src/Engine.sol";
import {Sigil} from "../src/Sigil.sol";
import {Renderer} from "../src/Renderer.sol";
import {Ipseity, IRenderer} from "../src/Ipseity.sol";
import {Pool, IIpseity} from "../src/Pool.sol";
import {Curve} from "../src/lib/Curve.sol";
import {Section} from "../src/lib/Types.sol";
import {ERC6551Registry} from "./mocks/ERC6551Registry.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

/*───────────────────────────────────────────────────────────────────────────
  The market.

  These are written to break it. The properties that actually keep the
  money in the pool are the three fuzzed ones at the top: the invariant
  never falls, a round trip never profits, and the pool never pays out
  more than it holds. Everything below them is access control.
───────────────────────────────────────────────────────────────────────────*/
contract PoolTest is Test {
    Ipseity token;
    Pool    pool;
    MockERC20 weth;
    MockERC20 usdc;

    address holder = address(0xB0B1);
    address trader = address(0x7EAD);
    address renter = address(0x8E17);

    uint256 constant CAP = 1e24;
    uint256 constant WAD = 1e18;
    uint256 constant FOREVER = 4102444800;

    function setUp() public {
        vm.etch(0x000000006551c19487814612e58FE06813775758, address(new ERC6551Registry()).code);

        Engine engine = new Engine(false);
        Renderer renderer = new Renderer(engine, new Sigil());
        engine.loadHead("<html><head></head>");
        engine.loadBody("<body></body></html>");
        engine.freeze();

        token = new Ipseity(IRenderer(address(renderer)));
        // admin is the test contract; in production it is the Timelock
        pool = new Pool(IIpseity(address(token)), CAP, address(this), false);
        token.setPool(address(pool));

        weth = new MockERC20("Wrapped Ether", "WETH", 18, 0, false);
        usdc = new MockERC20("USD Coin", "USDC", 18, 0, false);

        vm.deal(holder, 10 ether);
        vm.deal(trader, 10 ether);

        vm.startPrank(holder);
        token.mint{value: 0.01 ether}();
        pool.openMarket(1, address(weth), address(usdc), 30);
        vm.stopPrank();

        weth.mint(holder, 1e24);
        usdc.mint(holder, 1e24);
        weth.mint(trader, 1e24);
        usdc.mint(trader, 1e24);

        vm.startPrank(holder);
        weth.approve(address(pool), type(uint256).max);
        usdc.approve(address(pool), type(uint256).max);
        pool.deposit(1, 100 * WAD, 300_000 * WAD);
        vm.stopPrank();

        vm.startPrank(trader);
        weth.approve(address(pool), type(uint256).max);
        usdc.approve(address(pool), type(uint256).max);
        vm.stopPrank();
    }

    function _k() internal view returns (uint256) {
        (, , uint112 rb, uint112 rq, , , uint256 c, , , , , ) = pool.market(1);
        uint256 vb = (uint256(rb) * c) / 10_000;
        uint256 vq = (uint256(rq) * c) / 10_000;
        return (uint256(rb) + vb) * (uint256(rq) + vq);
    }

    /*═════════ the three that matter ═════════*/

    /// @dev If k can be made to fall, the pool can be drained one trade at a
    ///      time. Every legal trade must leave it the same or larger.
    function testFuzz_invariantNeverFalls(uint256 amount, bool baseIn, uint256 word) public {
        word = bound(word, 0, type(uint128).max);
        word = (word & ~(uint256(0xff) << 112)) | (uint256(bound(word >> 112, 0, 7)) << 112);
        vm.prank(holder);
        token.commit(1, word);
        vm.prank(holder);
        pool.syncCurve(1);

        (, , uint112 rb, uint112 rq, , , , , , , , ) = pool.market(1);
        amount = bound(amount, 1, baseIn ? uint256(rb) / 3 : uint256(rq) / 3);

        uint256 before_ = _k();
        vm.prank(trader);
        try pool.swap(1, baseIn, amount, 0, trader, FOREVER) {
            assertGe(_k(), before_, "the invariant fell: the pool leaks");
        } catch {
            assertEq(_k(), before_, "a refused trade changed the reserves");
        }
    }

    /// @dev Buy then immediately sell back. If this can ever come out ahead,
    ///      the curve is free money and the pool is a faucet.
    function testFuzz_roundTripNeverProfits(uint256 amount, uint256 word) public {
        word = bound(word, 0, type(uint128).max);
        word = (word & ~(uint256(0xff) << 112)) | (uint256(bound(word >> 112, 0, 7)) << 112);
        vm.prank(holder);
        token.commit(1, word);
        vm.prank(holder);
        pool.syncCurve(1);

        (, , uint112 rb, , , , , , , , , ) = pool.market(1);
        amount = bound(amount, 1e12, uint256(rb) / 4);

        uint256 start = weth.balanceOf(trader);
        vm.startPrank(trader);
        uint256 got;
        try pool.swap(1, true, amount, 0, trader, FOREVER) returns (uint256 o) { got = o; }
        catch { vm.stopPrank(); return; }
        if (got == 0) { vm.stopPrank(); return; }
        try pool.swap(1, false, got, 0, trader, FOREVER) {} catch { vm.stopPrank(); return; }
        vm.stopPrank();

        assertLe(weth.balanceOf(trader), start, "a round trip made money out of nothing");
    }

    /// @dev The curve prices against virtual reserves, so it will happily
    ///      quote more than the pool holds. The guard is the only thing
    ///      standing between that and an insolvent market.
    function testFuzz_neverPaysMoreThanItHolds(uint256 amount, bool baseIn) public {
        (, , uint112 rb, uint112 rq, , , , , , , , ) = pool.market(1);
        amount = bound(amount, 1, 1e26);
        uint256 held = baseIn ? uint256(rq) : uint256(rb);

        vm.prank(trader);
        try pool.swap(1, baseIn, amount, 0, trader, FOREVER) returns (uint256 out) {
            assertLt(out, held, "the pool paid out more than it had");
        } catch {
            // refusing an oversized trade is the correct outcome
        }
    }

    /*═════════ the curve is a copy, not a live read ═════════*/

    /// @dev A renter may operate the artwork. If the pool read the section
    ///      live, that renter could concentrate a curve holding somebody
    ///      else's inventory and trade through it at the better rate.
    function test_renterCannotRepriceSomeoneElsesLiquidity() public {
        vm.prank(holder);
        token.setUser(1, renter, uint64(FOREVER));

        uint256 before_ = pool.quote(1, true, WAD);

        vm.prank(renter);
        token.commit(1, Section.pack([uint16(0), 0, 0, 32768, 32768, 32768], 32768, 2, 33));

        assertEq(pool.quote(1, true, WAD), before_, "a renter moved the market");

        (bool drifted, , ) = pool.pendingCurve(1);
        assertTrue(drifted, "the drift should be reported");

        vm.prank(renter);
        vm.expectRevert(Pool.NotHolder.selector);
        pool.syncCurve(1);

        vm.prank(holder);
        pool.syncCurve(1);
        assertTrue(pool.quote(1, true, WAD) != before_, "the holder's sync should move it");
    }

    function test_turningThroughWConcentratesTheCurve() public {
        uint256 flat = Curve.concentration(Section.pack([uint16(0), 0, 0, 0, 0, 0], 0, 0, 0));
        uint256 spun = Curve.concentration(Section.pack([uint16(32768), 32768, 32768, 0, 0, 0], 0, 0, 0));
        uint256 edge = Curve.concentration(Section.pack([uint16(0), 0, 0, 32768, 32768, 32768], 0, 0, 0));

        assertEq(flat, 0, "an unturned solid is plain constant product");
        assertEq(spun, 0, "spinning the section must not touch the market");
        assertEq(edge, Curve.MAX_CONCENTRATION, "edge on is fully concentrated");
    }

    /*═════════ the market travels with the token ═════════*/

    function test_sellingTheTokenSellsTheMarket() public {
        address buyer = address(0xB0197A);
        vm.prank(holder);
        token.transferFrom(holder, buyer, 1);

        (, , uint112 rb, uint112 rq, , , , , , , , ) = pool.market(1);
        assertGt(rb, 0);
        assertGt(rq, 0);

        vm.prank(holder);
        vm.expectRevert(Pool.NotHolder.selector);
        pool.withdraw(1, 1, 0, holder);

        uint256 before_ = weth.balanceOf(buyer);
        vm.prank(buyer);
        pool.withdraw(1, WAD, 0, buyer);
        assertEq(weth.balanceOf(buyer) - before_, WAD, "the new owner owns the inventory");
    }

    /*═════════ access and limits ═════════*/

    function test_onlyHolderMayOpenDepositWithdrawOrSetFee() public {
        vm.startPrank(trader);
        vm.expectRevert(Pool.NotHolder.selector); pool.openMarket(1, address(weth), address(usdc), 30);
        vm.expectRevert(Pool.NotHolder.selector); pool.deposit(1, 1, 1);
        vm.expectRevert(Pool.NotHolder.selector); pool.withdraw(1, 1, 0, trader);
        vm.expectRevert(Pool.NotHolder.selector); pool.setFee(1, 10);
        vm.expectRevert(Pool.NotHolder.selector); pool.syncCurve(1);
        vm.stopPrank();
    }

    function test_slippageFloorIsHonoured() public {
        vm.prank(trader);
        vm.expectRevert();
        pool.swap(1, true, WAD, type(uint128).max, trader, FOREVER);
    }

    function test_deadlineIsHonoured() public {
        vm.warp(1000);
        vm.prank(trader);
        vm.expectRevert(Pool.Expired.selector);
        pool.swap(1, true, WAD, 0, trader, 999);
    }

    function test_feeCap() public {
        vm.prank(holder);
        vm.expectRevert(Pool.FeeTooHigh.selector);
        pool.setFee(1, 501);
    }

    function test_depositCap() public {
        vm.prank(holder);
        vm.expectRevert(Pool.DepositCap.selector);
        pool.deposit(1, CAP, 0);
    }

    function test_marketMustBeEmptyToClose() public {
        vm.prank(holder);
        vm.expectRevert(Pool.MarketNotEmpty.selector);
        pool.closeMarket(1);
    }

    function test_feeOnTransferTokenIsCreditedOnlyWhatArrived() public {
        MockERC20 fot = new MockERC20("FeeOnTransfer", "FOT", 18, 100, false);
        fot.mint(holder, 1e24);

        vm.startPrank(holder);
        token.mint{value: 0.01 ether}();
        pool.openMarket(2, address(fot), address(usdc), 30);
        fot.approve(address(pool), type(uint256).max);
        pool.deposit(2, 1000 * WAD, 0);
        vm.stopPrank();

        (, , uint112 rb, , , , , , , , , ) = pool.market(2);
        assertEq(uint256(rb), 990 * WAD, "credited more than arrived");
    }

    function test_silentTokenIsAccepted() public {
        MockERC20 usdt = new MockERC20("Tether", "USDT", 6, 0, true);
        usdt.mint(holder, 1e12);

        vm.startPrank(holder);
        token.mint{value: 0.01 ether}();
        pool.openMarket(2, address(usdt), address(usdc), 30);
        usdt.approve(address(pool), type(uint256).max);
        pool.deposit(2, 1e9, 0);
        vm.stopPrank();

        (, , uint112 rb, , , , , , , , , ) = pool.market(2);
        assertEq(uint256(rb), 1e9, "a token that returns nothing was rejected");
    }

    /*═════════ the bond ═════════*/

    /// @dev "Selling the token sells the market" is mechanically true the
    ///      moment ownerOf changes, and worth nothing to a buyer on its own:
    ///      the seller can empty it between the handshake and the settlement.
    ///      The bond is what turns it into a promise, and the only property
    ///      that makes a promise worth reading is that it cannot be walked
    ///      back.
    function testFuzz_bondOnlyRatchets(uint64 a, uint64 b) public {
        a = uint64(bound(a, block.timestamp + 1, block.timestamp + 300 days));
        b = uint64(bound(b, block.timestamp + 1, block.timestamp + 300 days));

        vm.prank(holder);
        pool.bond(1, a);
        assertEq(pool.bondedUntil(1), a);

        vm.prank(holder);
        if (b > a) {
            pool.bond(1, b);
            assertEq(pool.bondedUntil(1), b);
        } else {
            vm.expectRevert(Pool.RatchetOnly.selector);
            pool.bond(1, b);
            assertEq(pool.bondedUntil(1), a, "the ratchet turned backwards");
        }
    }

    function test_bondFreezesEveryExitAndEveryTerm() public {
        uint64 until = uint64(block.timestamp + 30 days);
        vm.startPrank(holder);
        pool.bond(1, until);

        vm.expectRevert(abi.encodeWithSelector(Pool.Bonded.selector, until));
        pool.withdraw(1, 1, 0, holder);
        vm.expectRevert(abi.encodeWithSelector(Pool.Bonded.selector, until));
        pool.closeMarket(1);
        vm.expectRevert(abi.encodeWithSelector(Pool.Bonded.selector, until));
        pool.setFee(1, 100);
        vm.expectRevert(abi.encodeWithSelector(Pool.Bonded.selector, until));
        pool.syncCurve(1);

        // additive operations must survive, or a bonded market cannot be fed
        pool.deposit(1, WAD, 0);
        vm.stopPrank();

        vm.prank(trader);
        pool.swap(1, true, WAD / 100, 0, trader, FOREVER);
    }

    function test_bondSurvivesTheSaleAndBindsTheBuyer() public {
        address buyer = address(0xB0197A);
        uint64 until = uint64(block.timestamp + 30 days);

        vm.startPrank(holder);
        pool.bond(1, until);
        token.transferFrom(holder, buyer, 1);
        vm.stopPrank();

        assertEq(pool.bondedUntil(1), until, "the bond did not survive the sale");
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(Pool.Bonded.selector, until));
        pool.withdraw(1, 1, 0, buyer);
    }

    function test_bondExpiresAndReleases() public {
        uint64 until = uint64(block.timestamp + 30 days);
        vm.prank(holder);
        pool.bond(1, until);

        vm.warp(until + 1);
        assertFalse(pool.isBonded(1));
        vm.prank(holder);
        pool.withdraw(1, WAD, 0, holder);
    }

    function test_bondHasACeiling() public {
        vm.prank(holder);
        vm.expectRevert(Pool.BondTooLong.selector);
        pool.bond(1, uint64(block.timestamp + 400 days));
    }

    /*═════════ privilege ═════════*/

    /// @dev A pause that traps money is a slower theft. Withdrawal carries
    ///      no pause modifier and must be reachable in every state.
    function test_pauseHaltsTradeButNeverCustody() public {
        pool.setPaused(true);

        vm.prank(trader);
        vm.expectRevert(Pool.Paused.selector);
        pool.swap(1, true, WAD, 0, trader, FOREVER);

        vm.startPrank(holder);
        vm.expectRevert(Pool.Paused.selector);
        pool.deposit(1, WAD, 0);

        uint256 before_ = weth.balanceOf(holder);
        pool.withdraw(1, WAD, 0, holder);
        assertEq(weth.balanceOf(holder) - before_, WAD, "the pause trapped the inventory");
        vm.stopPrank();
    }

    function test_allowlistGatesNewMarkets() public {
        pool.setAllowlistEnforced(true);
        vm.startPrank(holder);
        token.mint{value: 0.01 ether}();
        vm.expectRevert(abi.encodeWithSelector(Pool.NotBlessed.selector, address(weth)));
        pool.openMarket(2, address(weth), address(usdc), 30);
        vm.stopPrank();

        pool.bless(address(weth), true);
        pool.bless(address(usdc), true);
        vm.prank(holder);
        pool.openMarket(2, address(weth), address(usdc), 30);
    }

    function test_onlyAdminMayFlipTheSwitches() public {
        vm.startPrank(trader);
        vm.expectRevert(Pool.NotAdmin.selector); pool.setPaused(true);
        vm.expectRevert(Pool.NotAdmin.selector); pool.bless(address(weth), true);
        vm.expectRevert(Pool.NotAdmin.selector); pool.setAllowlistEnforced(true);
        vm.expectRevert(Pool.NotAdmin.selector); pool.proposeAdmin(trader);
        vm.expectRevert(Pool.NotAdmin.selector); pool.acceptAdmin();
        vm.stopPrank();
    }

    function test_adminHandoverTakesTwoSteps() public {
        pool.proposeAdmin(trader);
        assertEq(pool.admin(), address(this), "the admin moved on one call");

        vm.prank(renter);
        vm.expectRevert(Pool.NotAdmin.selector);
        pool.acceptAdmin();

        vm.prank(trader);
        pool.acceptAdmin();
        assertEq(pool.admin(), trader);
    }

    /*═════════ the maths on its own ═════════*/

    function testFuzz_concentrationIsBounded(uint256 word) public pure {
        uint256 c = Curve.concentration(word);
        assertLe(c, Curve.MAX_CONCENTRATION);
    }

    /// @dev More in must never mean less out, at any curve.
    function testFuzz_outputIsMonotonicInInput(uint256 a, uint256 b, uint256 word) public pure {
        uint256 rIn = 1000 * 1e18;
        uint256 rOut = 3_000_000 * 1e18;
        a = bound(a, 1e6, rIn / 4);
        b = bound(b, a, rIn / 3);
        assertLe(
            Curve.amountOut(a, rIn, rOut, word, 30),
            Curve.amountOut(b, rIn, rOut, word, 30),
            "a larger trade got less out"
        );
    }

    /// @dev The output must always be strictly under the priced reserve, or
    ///      the arithmetic itself is unsound before any guard is applied.
    function testFuzz_outputStaysUnderThePricedReserve(uint256 amount, uint256 word) public pure {
        uint256 rIn = 1000 * 1e18;
        uint256 rOut = 3_000_000 * 1e18;
        amount = bound(amount, 1, 1e30);
        (, uint256 vOut) = Curve.virtualReserves(word, rIn, rOut);
        assertLt(Curve.amountOut(amount, rIn, rOut, word, 30), rOut + vOut);
    }
}
