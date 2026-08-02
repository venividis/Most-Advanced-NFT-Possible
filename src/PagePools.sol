// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibNum} from "./lib/LibNum.sol";
import {Web} from "./lib/Web.sol";
import {Assets} from "./lib/Assets.sol";
import {IChrome, IDesk, IPoolRead, IVenue} from "./interfaces/Site.sol";

interface IDeskUni {
    function config() external view returns (string memory);
    function base() external pure returns (string memory);
}

interface IDeskPos {
    function pos() external pure returns (string memory);
}

/*───────────────────────────────────────────────────────────────────────────
  PagePools — liquidity, ranges, and the position that is a limit order

  Three of the nine things a modern exchange offers are the same transaction
  with different tick bounds, and saying so out loud is more useful than
  giving each of them its own vocabulary:

    · **provide liquidity** is a position spanning every price;
    · **concentrated liquidity** is the same position with the bounds pulled
      in, which multiplies the fees earned per unit deposited and gives up
      earning anything outside the range;
    · **a limit order** is that position taken to its limit — bounds one tick
      apart, entirely on one side of the current price, funded with one token
      and converted to the other as the price crosses.

  All three are `NonfungiblePositionManager.mint`, eleven flat words, sent
  from the visitor's wallet.

  ── what a range order is, and is not ──

  This page will not call it a limit order without qualification, because it
  is not one, and the differences are the sort a person finds out about
  afterwards:

    it fills *gradually* across the range rather than all at once;
    it *un-fills* if the price comes back through;
    it *earns fees* the whole time it is working, which a limit order does
      not;
    and nothing settles it — the tokens sit in the position until you come
      back and withdraw them, in two transactions.

  What it does not need is a server, a relayer, a signature, an off-chain
  order book, or anybody's permission. Uniswap's own limit orders need four
  of those five: an EIP-712 signature POSTed to a hosted book, where fillers
  compete for it. A page with no server cannot place one of those and does
  not pretend to. It can place this, and this settles against the AMM.

  ── creating a pool ──

  Permissionless and one transaction. The only subtlety is that the position
  manager does not sort the pair for you — an unsorted pair derives a pool
  address that does not exist, and the call reverts somewhere unhelpful — so
  the page sorts, and then tells you which way round the price it is asking
  for actually reads.
───────────────────────────────────────────────────────────────────────────*/
contract PagePools {
    using LibNum for uint256;

    IChrome   public immutable CHROME;
    IPoolRead public immutable POOL;
    IDesk     public immutable DESK;
    IDeskUni  public immutable DESKU;
    IDeskPos  public immutable DESKP;
    IVenue    public immutable VENUE;

    constructor(
        IChrome chrome, IPoolRead pool, IDesk desk,
        IDeskUni deskU, IDeskPos deskP, IVenue venue
    ) {
        CHROME = chrome;
        POOL = pool;
        DESK = desk;
        DESKU = deskU;
        DESKP = deskP;
        VENUE = venue;
    }

    /*═══════════════════ /pools ═══════════════════*/

    function pools() external view returns (string memory) {
        if (!VENUE.present()) return _closed(10, "liquidity");
        return string.concat(
            CHROME.head("IPSEITY \xc2\xb7 liquidity"),
            CHROME.navTop(10),
            DESKU.config(),
            "<h1>liquidity</h1>"
            "<p class=e>A Uniswap v3 position is two ticks and an amount. Everything "
            "below is that one transaction with different bounds &mdash; full range, a "
            "band around the current price, or a band you type &mdash; sent from your "
            "wallet to the position manager, whose address is at the bottom of this "
            "page.</p>",
            _yours(),
            _addCard(),
            _createCard(),
            _ranges(),
            _where(),
            DESK.core(),
            DESKU.base(),
            DESKP.pos(),
            CHROME.foot(msg.sender, block.chainid)
        );
    }

    /*═══════════════════ /limit ═══════════════════*/

    function limit() external view returns (string memory) {
        if (!VENUE.present()) return _closed(10, "limit orders");
        return string.concat(
            CHROME.head("IPSEITY \xc2\xb7 limit orders"),
            CHROME.navTop(10),
            DESKU.config(),
            "<h1>an order at a price you choose</h1>",
            _limitProse(),
            _addCard(),
            _yours(),
            _where(),
            DESK.core(),
            DESKU.base(),
            DESKP.pos(),
            CHROME.foot(msg.sender, block.chainid)
        );
    }

    function _limitProse() private pure returns (string memory) {
        return
            "<p class=e>Uniswap's limit orders are not on chain. Placing one is an "
            "EIP-712 signature POSTed to a hosted order book, where independent fillers "
            "compete to execute it; there is no contract a browser can call to place "
            "one, and no registry it could read to list them. A page with no server "
            "cannot do it, and this one does not pretend to.</p>"
            "<p class=e>What it can do is the thing Uniswap's own documentation calls a "
            "<b>range order</b>, and which settles against the AMM itself. Put liquidity "
            "in a narrow band <em>entirely on one side of the current price</em>. Such a "
            "position can only be funded with one of the two tokens &mdash; the pool will "
            "not take the other, because at that price it does not need it &mdash; and as "
            "the price crosses your band the pool converts what you deposited into the "
            "other token. That is a sale at a price you chose, executed by the AMM, with "
            "no counterparty, no relayer and nobody's permission.</p>"
            "<h2>how it differs from a limit order, in the four ways that matter</h2>"
            "<ul class=r>"
            "<li><b>It fills gradually.</b> Across the band, not all at once at one "
            "price. A one-tick band is as close to a single price as the pool allows.</li>"
            "<li><b>It un-fills.</b> If the price comes back through your band, the pool "
            "converts it back. Nothing is final until you withdraw.</li>"
            "<li><b>It earns fees</b> the whole time it is working, which a resting limit "
            "order does not.</li>"
            "<li><b>Nothing settles it.</b> The proceeds sit in the position until you "
            "return and take them out, and that is two transactions &mdash; one to "
            "release the liquidity, one to collect it.</li>"
            "</ul>"
            "<p class=e>Set the range below entirely above the current price to sell the "
            "first token of the pair, or entirely below it to sell the second. The page "
            "shows you the exact prices your ticks mean before you send anything, "
            "because the tick you get is the nearest one on the pool's grid and not the "
            "price you typed.</p>";
    }

    /*═══════════════════ the cards ═══════════════════*/

    function _yours() private pure returns (string memory) {
        return
            "<h2>your positions</h2>"
            "<p class=e>Read straight off the position manager: how many you hold, then "
            "each one by index, then its ticks and what it is owed. No indexer, no "
            "subgraph, nothing cached &mdash; which is also why it stops at twenty.</p>"
            "<div id=pos><p class=e>Connect a wallet to see your positions.</p></div>";
    }

    function _addCard() private view returns (string memory) {
        return string.concat(
            "<h2>a new position</h2>"
            "<div class=app>"
            "<div class=hd><b>Add liquidity</b></div>",
            _pick("First token", "la", "lax"),
            _pick("Second token", "lb", "lbx"),
            "<label>fee tier</label><div class=det id=lt></div>"
            "<label>range</label>"
            "<div><button id=rfull>full range</button>"
            "<button data-span=2>&plusmn;2%</button>"
            "<button data-span=10>&plusmn;10%</button>"
            "<button data-span=25>&plusmn;25%</button></div>"
            "<div class=two style=\"margin-top:.5rem\">"
            "<div><label>min price</label><input id=pmin placeholder=\"0.0\"></div>"
            "<div><label>max price</label><input id=pmax placeholder=\"0.0\"></div></div>"
            "<button id=rcustom>use those prices</button>"
            "<div class=det id=rng></div>"
            "<div class=two>"
            "<div><label>amount, first token</label><input id=a0 placeholder=\"0.0\"></div>"
            "<div><label>amount, second token</label><input id=a1 placeholder=\"0.0\">"
            "</div></div>"
            "<button class=go id=add2>Add liquidity</button>"
            "<div id=s></div></div>"
        );
    }

    function _createCard() private view returns (string memory) {
        return string.concat(
            "<h2>a pool that does not exist yet</h2>"
            "<p class=e>Permissionless, and one transaction. It creates the pool if "
            "there is none and sets its starting price if it has never been set; running "
            "it against a pool that already exists changes nothing. The pair is sorted "
            "by address before it is sent, because the position manager does not sort "
            "for you and an unsorted pair derives an address with no pool at it.</p>"
            "<div class=app><div class=hd><b>Create a pool</b></div>"
            "<label>starting price, second token per first</label>"
            "<input id=p0 placeholder=\"0.0\">"
            "<p class=e style=\"margin:.4rem 0 0\">Uses the pair and fee tier chosen "
            "above. The price is rounded to the nearest tick the pool can represent, and "
            "the range panel above shows what that tick is actually worth.</p>"
            "<button class=go id=mkpool>Create the pool</button></div>"
        );
    }

    function _pick(string memory label, string memory sel, string memory box)
        private view returns (string memory)
    {
        return string.concat(
            "<label>", label, "</label>"
            "<select id=", sel, ">", _options(), "</select>"
            "<input id=", box, " placeholder=\"0x\\u2026 any ERC-20 address\" hidden>"
        );
    }

    function _options() private view returns (string memory) {
        address wr = VENUE.WRAPPED();
        string memory opts = "<option value=\"\">choose\xe2\x80\xa6</option>";
        if (wr != address(0)) opts = string.concat(opts, _option(wr));
        (address[] memory list,) = Assets.derive(POOL, 0, 32);
        for (uint256 i; i < list.length; ++i) {
            if (list[i] == wr) continue;
            opts = string.concat(opts, _option(list[i]));
        }
        return string.concat(opts, "<option value=\"?\">paste an address\xe2\x80\xa6</option>");
    }

    function _option(address t) private view returns (string memory) {
        return string.concat(
            "<option value=\"", LibNum.hexAddr(t), "\">", Web.symbolOf(t), "</option>"
        );
    }

    /*═══════════════════ prose ═══════════════════*/

    function _ranges() private pure returns (string memory) {
        return
            "<h2>why the range is the whole decision</h2>"
            "<p class=e>Liquidity spread across every price earns the fee on every trade "
            "and earns it thinly. Liquidity concentrated near the current price earns the "
            "same fee on the same trades out of a much smaller deposit &mdash; and earns "
            "nothing at all once the price leaves the band, while holding whichever of "
            "the two tokens is now the less valuable one. That last part is the whole "
            "cost and it does not appear on any screen until it has happened.</p>"
            "<p class=e>The ticks are shown next to the prices deliberately. A tick is "
            "what the pool stores; a price is what you meant; and the tick you get is the "
            "nearest multiple of the tier's spacing, which is one basis point apart at "
            "0.01% and two hundred at 1%. Snapping a price to a tick is done on chain "
            "here, and the price that tick is worth is read back on chain, so the number "
            "on the screen is the number the pool will use.</p>";
    }

    function _closed(uint8 tab, string memory what) private view returns (string memory) {
        return string.concat(
            CHROME.head("IPSEITY"),
            CHROME.navTop(tab),
            "<h1>", what, "</h1>"
            "<p class=e>There is no Uniswap v3 deployment wired up on chain <code>",
            block.chainid.str(),
            "</code>, so there is nothing here to provide liquidity to. This contract was "
            "given the zero address for the factory and says so rather than showing a "
            "form that would revert.</p>"
            "<p><a class=g href=\"/open\">the collection's own markets &rarr;</a></p>",
            CHROME.foot(msg.sender, block.chainid)
        );
    }

    function _where() private view returns (string memory) {
        return string.concat(
            "<h2>where these transactions go</h2><dl>",
            "<dt>positions</dt><dd><code>", LibNum.hexAddr(VENUE.POSITIONS()), "</code>"
                "<span class=m>NonfungiblePositionManager &mdash; every button on this "
                "page sends here, and approvals go here too</span></dd>",
            "<dt>factory</dt><dd><code>", LibNum.hexAddr(VENUE.FACTORY()), "</code>"
                "<span class=m>read only, to find out which pools exist</span></dd>",
            "<dt>venue</dt><dd><code>", LibNum.hexAddr(address(VENUE)), "</code>"
                "<span class=m>this collection's reader &mdash; it does the tick "
                "arithmetic and has no function that moves anything</span></dd>",
            "</dl>"
            "<p class=e>Two approvals, one per token, before the first position. "
            "Withdrawing is two transactions: <code>decreaseLiquidity</code> releases the "
            "liquidity into what the position is owed, and <code>collect</code> actually "
            "transfers it. They cannot be batched here &mdash; the position manager's "
            "<code>multicall</code> takes an array of dynamic bytes, and this client has "
            "no ABI coder &mdash; so the page sends them separately and says so rather "
            "than leaving you with a position that looks emptied and has paid out "
            "nothing.</p>"
            "<p class=e>Nothing here has been audited.</p>"
        );
    }
}
