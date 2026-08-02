// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibNum} from "./lib/LibNum.sol";
import {Web} from "./lib/Web.sol";
import {Assets} from "./lib/Assets.sol";
import {IChrome, IDesk, IPoolRead, IVenue, Look} from "./interfaces/Site.sol";

interface IDeskUni {
    function config() external view returns (string memory);
    function base() external pure returns (string memory);
}

interface IDeskCivic {
    function civic() external pure returns (string memory);
}

/*───────────────────────────────────────────────────────────────────────────
  PageExplore — a price chart with no indexer, drawn by a contract

  Uniswap's Explore tab is backed by subgraphs: indexers replaying `Swap`
  events into volume, total value locked and rankings. There is no volume
  counter in chain state and no way to enumerate "all tokens", so none of
  that can be reproduced here and none of it is claimed.

  What *is* on chain turns out to be the more interesting half. A v3 pool has
  been recording a cumulative tick since the day it was created. The
  difference between any two of those readings, divided by the seconds
  between them, is the time-weighted average price over that interval —
  computed by the pool itself. So this page draws a real price history with
  no indexer, no subgraph and no server, out of the same contract that would
  execute your trade.

  Two properties follow that a hosted chart cannot have. It cannot be
  falsified by whoever is serving the page, because whoever is serving the
  page is a contract reading another contract. And it needs no JavaScript:
  the bars are divs with percentage heights, assembled in Solidity, so the
  chart is there in a client with scripting switched off entirely.

  The catch is real and the page says it out loud: every pool is created with
  room for exactly one observation, so most pools have no history at all.
  Anyone may pay to lengthen the buffer — permanently, for everyone — and the
  page offers that button, because "this pool has no memory" is a fixable
  condition rather than an excuse.

  `/explore/<address>` is a whole page about one token: what it calls itself,
  which of the four fee tiers has a pool, how deep each one is at the current
  tick, and the chart. All of it rendered here, from reads.
───────────────────────────────────────────────────────────────────────────*/
contract PageExplore {
    using LibNum for uint256;

    IChrome    public immutable CHROME;
    IPoolRead  public immutable POOL;
    IDesk      public immutable DESK;
    IDeskUni   public immutable DESKU;
    IDeskCivic public immutable DESKC;
    IVenue     public immutable VENUE;

    /// @dev One day of history in 24 bars. Enough to be a chart, few enough
    ///      that `observe` fits comfortably inside any node's `eth_call` cap.
    uint32 public constant WINDOW = 86_400;
    uint8  public constant BARS = 24;

    constructor(
        IChrome chrome, IPoolRead pool, IDesk desk,
        IDeskUni deskU, IDeskCivic deskC, IVenue venue
    ) {
        CHROME = chrome;
        POOL = pool;
        DESK = desk;
        DESKU = deskU;
        DESKC = deskC;
        VENUE = venue;
    }

    /*═══════════════════ /explore ═══════════════════*/

    function explore(address token) external view returns (string memory) {
        if (!VENUE.present()) return _closed(11, "explore");
        return string.concat(
            CHROME.head("IPSEITY \xc2\xb7 explore"),
            CHROME.navTop(11),
            DESKU.config(),
            token == address(0) ? _exploreIndex() : _exploreOne(token),
            DESK.core(),
            DESKU.base(),
            DESKC.civic(),
            CHROME.foot(msg.sender, block.chainid)
        );
    }

    function _exploreIndex() private view returns (string memory) {
        address wr = VENUE.WRAPPED();
        (address[] memory list,) = Assets.derive(POOL, 0, 32);
        string memory rows;
        if (wr != address(0)) rows = _exploreRow(wr);
        for (uint256 i; i < list.length; ++i) {
            if (list[i] == wr) continue;
            rows = string.concat(rows, _exploreRow(list[i]));
        }
        return string.concat(
            "<h1>explore</h1>"
            "<p class=e>Uniswap's own Explore tab is backed by subgraphs: indexers "
            "replaying swap events into volume, total value locked and rankings. None "
            "of that is in chain state, so none of it is here, and this page does not "
            "invent any of it.</p>"
            "<p class=e>What is here instead: paste any ERC-20 address and this page "
            "asks the factory which of the four fee tiers has a pool for it, asks each "
            "of those pools how deep it is at the current tick, and draws a price chart "
            "out of the pool's own oracle. No indexer, no subgraph, no server &mdash; "
            "and no JavaScript, because the page contract renders it.</p>"
            "<div class=app style=\"padding:.9rem 1rem\">"
            "<label>any ERC-20 address</label>"
            "<input id=xa placeholder=\"0x\xe2\x80\xa6\">"
            "<button class=go id=xgo>Look it up</button></div>",
            list.length == 0 && wr == address(0)
                ? "<p class=e>Nothing to start from on this chain.</p>"
                : string.concat("<h2>a few to start from</h2><table>"
                    "<tr><th>asset</th><th>address</th><th></th></tr>", rows, "</table>")
        );
    }

    function _exploreRow(address t) private view returns (string memory) {
        return string.concat(
            "<tr><td>", Web.symbolOf(t), "</td><td><code>", LibNum.hexAddr(t),
            "</code></td><td><a href=\"/explore/", LibNum.hexAddr(t),
            "\">look &rarr;</a></td></tr>"
        );
    }

    function _exploreOne(address t) private view returns (string memory) {
        uint8 d = Web.decimalsOf(t);
        (address quote, Look[4] memory all) = _against(t, d);

        return string.concat(
            "<h1>", Web.symbolOf(t), "</h1>"
            "<p class=e><code>", LibNum.hexAddr(t), "</code></p>",
            _facts(t, d, quote),
            _tierTable(all, quote),
            _chart(all, t, quote, d),
            "<p><a class=g href=\"/swap\">trade it &rarr;</a>"
            "<a class=g href=\"/pools\">provide liquidity &rarr;</a>"
            "<a class=g href=\"/explore\">something else &rarr;</a></p>"
        );
    }

    /*  What to price it against.

        The wrapped native token is the right default and is wrong in two
        cases that both happen: when the subject *is* the wrapped native, and
        when the pair simply has no pool. The first version of this took the
        first other asset it could find, which for a collection whose first
        market happens to trade something obscure meant pricing WETH against
        that and reporting "no pool at any tier" for the most liquid token on
        the chain.

        So it tries candidates until one of them actually has a pool, and
        stops at eight — every candidate is four `getPool` calls plus the
        reads behind them, and a page that searched exhaustively would be a
        page no node finishes. The first version stopped at four candidates
        drawn from the first eight markets, which sounds like plenty and is
        not: a collection whose early markets are all obscure pushes the one
        liquid pair past the bound, and the most traded token on the chain
        renders as "no pool at any tier".                                  */
    function _against(address t, uint8 d)
        private view returns (address quote, Look[4] memory all)
    {
        quote = VENUE.WRAPPED();
        if (quote != address(0) && quote != t) {
            all = VENUE.survey(t, quote, d);
            for (uint256 i; i < 4; ++i) if (all[i].found) return (quote, all);
        }

        /*  Two passes, and the split is what makes the search affordable.

            The first asks only `getPool` — one cheap call per tier — so a
            long list of candidates costs almost nothing. Only the winner
            gets the full read, which is six more calls per pool.

            The first version of this did the full survey per candidate and
            could therefore only afford four of them, drawn from the first
            eight markets. That sounds like plenty and is not: a collection
            whose early markets trade obscure things pushes the one liquid
            pair past the bound, and the most traded token on the chain
            renders as "no pool at any tier" — a wrong answer wearing the
            costume of a thorough one.                                     */
        (address[] memory list,) = Assets.derive(POOL, 0, 24);
        uint24[4] memory fees = VENUE.tiers();
        address fallbackQuote;
        for (uint256 j; j < list.length; ++j) {
            address cand = list[j];
            if (cand == t || cand == VENUE.WRAPPED()) continue;
            if (fallbackQuote == address(0)) fallbackQuote = cand;
            for (uint256 i; i < 4; ++i) {
                if (VENUE.poolAt(t, cand, fees[i]) == address(0)) continue;
                return (cand, VENUE.survey(t, cand, d));
            }
        }
        /*  Nothing has a pool with it. Still name something, so the page
            says "no pool against X" rather than "no pool against nothing".  */
        return (quote == t || quote == address(0) ? fallbackQuote : quote, all);
    }

    function _facts(address t, uint8 d, address quote) private view returns (string memory) {
        return string.concat(
            "<dl><dt>name</dt><dd>", Web.nameOf(t), "</dd>",
            "<dt>symbol</dt><dd>", Web.symbolOf(t), "</dd>",
            "<dt>decimals</dt><dd>", uint256(d).str(), "</dd>",
            "<dt>priced in</dt><dd>", Web.symbolOf(quote),
                "<span class=m><code>", LibNum.hexAddr(quote), "</code></span></dd>",
            "</dl>"
            "<p class=e>Every one of those came from the token itself, escaped on chain "
            "before it went into this page. A ticker is chosen by whoever deployed the "
            "contract and two tokens may share one, so the address is printed beside it "
            "everywhere it appears.</p>"
        );
    }

    function _tierTable(Look[4] memory all, address quote)
        private view returns (string memory)
    {
        uint24[4] memory fees = VENUE.tiers();
        uint8 dq = Web.decimalsOf(quote);
        string memory rows;
        bool any;
        for (uint256 i; i < 4; ++i) {
            any = any || all[i].found;
            rows = string.concat(
                rows,
                "<tr><td>", Web.amount(uint256(fees[i]), 4, 4), "%</td>",
                all[i].found
                    ? string.concat(
                        "<td>", Web.amount(all[i].spot, dq, 6), " ", Web.symbolOf(quote),
                        "</td><td>", uint256(all[i].liquidity).str(),
                        "</td><td><code>", LibNum.hexAddr(all[i].pool), "</code></td>")
                    : "<td colspan=3 class=m>no pool</td>",
                "</tr>"
            );
        }
        return string.concat(
            "<h2>where it trades</h2>",
            any ? "" : "<p class=e>No Uniswap v3 pool exists for this pair at any fee "
                       "tier. That is an answer, not a failure &mdash; it was read from "
                       "the factory.</p>",
            "<table><tr><th>tier</th><th>price</th><th>liquidity at tick</th>"
            "<th>pool</th></tr>", rows, "</table>"
            "<p class=e>Liquidity here is the in-range liquidity at the current tick, "
            "which is the number that decides what a trade of ordinary size costs. "
            "Total value locked would be the wrong measure: a pool can hold a great deal "
            "of it parked in ranges the price is nowhere near.</p>"
        );
    }

    /*  The chart, drawn by the contract.

        `Venue.history` reads the pool's own ring buffer and returns one
        time-weighted mean tick per interval. Turning each into a bar is a
        division; there is no canvas, no library, and nothing fetched. The
        whole thing is a row of divs whose heights are percentages, so it
        renders in a client with scripting switched off entirely — which is
        the strongest form the claim "this page needs no server" can take. */
    function _chart(Look[4] memory all, address base, address quote, uint8 d)
        private view returns (string memory)
    {
        Look memory best;
        for (uint256 i; i < 4; ++i) {
            if (all[i].found && (!best.found || all[i].liquidity > best.liquidity)) {
                best = all[i];
            }
        }
        if (!best.found) return "";

        (bool ok, int24[] memory ticks, uint32 step) =
            VENUE.history(best.pool, WINDOW, BARS);
        if (!ok || ticks.length == 0) return _noHistory(best.pool);

        int24 lo = ticks[0];
        int24 hi = ticks[0];
        for (uint256 i = 1; i < ticks.length; ++i) {
            if (ticks[i] < lo) lo = ticks[i];
            if (ticks[i] > hi) hi = ticks[i];
        }
        uint256 span = uint256(int256(hi) - int256(lo));

        string memory bars;
        for (uint256 i; i < ticks.length; ++i) {
            uint256 h = span == 0
                ? 50
                : 6 + (uint256(int256(ticks[i]) - int256(lo)) * 88) / span;
            bars = string.concat(bars, "<i style=\"height:", h.str(), "%\"></i>");
        }

        uint256 unit = d > 36 ? 1 : 10 ** uint256(d);
        bool baseIs0 = base < quote;
        uint8 dq = Web.decimalsOf(quote);
        return string.concat(
            "<h2>the pool's own record</h2>",
            "<div class=ch>", bars, "</div>",
            "<dl><dt>high</dt><dd>",
                Web.amount(VENUE.priceAt(baseIs0 ? hi : lo, unit, baseIs0), dq, 6),
                " ", Web.symbolOf(quote), "</dd>",
            "<dt>low</dt><dd>",
                Web.amount(VENUE.priceAt(baseIs0 ? lo : hi, unit, baseIs0), dq, 6),
                " ", Web.symbolOf(quote), "</dd>",
            "<dt>each bar</dt><dd>", uint256(step).str(), " seconds</dd>",
            "<dt>read from</dt><dd><code>", LibNum.hexAddr(best.pool), "</code></dd></dl>",
            "<p class=e>Each bar is a time-weighted average tick over ",
            uint256(step).str(), " seconds, computed by the pool and divided here. It "
            "is not a candle and there is no volume behind it, because a pool records "
            "price and nothing else. What it is instead is a price history that nobody "
            "serving this page could have altered &mdash; and it was drawn by a "
            "contract, so it is here with JavaScript switched off.</p>"
        );
    }

    function _noHistory(address p) private pure returns (string memory) {
        return string.concat(
            "<h2>the pool's own record</h2>"
            "<p class=e>This pool has no history to draw. Every v3 pool is created with "
            "room for exactly <em>one</em> observation &mdash; enough for the current "
            "price and nothing before it &mdash; and the buffer is only longer if "
            "somebody paid to make it longer. That is the common case, not a "
            "malfunction.</p>"
            "<p class=e>Anyone may extend it, permanently, for everyone. The button "
            "below sends <code>increaseObservationCardinalityNext</code> to the pool "
            "itself; after it confirms the pool begins keeping that many observations, "
            "and a chart appears here once enough time has passed to fill them.</p>"
            "<div class=app style=\"padding:.9rem 1rem\">"
            "<div class=hd><b>Lengthen this pool's memory</b></div>"
            "<label>observations to keep</label><input id=gv value=\"300\">"
            "<input id=gp value=\"", LibNum.hexAddr(p), "\" hidden>"
            "<p class=e style=\"margin:.4rem 0 0\">300 observations at roughly one per "
            "block is a few hours of history on a fast chain and a day or two on a slow "
            "one. It costs gas once, in proportion to how many slots are being "
            "reserved.</p>"
            "<button class=go id=grow>Extend it</button><div id=s></div></div>"
        );
    }

    function _closed(uint8 tab, string memory what) private view returns (string memory) {
        return string.concat(
            CHROME.head("IPSEITY"),
            CHROME.navTop(tab),
            "<h1>", what, "</h1>"
            "<p class=e>There is no Uniswap v3 deployment wired up on chain <code>",
            block.chainid.str(),
            "</code>. This contract was given the zero address for the factory, so every "
            "read degrades to \"no venue\" and this page says so instead of showing "
            "prices from nowhere.</p>"
            "<p><a class=g href=\"/open\">the collection's own markets &rarr;</a></p>",
            CHROME.foot(msg.sender, block.chainid)
        );
    }
}
