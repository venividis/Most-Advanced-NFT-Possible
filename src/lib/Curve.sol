// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Section} from "./Types.sol";

/*───────────────────────────────────────────────────────────────────────────
  CURVE — the shape of the solid is the shape of the market

  A pool needs an invariant: a rule saying what combinations of the two
  reserves are equivalent, so that any trade can be priced by moving along
  it. The plain constant product is x·y = k.

  This one is

      (x + vx)·(y + vy) = k

  where vx and vy are *virtual* reserves — liquidity the curve prices
  against but does not actually hold. Adding them flattens the curve near
  the current price, which is what a market maker means by "concentrating"
  liquidity: trades near the middle move the price less, and the same
  inventory does more work.

  vx and vy come from the token's section word. Specifically from how far
  the solid has been turned out of the holder's own 3-space — the sum of
  the three rotation planes that contain w, the same quantity the artwork
  reports as "Turned through w". So:

      solid barely turned      →  vx, vy ≈ 0     →  plain constant product,
                                                    a wide, forgiving market
      solid turned edge on     →  vx, vy large   →  a tight market that
                                                    holds its price

  Rotating the artwork re-prices the market. The picture is not a picture
  of the pool; it is a readout of it.

  ── why this family and not a prettier one ──

  The tempting move is to let the six angles drive an arbitrary invariant.
  They cannot. An invariant has to be monotonic and convex or a trader can
  walk the curve back on itself and take the reserves for nothing. This
  family is constant product with a change of origin, so it inherits
  constant product's proof: the invariant is a hyperbola for every legal
  parameter, and no rotation the holder can commit will bend it into a
  shape that leaks.

  The one thing virtual reserves do break is the guarantee that the pool
  can pay. A curve that prices against liquidity it does not hold will
  happily quote an output larger than the real balance. That is not fixed
  by cleverness, it is fixed by refusing the trade — see MAX_OUT_BPS in
  Pool.sol. The pool has a maximum trade size, and says so.
───────────────────────────────────────────────────────────────────────────*/
library Curve {
    /// @dev Reserves are uint112 as in Uniswap v2, so x + vx stays under
    ///      2^120 and the product under 2^240 with room to spare.
    uint256 internal constant MAX_RESERVE = type(uint112).max;

    /// @dev Virtual reserves cap at 8x real. Beyond that the curve is so
    ///      flat that the maximum payable trade becomes uselessly small.
    uint256 internal constant MAX_CONCENTRATION = 80_000;   // 8.0000x, in bps
    uint256 internal constant BPS = 10_000;

    error ReserveOverflow();
    error NoLiquidity();
    error ZeroInput();

    /*───────────────── the section, read as a market ─────────────────*/

    /// @notice How tightly this token's market is concentrated, in bps of
    ///         the real reserves. Derived only from the three rotation
    ///         planes that contain w — the ones that change the shape of
    ///         the section rather than merely spinning it.
    /// @return bps 0 (plain constant product) .. MAX_CONCENTRATION
    function concentration(uint256 word) internal pure returns (uint256 bps) {
        uint256 turned;
        unchecked {
            for (uint256 p = 3; p < 6; ++p) {
                uint256 a = uint256(Section.angle(word, p));
                // distance from rest, whichever way round the circle is nearer
                turned += a > 32768 ? 65536 - a : a;
            }
        }
        // turned is 0..98304 (three planes, half a turn each)
        return (turned * MAX_CONCENTRATION) / 98_304;
    }

    /// @notice The virtual reserves this section adds to each side.
    /// @notice The offsets a market anchors to, computed once from the
    ///         reserves as they stand at that moment.
    /// @dev    ANCHORING, not deriving. This is called when liquidity or the
    ///         curve changes and the result is stored; it is never called
    ///         from a trade.
    ///
    ///         It used to be called on every quote, from the live reserves,
    ///         and that was a critical bug. Virtual reserves proportional to
    ///         live reserves re-anchor the curve after every trade: k is
    ///         conserved *within* a trade and not *across* two, so buying
    ///         and selling straight back extracted the difference. At 8x
    ///         concentration and a trade worth a third of the reserve, 400
    ///         units in came back as 718. The fuzz suite found it — see
    ///         tools/fuzz.mjs, "a round trip never profits".
    ///
    ///         Held as an offset, the curve stays where it was put, and the
    ///         only thing that moves it is the holder deliberately moving
    ///         it.
    function anchor(uint256 word, uint256 rBase, uint256 rQuote)
        internal pure returns (uint256 vBase, uint256 vQuote)
    {
        uint256 c = concentration(word);
        vBase = (rBase * c) / BPS;
        vQuote = (rQuote * c) / BPS;
    }

    /*───────────────── pricing ─────────────────*/

    /// @notice How much comes out for `amountIn` going in.
    /// @dev    The fee is taken off the amount used for pricing but the whole
    ///         input still lands in the reserves, so k rises on every trade
    ///         and the fee accrues to whoever holds the token. Rounding is
    ///         always toward the pool.
    /// @param vIn  the anchored offset on the incoming side
    /// @param vOut the anchored offset on the outgoing side
    /// @dev   Both are passed in rather than derived. The caller holds them;
    ///        see `anchor` for why that distinction is the whole ballgame.
    function amountOut(
        uint256 amountIn,
        uint256 rIn,
        uint256 rOut,
        uint256 vIn,
        uint256 vOut,
        uint256 feeBps
    ) internal pure returns (uint256 out) {
        if (amountIn == 0) revert ZeroInput();
        if (rIn == 0 || rOut == 0) revert NoLiquidity();

        uint256 x = rIn + vIn;
        uint256 y = rOut + vOut;
        uint256 k = x * y;

        uint256 inAfterFee = (amountIn * (BPS - feeBps)) / BPS;
        uint256 xNew = x + inAfterFee;

        // round the pool's remaining balance up, so the trader never gains
        // the rounding dust
        uint256 yNew = (k + xNew - 1) / xNew;
        out = y > yNew ? y - yNew : 0;
    }

    /// @notice What one unit of the input side is worth right now, scaled by
    ///         1e18. For display only — a real trade moves the price.
    function spot(uint256 rIn, uint256 rOut, uint256 vIn, uint256 vOut)
        internal pure returns (uint256)
    {
        if (rIn == 0 || rOut == 0) return 0;
        return ((rOut + vOut) * 1e18) / (rIn + vIn);
    }

    /// @notice The invariant, for tests that need to prove it never falls.
    /// @dev    Takes the anchored offsets, so what it measures is the
    ///         quantity trading actually conserves rather than a quantity
    ///         that moves underneath it.
    function invariant(uint256 rIn, uint256 rOut, uint256 vIn, uint256 vOut)
        internal pure returns (uint256)
    {
        return (rIn + vIn) * (rOut + vOut);
    }
}
