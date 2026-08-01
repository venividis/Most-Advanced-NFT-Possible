// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibNum} from "./lib/LibNum.sol";
import {Web} from "./lib/Web.sol";
import {IHub, IPoolRead, IChrome, IDesk, MarketView} from "./interfaces/Site.sol";

/*───────────────────────────────────────────────────────────────────────────
  PageMarket — the swap card, and the directory of everything open

  The version before this listed twelve facts and offered two text boxes: an
  integer amount in the token's smallest unit, and a floor the visitor was
  expected to work out by hand before they had seen the quote. It was
  accurate and nobody could have used it.

  This is the shape exchanges converged on, and it is worth being precise
  about why rather than treating it as decoration. Every element answers a
  question a person actually has, in the order they have it: what am I
  paying, what do I get, at what rate, what is the worst case, and is there
  one button or two. The approve-then-swap step is the one most often hidden
  and it is the one most worth showing, because it is two transactions and a
  person who does not know that will think the first one failed.

  What the page does NOT do is decide anything. The quote comes from
  `Pool.quote` at the block you are looking at, the floor is that quote less
  a slippage tolerance you set, the deadline is a number of minutes you set,
  and the calldata is assembled from selectors this contract computed. There
  is no router, no path-finding, no private mempool and no relayer. The
  transaction your wallet shows you is the transaction this page built, and
  you can read it in the page source.
───────────────────────────────────────────────────────────────────────────*/
contract PageMarket {
    using LibNum for uint256;

    IHub      public immutable HUB;
    IChrome   public immutable CHROME;
    IPoolRead public immutable POOL;
    IDesk     public immutable DESK;

    /// @dev Twenty-four rows, three reads each, roughly 1M gas of `eth_call`.
    uint256 public constant PAGE = 24;

    constructor(IHub hub, IChrome chrome, IPoolRead pool, IDesk desk) {
        HUB = hub;
        CHROME = chrome;
        POOL = pool;
        DESK = desk;
    }

    /*═══════════════════ /token/<id>/market ═══════════════════*/

    function _read(uint256 id) private view returns (MarketView memory m) {
        (
            m.base, m.quote, m.rBase, m.rQuote, m.feeBps, m.open,
            m.conc, m.spot, m.maxBaseOut, m.maxQuoteOut, m.trades, m.bondUntil
        ) = POOL.market(id);
        m.dBase = Web.decimalsOf(m.base);
        m.dQuote = Web.decimalsOf(m.quote);
    }

    function market(uint256 id) external view returns (string memory) {
        string memory t = id.str();
        MarketView memory m = _read(id);
        return string.concat(
            CHROME.head(string.concat("Swap \xc2\xb7 IPSEITY #", t)),
            CHROME.nav(id, 3),
            CHROME.tabs(t, 0),
            DESK.config(id),
            m.open ? _card(m) : _shut(t),
            m.open ? _facts(id, m) : "",
            DESK.core(),
            m.open ? DESK.swap() : "",
            CHROME.foot(msg.sender, block.chainid)
        );
    }

    /// @dev The card. One column, and the button says which of the two
    ///      transactions it is about to send.
    function _card(MarketView memory m) private view returns (string memory) {
        return string.concat(
            "<div class=app>"
            "<div class=hd><b>Swap</b>"
            "<button class=ico id=cog>slippage &amp; deadline</button></div>"
            "<div class=set id=set hidden>"
            "<div>Slippage tolerance, now <b id=sl>0.5%</b> &mdash; the most the price "
            "may move against you "
            "between now and the block your trade lands in. Past it the trade reverts "
            "rather than filling badly.</div>"
            "<button data-slip=10>0.1%</button><button data-slip=50>0.5%</button>"
            "<button data-slip=100>1%</button><button data-slip=300>3%</button>"
            "<div style=\"margin-top:.5rem\">Deadline "
            "<input id=dl value=\"30\"> minutes</div></div>",
            _side("You pay", "si", "bi", "ts", Web.symbolOf(m.base), true),
            "<button class=flip id=flip title=\"turn it round\">&darr;</button>",
            _side("You receive", "so", "bo", "rs", Web.symbolOf(m.quote), false),
            "<div class=det id=det></div>"
            "<button class=go id=go disabled>Enter an amount</button>"
            "<div id=s></div></div>"
        );
    }

    function _side(
        string memory label, string memory input, string memory balance,
        string memory tick, string memory sym, bool editable
    ) private pure returns (string memory) {
        return string.concat(
            "<div class=fld><div class=lbl><span>", label,
            "</span><span id=", balance, "></span></div>"
            "<div class=row><input id=", input, " placeholder=\"0.0\" inputmode=decimal",
            editable ? "" : " readonly", ">",
            editable ? "<button class=mx id=mx>MAX</button>" : "",
            "<span class=tk id=", tick, ">", sym, "</span></div></div>"
        );
    }

    function _shut(string memory t) private pure returns (string memory) {
        return string.concat(
            "<div class=app><div class=hd><b>Swap</b></div>"
            "<p class=e>Token #", t, " has not opened a market. Only its holder can, "
            "against any pair of ERC-20s, and when they do the fee income belongs to "
            "the token &mdash; so selling the NFT would sell the exchange, inventory "
            "and price curve together, in one transaction, with no migration.</p>"
            "<p><a class=g href=\"/token/", t, "/pool\">open one &rarr;</a></p></div>"
        );
    }

    /*═══════════════════ underneath, where a person looks second ═══════════════════*/

    function _facts(uint256 id, MarketView memory m) private view returns (string memory) {
        return string.concat(
            "<h2>this market</h2><dl>",
            "<dt>pair</dt><dd>", Web.symbolOf(m.base), " / ", Web.symbolOf(m.quote),
                "<span class=m>", LibNum.hexAddr(m.base), "</span>",
                "<span class=m>", LibNum.hexAddr(m.quote), "</span></dd>",
            "<dt>inventory</dt><dd>", Web.amount(m.rBase, m.dBase, 6), " ",
                Web.symbolOf(m.base), " &middot; ", Web.amount(m.rQuote, m.dQuote, 6),
                " ", Web.symbolOf(m.quote), "</dd>",
            "<dt>fee</dt><dd>", Web.amount(uint256(m.feeBps), 2, 2),
                "% &mdash; to the token, not to a protocol</dd>",
            _facts2(id, m),
            "</dl>", _caution()
        );
    }

    function _facts2(uint256 id, MarketView memory m) private view returns (string memory) {
        return string.concat(
            "<dt>concentration</dt><dd>", m.conc.str(), " bps <span class=m>set by how far "
                "the solid has been turned through w</span></dd>",
            "<dt>trades</dt><dd>", m.trades.str(), "</dd>",
            "<dt>bonded</dt><dd>", m.bondUntil > block.timestamp
                ? string.concat("until ", uint256(m.bondUntil).str(),
                    " <span class=m>&mdash; nothing leaves and no term moves before then"
                    "</span>")
                : "no", "</dd>",
            "<dt>liquidity</dt><dd><code>", LibNum.hexAddr(HUB.ownerOf(id)), "</code>"
                "<span class=m>whoever holds #", id.str(), " is the only provider, and "
                "takes the fee</span></dd>",
            POOL.paused()
                ? "<dt>paused</dt><dd class=w>Trading is halted collection-wide. Custody "
                  "is not: the holder can still deposit and withdraw.</dd>"
                : ""
        );
    }

    function _caution() private pure returns (string memory) {
        return
            "<h2>before you trade</h2>"
            "<p class=e>The holder sets the fee and can reshape the curve. A market "
            "whose owner can move it is not a price feed and nothing here should be "
            "read as one. What the contract does guarantee is narrower and worth more: "
            "no single trade may take more than half the reserve it is paid out of, the "
            "virtual offsets are written only when liquidity or the curve changes and "
            "never by a trade, and a bonded market cannot pay anything out or move any "
            "term until the bond expires.</p>"
            "<p class=e>The first trade in a given direction takes two transactions: one "
            "approving the pool to move the token you are sending, one to swap. The "
            "button says which it is about to send, because a person who does not know "
            "that will think the first one failed. Nothing here has been audited.</p>";
    }

    /*═══════════════════ /open ═══════════════════*/

    function open(uint256 page) external view returns (string memory) {
        uint256 supply = HUB.totalSupply();
        uint256 from = page * PAGE + 1;
        uint256 to = from + PAGE - 1;
        if (to > supply) to = supply;

        string memory rows;
        uint256 found;
        for (uint256 id = from; id <= to && id <= supply; ++id) {
            (address b, address q, uint112 rb, uint112 rq, uint16 fee, bool isOpen,,,,, uint256 n,)
                = POOL.market(id);
            if (!isOpen) continue;
            ++found;
            rows = string.concat(
                rows,
                "<tr><td><a href=\"/token/", id.str(), "/market\">#", id.str(), "</a></td>",
                "<td>", Web.symbolOf(b), " / ", Web.symbolOf(q), "</td>",
                "<td>", Web.amount(rb, Web.decimalsOf(b), 3), " / ",
                        Web.amount(rq, Web.decimalsOf(q), 3), "</td>",
                "<td>", Web.amount(uint256(fee), 2, 2), "%</td>",
                "<td>", n.str(), "</td>",
                "<td><a href=\"/token/", id.str(), "/market\">trade &rarr;</a></td></tr>"
            );
        }

        return string.concat(
            CHROME.head("IPSEITY \xc2\xb7 open markets"),
            CHROME.navTop(7),
            "<h1>open for business</h1>"
            "<p class=e>Tokens whose holders have opened a market and put inventory "
            "behind it. Anyone may trade against any of these; the fee goes to the "
            "token.</p>",
            found == 0
                ? "<p class=e>No market is open in this range.</p>"
                : string.concat(
                    "<table><tr><th>token</th><th>pair</th><th>inventory</th>"
                    "<th>fee</th><th>trades</th><th></th></tr>", rows, "</table>"),
            _pager(page, from, to, supply, found),
            CHROME.foot(msg.sender, block.chainid)
        );
    }

    /// @dev Says what it looked at. A directory that quietly stops at
    ///      twenty-four reads like a directory of everything there is.
    function _pager(uint256 page, uint256 from, uint256 to, uint256 supply, uint256 found)
        private pure returns (string memory)
    {
        return string.concat(
            "<p class=e>Looked at tokens ", from.str(), " to ", to.str(), " of ",
            supply.str(), " issued, and found ", found.str(), " open. This page reads ",
            PAGE.str(), " markets at a time because reading every one of them in a "
            "single <code>eth_call</code> is a call no node will finish.</p><p>",
            page > 0
                ? string.concat("<a class=g href=\"/open/", (page - 1).str(),
                                "\">&larr; earlier</a>")
                : "",
            to < supply
                ? string.concat("<a class=g href=\"/open/", (page + 1).str(),
                                "\">later &rarr;</a>")
                : "",
            "</p>"
        );
    }
}
