// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibNum} from "./lib/LibNum.sol";
import {Web} from "./lib/Web.sol";
import {IHub, IPoolRead, IChrome, MarketView} from "./interfaces/Site.sol";

/*───────────────────────────────────────────────────────────────────────────
  PageMarket — the counter where the token's exchange is open

  Two pages. One token's market, with a live quote and a trade a visitor can
  actually sign; and the directory of every token currently open for
  business, which is the page that turns four thousand separate objects into
  something you can shop.

  ── the calldata is built here, not in the browser ──

  Each button carries a finished calldata prefix. `swap` takes six
  arguments, and this contract knows four of them at render time — the token
  id, which direction, and the deadline are all fixed by the page you are
  looking at. The visitor supplies an amount and a floor, and the client
  appends two words. No ABI coder ships to the browser and no selector is
  computed there; `0x` followed by eight familiar hex digits is in the page
  source, and it either matches the ABI or it does not.

  ── the directory is paged, and says so ──

  Reading one market is a struct and two ERC-20 metadata calls. Reading four
  thousand is a call no node will finish. So the directory walks a window
  and tells you it did, because the failure mode of a silent cap is a page
  that looks complete and is not.
───────────────────────────────────────────────────────────────────────────*/
contract PageMarket {
    using LibNum for uint256;

    IHub      public immutable HUB;
    IChrome   public immutable CHROME;
    IPoolRead public immutable POOL;

    /// @dev Twenty-four rows, three reads each, roughly 1M gas of `eth_call`.
    uint256 public constant PAGE = 24;

    /// @dev A deadline a page can hardcode has to be far enough out that a
    ///      slow wallet does not miss it and near enough that a transaction
    ///      forgotten in a mempool for a year does not land. `swap` takes
    ///      one because a trade that executes at a price from last week is
    ///      not the trade anyone agreed to.
    uint256 private constant WINDOW = 30 minutes;

    constructor(IHub hub, IChrome chrome, IPoolRead pool) {
        HUB = hub;
        CHROME = chrome;
        POOL = pool;
    }

    /*═══════════════════ /token/<id>/market ═══════════════════*/

    /// @dev One read, packed once. Every helper below takes the struct,
    ///      because twelve loose return values plus four metadata reads is
    ///      more than the stack has room for even through the IR pipeline.
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

        if (!m.open) {
            return string.concat(
                CHROME.head(string.concat("IPSEITY #", t, " \xc2\xb7 market")),
                CHROME.nav(id, 3),
                "<h1>no market</h1>",
                _explain(),
                "<p class=e>Token #", t, " has not opened one. Only its holder can, and "
                "when they do the fee income belongs to the token &mdash; so selling the "
                "NFT would sell the exchange, inventory and price curve together, in one "
                "transaction, with no migration.</p>",
                CHROME.foot(msg.sender, block.chainid)
            );
        }

        return string.concat(
            CHROME.head(string.concat("IPSEITY #", t, " \xc2\xb7 market")),
            CHROME.nav(id, 3),
            "<h1>the market of #", t, "</h1>",
            _explain(),
            _facts(m),
            POOL.paused() ? "<p class=w>Trading is paused collection-wide. Custody is "
                            "not: deposits and withdrawals by holders still work.</p>" : "",
            _desk(id, m),
            _caution(),
            CHROME.foot(msg.sender, block.chainid)
        );
    }

    function _facts(MarketView memory m) private view returns (string memory) {
        return string.concat("<dl>", _pair(m), _prices(m), _facts2(m), "</dl>");
    }

    function _pair(MarketView memory m) private view returns (string memory) {
        return string.concat(
            "<dt>pair</dt><dd>", Web.symbolOf(m.base), " <span class=m>",
                LibNum.hexAddr(m.base), "</span><br>", Web.symbolOf(m.quote),
                " <span class=m>", LibNum.hexAddr(m.quote), "</span></dd>",
            "<dt>reserves</dt><dd>", Web.amount(m.rBase, m.dBase, 6), " ",
                Web.symbolOf(m.base), " &middot; ", Web.amount(m.rQuote, m.dQuote, 6),
                " ", Web.symbolOf(m.quote), "</dd>"
        );
    }

    function _prices(MarketView memory m) private view returns (string memory) {
        return string.concat(
            "<dt>spot</dt><dd>", Web.amount(m.spot, m.dQuote, 8), " ",
                Web.symbolOf(m.quote), " per ", Web.symbolOf(m.base), "</dd>",
            "<dt>fee</dt><dd>", uint256(m.feeBps).str(), " bps, to the token</dd>",
            "<dt>concentration</dt><dd>", m.conc.str(), " bps <span class=m>set by how far "
                "the solid is turned through w</span></dd>"
        );
    }

    function _facts2(MarketView memory m) private view returns (string memory) {
        return string.concat(
            "<dt>most that can leave</dt><dd>", Web.amount(m.maxBaseOut, m.dBase, 6), " ",
                Web.symbolOf(m.base), " &middot; ",
                Web.amount(m.maxQuoteOut, m.dQuote, 6), " ", Web.symbolOf(m.quote),
                "</dd>",
            "<dt>trades</dt><dd>", m.trades.str(), "</dd>",
            "<dt>bonded</dt><dd>", m.bondUntil > block.timestamp
                ? string.concat("until ", uint256(m.bondUntil).str(),
                    " <span class=m>&mdash; nothing leaves and no term moves before then"
                    "</span>")
                : "no", "</dd>"
        );
    }

    function _explain() private pure returns (string memory) {
        return
            "<p class=e>Every token here can be its own exchange. The holder is the only "
            "liquidity provider &mdash; they put the inventory in, set the fee and take the "
            "fee &mdash; and anybody at all may trade against it. Prices are constant "
            "product against <em>virtual</em> reserves, and how far the artwork has been "
            "turned through the fourth axis is what sets them: a barely-turned solid is a "
            "wide forgiving market, a solid turned edge-on is a tight one.</p>";
    }

    /// @dev The trading desk. Two directions, each a quote button and a swap
    ///      button over the same two inputs.
    function _desk(uint256 id, MarketView memory m) private view returns (string memory) {
        return string.concat(
            "<h2>trade</h2>",
            _side(id, true, Web.symbolOf(m.base), Web.symbolOf(m.quote), m.dBase),
            _side(id, false, Web.symbolOf(m.quote), Web.symbolOf(m.base), m.dQuote),
            "<p class=e>Amounts are integers in the token's own smallest unit &mdash; ",
            uint256(m.dBase).str(), " decimals in, ", uint256(m.dQuote).str(), " out for the first "
            "form. <em>Approve the pool first</em>: a swap pulls what you send with "
            "<code>transferFrom</code>, and the pool credits only what actually arrived, "
            "so a fee-on-transfer token is charged honestly rather than assumed away.</p>"
        );
    }

    function _side(uint256 id, bool baseIn, string memory from, string memory to, uint8 dIn)
        private view returns (string memory)
    {
        string memory k = baseIn ? "a" : "b";
        // quote(uint256,bool,uint256) — id and direction fixed here, the
        // amount is the one word the browser appends
        string memory quoteCall = string.concat(
            _sel("quote(uint256,bool,uint256)"), _w(id), _w(baseIn ? 1 : 0)
        );
        // swap(uint256,bool,uint256,uint256,address,uint256) — id, direction
        // fixed; amount, floor and recipient come from the page; the
        // deadline is stamped at render time
        string memory swapCall = string.concat(
            _sel("swap(uint256,bool,uint256,uint256,address,uint256)"),
            _w(id), _w(baseIn ? 1 : 0)
        );
        return string.concat(
            "<div class=card><h3>", from, " &rarr; ", to, "</h3>",
            "<label for=", k, "i>amount in (", uint256(dIn).str(), " decimals)</label>",
            "<input id=", k, "i value=\"0\">",
            "<label for=", k, "m>least you will accept out</label>",
            "<input id=", k, "m value=\"0\">",
            _buttons(k, quoteCall, swapCall),
            "<p class=e>out: <code id=", k, "q>&mdash;</code></p>",
            // the deadline travels as a hidden input so the client's word
            // packer handles it exactly like the others
            "<input type=hidden id=", k, "d value=\"",
                (block.timestamp + WINDOW).str(), "\"></div>"
        );
    }

    function _buttons(string memory k, string memory quoteCall, string memory swapCall)
        private view returns (string memory)
    {
        string memory pool = LibNum.hexAddr(address(POOL));
        return string.concat(
            "<button data-to=\"", pool, "\" data-read",
                " data-call=\"", quoteCall, "\" data-args=\"", k, "i:uint\"",
                " data-out=", k, "q>quote</button>",
            "<button data-to=\"", pool, "\"",
                " data-call=\"", swapCall, "\"",
                " data-args=\"", k, "i:uint,", k, "m:uint,@:addr,", k, "d:uint\">swap</button>"
        );
    }

    function _caution() private pure returns (string memory) {
        return
            "<h2>before you trade</h2>"
            "<p class=e>The holder sets the fee and can move the curve. A market whose "
            "owner can reshape it is not a price feed, and nothing here should be read as "
            "one. What the contract does guarantee is narrower and worth more: no single "
            "trade may take more than half of the reserve it is paid out of, the virtual "
            "offsets are written only when liquidity or the curve changes and never by a "
            "trade, and a bonded market cannot pay anything out or move any term until the "
            "bond expires. None of this has been audited.</p>";
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
                "<td>", uint256(fee).str(), "</td>",
                "<td>", n.str(), "</td></tr>"
            );
        }

        return string.concat(
            CHROME.head("IPSEITY \xc2\xb7 open markets"),
            CHROME.navTop(7),
            "<h1>open for business</h1>"
            "<p class=e>Tokens whose holders have opened a market and put inventory behind "
            "it. Anyone may trade against any of these; the fee goes to the token.</p>",
            found == 0
                ? "<p class=e>No market is open in this range.</p>"
                : string.concat(
                    "<table><tr><th>token</th><th>pair</th><th>reserves</th>"
                    "<th>fee bps</th><th>trades</th></tr>", rows, "</table>"),
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
            PAGE.str(), " markets at a time because reading every one of them in a single "
            "<code>eth_call</code> is a call no node will finish.</p><p>",
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

    /*═══════════════════ calldata, assembled on chain ═══════════════════*/

    function _sel(string memory sig) private pure returns (string memory) {
        bytes4 s = bytes4(keccak256(bytes(sig)));
        bytes memory hexd = "0123456789abcdef";
        bytes memory o = new bytes(10);
        o[0] = "0"; o[1] = "x";
        for (uint256 i; i < 4; ++i) {
            o[2 + i * 2] = hexd[uint8(s[i]) >> 4];
            o[3 + i * 2] = hexd[uint8(s[i]) & 0x0f];
        }
        return string(o);
    }

    function _w(uint256 v) private pure returns (string memory) {
        bytes memory hexd = "0123456789abcdef";
        bytes memory o = new bytes(64);
        for (uint256 i; i < 64; ++i) {
            o[63 - i] = hexd[(v >> (i * 4)) & 0x0f];
        }
        return string(o);
    }
}
