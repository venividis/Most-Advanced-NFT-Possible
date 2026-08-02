// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibNum} from "./lib/LibNum.sol";
import {Web} from "./lib/Web.sol";
import {IChrome, IDesk, IPoolRead, IVenue} from "./interfaces/Site.sol";

interface IDeskUni {
    function config() external view returns (string memory);
    function base() external pure returns (string memory);
}

interface IDeskCivic {
    function civic() external pure returns (string memory);
}

/*───────────────────────────────────────────────────────────────────────────
  PageCivic — a vault you can check, and a governor you can read

  Two surfaces where the honest answer is more interesting than a
  reproduction of the hosted one would have been.

  ── /earn: no vault list, and no APY ──

  Uniswap's Earn tab routes deposits into third-party lending vaults. Two
  things about it cannot be done from a page with no server, and neither is
  faked:

    · **which vaults exist** is not enumerable — there is no on-chain
      registry a single `eth_call` can walk, and a list of addresses
      compiled into this contract would be exactly the "trust me" that the
      rest of this collection refuses;
    · **APY** is a rate over time, which is historical by definition and
      unreadable from any single call. A yield figure on a page like this
      would have come from somewhere the page cannot check.

  What can be done is the part that decides whether the money is safe: given
  an address, ask it. `asset()`, `totalAssets()`, `convertToAssets()` and
  `maxRedeem()` are all ERC-4626 view functions, so this page verifies a
  vault *before* offering a deposit button — it names the underlying asset
  the vault itself declares, prices one share in that asset, and refuses to
  render the form at all for an address that will not answer. Appearing on a
  list is a weaker guarantee than that.

  ── /vote: everything except what the proposal says ──

  Governance is genuinely on chain and this page reads it directly from the
  governor: how many proposals there are, each one's state, its vote counts,
  its quorum. Casting a vote is two flat words.

  One thing is structurally unreachable and it is worth being precise about
  why. `propose()` takes a human-readable `description` and does exactly one
  thing with it: emits it in an event. The stored proposal has no
  description field. Reading an event needs `eth_getLogs`, and **the EVM
  gives contracts no opcode to read past logs at all** — so no Solidity
  anywhere, however clever, can put the text of a proposal on this page. It
  shows the numbers, which are the part that is not somebody's summary, and
  says where the words are.

  A second thing is a trap rather than a limit, and the page says it before
  you can vote: **voting power is snapshotted at each proposal's start
  block**. Delegating today does nothing for a proposal that opened
  yesterday — the vote is accepted, counts zero, and nothing tells you. The
  page reads your current votes and says when they are zero.
───────────────────────────────────────────────────────────────────────────*/
contract PageCivic {
    using LibNum for uint256;

    IChrome    public immutable CHROME;
    IPoolRead  public immutable POOL;
    IDesk      public immutable DESK;
    IDeskUni   public immutable DESKU;
    IDeskCivic public immutable DESKC;
    IVenue     public immutable VENUE;

    /*  Every selector this contract sends, as the signature string it came
        from. `keccak256` of a literal is folded at compile time, so this
        costs nothing at runtime and buys the property the rest of the
        collection insists on: a reader can hash the string themselves and
        check it against the ABI, rather than taking four bytes of hex on
        trust. Four bytes of hex is exactly the sort of thing that is right
        in review and wrong in the deployment.                            */
    bytes4 private constant SEL_ASSET          = bytes4(keccak256("asset()"));
    bytes4 private constant SEL_TOTAL_ASSETS   = bytes4(keccak256("totalAssets()"));
    bytes4 private constant SEL_TO_ASSETS      = bytes4(keccak256("convertToAssets(uint256)"));
    bytes4 private constant SEL_PROPOSAL_COUNT = bytes4(keccak256("proposalCount()"));
    bytes4 private constant SEL_QUORUM         = bytes4(keccak256("quorumVotes()"));
    bytes4 private constant SEL_PROPOSALS      = bytes4(keccak256("proposals(uint256)"));
    bytes4 private constant SEL_STATE          = bytes4(keccak256("state(uint256)"));

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

    /*═══════════════════ /earn ═══════════════════*/

    function earn(address vault) external view returns (string memory) {
        return string.concat(
            CHROME.head("IPSEITY \xc2\xb7 earn"),
            CHROME.navTop(12),
            DESKU.config(),
            "<h1>earn</h1>",
            vault == address(0) ? _earnIndex() : _earnOne(vault),
            DESK.core(),
            DESKU.base(),
            DESKC.civic(),
            CHROME.foot(msg.sender, block.chainid)
        );
    }

    function _earnIndex() private pure returns (string memory) {
        return
            "<p class=e>Uniswap's Earn tab routes deposits into third-party lending "
            "vaults. Two things about that cannot be done from a page with no server, "
            "and neither is faked here.</p>"
            "<p class=e><b>Which vaults exist is not enumerable.</b> There is no "
            "on-chain registry a single call can walk, so there is no list, and a list "
            "of addresses compiled into this contract would be exactly the \"trust me\" "
            "that the rest of this collection refuses. Bring an address.</p>"
            "<p class=e><b>APY cannot be read.</b> It is a rate over time, which is "
            "historical by definition; one <code>eth_call</code> sees one moment. Any "
            "yield figure on a page like this would have come from somewhere the page "
            "cannot check, so there is none.</p>"
            "<p class=e>What is left is the part that decides whether the money is "
            "safe, and it is entirely on chain. ERC-4626 makes a vault answer for "
            "itself: what asset it holds, how much of it, and what one share converts "
            "to. This page asks all three <em>before</em> it shows you anything, and "
            "reports each answer separately &mdash; including \"would not answer\", "
            "which is a different fact from zero and is shown as one. The deposit form "
            "is withheld entirely from an address that will not name an asset, because "
            "that is the read which decides what you would be depositing.</p>"
            "<div class=app style=\"padding:.9rem 1rem\">"
            "<label>an ERC-4626 vault address</label>"
            "<input id=va placeholder=\"0x\xe2\x80\xa6\">"
            "<button class=go id=vgo>Look it up</button></div>";
    }

    function _earnOne(address v) private view returns (string memory) {
        (bool ok, address asset) = _vaultAsset(v);
        if (!ok) {
            return string.concat(
                "<p class=e><code>", LibNum.hexAddr(v), "</code></p>"
                "<p class=w>That address does not answer <code>asset()</code>, so it is "
                "not an ERC-4626 vault as far as this page can tell &mdash; and this page "
                "will not offer a deposit button for something it could not verify.</p>"
                "<p><a class=g href=\"/earn\">try another &rarr;</a></p>"
            );
        }
        uint8 da = Web.decimalsOf(asset);
        uint8 dv = Web.decimalsOf(v);
        (bool okT, uint256 total) = _vaultWord(v, SEL_TOTAL_ASSETS);
        (bool okS, uint256 perShare) = _vaultConvert(v, 10 ** uint256(dv));

        return string.concat(
            "<h2>", Web.symbolOf(v), "</h2>"
            "<p class=e><code>", LibNum.hexAddr(v), "</code></p><dl>",
            "<dt>holds</dt><dd>", Web.symbolOf(asset),
                "<span class=m><code>", LibNum.hexAddr(asset), "</code> &mdash; the "
                "vault named this itself; nothing here decided it</span></dd>",
            "<dt>total assets</dt><dd>", okT
                ? string.concat(Web.amount(total, da, 4), " ", Web.symbolOf(asset))
                : "<span class=w>would not answer <code>totalAssets()</code></span>",
                "</dd>",
            "<dt>one share</dt><dd>", okS
                ? string.concat(Web.amount(perShare, da, 8), " ", Web.symbolOf(asset),
                    "<span class=m>from <code>convertToAssets</code>, at this block"
                    "</span>")
                : "<span class=w>would not answer <code>convertToAssets()</code>"
                  "</span>",
                "</dd>",
            "<dt>share decimals</dt><dd>", uint256(dv).str(),
                "<span class=m>often not the same as the asset's ",
                uint256(da).str(), ", which is where a hand-rolled client goes wrong"
                "</span></dd></dl>",
            _earnCard(v, asset),
            "<p class=e>No yield figure appears above and that is deliberate: a rate "
            "over time cannot be read from a single call, and a number this page could "
            "not check is a number it should not print. What it can tell you is what one "
            "share is worth right now &mdash; come back and look again, and the "
            "difference is the yield, measured rather than quoted.</p>"
            "<p class=e>Nothing here has been audited, and this page has no opinion "
            "whatsoever about whether that vault is a good idea.</p>"
        );
    }

    function _earnCard(address v, address asset) private view returns (string memory) {
        return string.concat(
            "<div class=app>"
            "<div class=hd><b>Deposit</b></div>"
            "<input id=vv value=\"", LibNum.hexAddr(v), "\" hidden>"
            "<input id=vt value=\"", LibNum.hexAddr(asset), "\" hidden>"
            "<div class=fld><div class=lbl><span>You deposit</span>"
            "<span id=vb></span></div>"
            "<div class=row><input id=vi placeholder=\"0.0\" inputmode=decimal>"
            "<span class=tk>", Web.symbolOf(asset), "</span></div></div>"
            "<div class=det id=vd></div>"
            "<button class=go id=vdep>Deposit</button>"
            "<div class=fld style=\"margin-top:1rem\">"
            "<div class=lbl><span>You redeem</span><span id=vsb></span></div>"
            "<div class=row><input id=vr placeholder=\"0.0\" inputmode=decimal>"
            "<span class=tk>", Web.symbolOf(v), "</span></div></div>"
            "<button class=go id=vred>Redeem</button>"
            "<div id=s></div></div>"
        );
    }

    /*  Both reads are raw staticcalls with a stipend, for the same reason
        every other external read on this site is: the address came from
        whoever typed it into the URL bar, and a page that reverts on a
        hostile answer is a page anybody can switch off.                   */
    function _vaultAsset(address v) private view returns (bool, address) {
        if (v.code.length == 0) return (false, address(0));
        (bool ok, bytes memory out) =
            v.staticcall{gas: 40_000}(abi.encodeWithSelector(SEL_ASSET));
        if (!ok || out.length < 32) return (false, address(0));
        address a = abi.decode(out, (address));
        return a == address(0) || a.code.length == 0 ? (false, address(0)) : (true, a);
    }

    /*  Both of these return whether the call worked, separately from what
        it returned, and that separation is the whole point.

        They used to return a bare `uint256` and answer zero for "the call
        reverted", "the call ran out of its stipend" and "the value really is
        zero" alike. So a working vault whose `totalAssets` needed more gas
        than the stipend rendered as "total assets 0" and "one share 0" —
        beside a live deposit button, under prose promising every number was
        read from the vault. A page that cannot tell silence from zero should
        not print either.

        The stipends are larger than they were, too: an aggregating vault's
        `totalAssets` walks its allocations and 60k does not cover that. But
        a bigger cap is not the fix, because any cap can be exceeded — the
        fix is that exceeding it is visible.                              */
    function _vaultWord(address v, bytes4 s) private view returns (bool, uint256) {
        (bool ok, bytes memory out) =
            v.staticcall{gas: 400_000}(abi.encodeWithSelector(s));
        if (!ok || out.length < 32) return (false, 0);
        return (true, abi.decode(out, (uint256)));
    }

    function _vaultConvert(address v, uint256 shares) private view returns (bool, uint256) {
        (bool ok, bytes memory out) = v.staticcall{gas: 400_000}(
            abi.encodeWithSelector(SEL_TO_ASSETS, shares));
        if (!ok || out.length < 32) return (false, 0);
        return (true, abi.decode(out, (uint256)));
    }

    /*═══════════════════ /vote ═══════════════════*/

    function vote() external view returns (string memory) {
        address g = VENUE.GOVERNOR();
        return string.concat(
            CHROME.head("IPSEITY \xc2\xb7 vote"),
            CHROME.navTop(13),
            DESKU.config(),
            "<h1>governance</h1>",
            g == address(0) || g.code.length == 0
                ? string.concat(
                    "<p class=e>No governor is wired up on chain <code>",
                    block.chainid.str(),
                    "</code> &mdash; this deployment was given the zero address, so "
                    "there is nothing here to read. Uniswap's governance lives on "
                    "Ethereum mainnet and nowhere else; the other chains have no "
                    "governor of their own, which is a fact about Uniswap rather than "
                    "a gap in this page.</p>")
                : _voteBody(g),
            DESK.core(),
            DESKU.base(),
            DESKC.civic(),
            CHROME.foot(msg.sender, block.chainid)
        );
    }

    function _voteBody(address g) private view returns (string memory) {
        (, uint256 count) = _govWord(g, abi.encodeWithSelector(SEL_PROPOSAL_COUNT));
        (bool okQ, uint256 quorum) = _govWord(g, abi.encodeWithSelector(SEL_QUORUM));
        string memory rows;
        uint256 shown;
        for (uint256 id = count; id > 0 && shown < 8; --id) {
            rows = string.concat(rows, _proposal(g, id));
            ++shown;
        }
        return string.concat(
            "<p class=e>Read straight from the governor at <code>", LibNum.hexAddr(g),
            "</code>. Every number below is a view call to that contract at this block "
            "&mdash; not an index of it, not a cache of it.</p>",
            _voteWarning(),
            "<dl><dt>proposals</dt><dd>", count.str(), "</dd>",
            "<dt>quorum</dt><dd>", okQ
                ? string.concat(Web.amount(quorum, 18, 0),
                    " votes<span class=m>what a proposal needs in favour to pass at "
                    "all</span>")
                : "<span class=w>would not answer <code>quorumVotes()</code></span>",
                "</dd></dl>",
            count == 0
                ? "<p class=e>No proposals have ever been made here.</p>"
                : string.concat(
                    "<h2>the last ", shown.str(), "</h2>"
                    "<table><tr><th>id</th><th>state</th><th>for</th><th>against</th>"
                    "<th>abstain</th><th></th></tr>", rows, "</table>"),
            _voteCard(g),
            _voteProse()
        );
    }

    function _voteWarning() private view returns (string memory) {
        return string.concat(
            "<div class=app style=\"padding:.9rem 1rem;max-width:none\">"
            "<div class=hd><b>before you vote</b></div>"
            "<p class=e style=\"margin:0\">Voting power is <b>snapshotted at each "
            "proposal's start block</b>. Delegating today does nothing for a proposal "
            "that opened yesterday &mdash; the vote is cast, it counts zero, and nothing "
            "tells you. Your current voting power is <b id=vp>connect a wallet</b>, and "
            "if that is zero while you hold the token, it is because you have never "
            "delegated. Delegating to yourself is one transaction and costs nothing but "
            "gas.</p>"
            "<input id=gg value=\"", LibNum.hexAddr(VENUE.GOVERNOR()), "\" hidden>"
            "<input id=gt value=\"", LibNum.hexAddr(VENUE.GOV_TOKEN()), "\" hidden>"
            "<button id=gdel>Delegate to myself</button><div id=s></div></div>"
        );
    }

    /// @dev `proposals(uint256)` is an auto-generated getter, so it returns
    ///      ten static words and silently omits the four dynamic arrays and
    ///      the receipts mapping the struct also holds. Reading word 5 as
    ///      `forVotes` is only correct because of that omission.
    function _proposal(address g, uint256 id) private view returns (string memory) {
        (bool ok, bytes memory out) = g.staticcall{gas: 80_000}(
            abi.encodeWithSelector(SEL_PROPOSALS, id));
        if (!ok || out.length < 320) {
            return string.concat("<tr><td>", id.str(),
                "</td><td colspan=5 class=m>would not answer</td></tr>");
        }
        uint256 forV;
        uint256 against;
        uint256 abstain;
        assembly ("memory-safe") {
            forV := mload(add(out, 192))       // word 5
            against := mload(add(out, 224))    // word 6
            abstain := mload(add(out, 256))    // word 7
        }
        (bool okS, uint256 st) = _govWord(g, abi.encodeWithSelector(SEL_STATE, id));
        return string.concat(
            "<tr><td>", id.str(), "</td><td>",
            okS ? _state(st) : "<span class=m>unreadable</span>", "</td>",
            "<td>", Web.amount(forV, 18, 0), "</td>",
            "<td>", Web.amount(against, 18, 0), "</td>",
            "<td>", Web.amount(abstain, 18, 0), "</td>",
            "<td><button data-vote=\"", id.str(), "\">vote</button></td></tr>"
        );
    }

    function _state(uint256 s) private pure returns (string memory) {
        if (s == 0) return "pending";
        if (s == 1) return "<b class=ok>active</b>";
        if (s == 2) return "canceled";
        if (s == 3) return "defeated";
        if (s == 4) return "succeeded";
        if (s == 5) return "queued";
        if (s == 6) return "expired";
        if (s == 7) return "executed";
        return "?";
    }

    function _voteCard(address) private pure returns (string memory) {
        return
            "<div class=app><div class=hd><b>Cast a vote</b></div>"
            "<label>proposal</label><input id=pid placeholder=\"id\">"
            "<label>how</label>"
            "<div><button data-support=1>for</button>"
            "<button data-support=0>against</button>"
            "<button data-support=2>abstain</button></div>"
            "<div class=det id=vsel></div>"
            "<button class=go id=cast>Cast it</button></div>";
    }

    function _voteProse() private pure returns (string memory) {
        return
            "<h2>what this page cannot show you</h2>"
            "<p class=e>The text of a proposal. Not a shortcut that was skipped &mdash; "
            "a structural impossibility. <code>propose()</code> takes a human-readable "
            "description and does exactly one thing with it: emits it in an event. The "
            "stored proposal has no description field. Reading an event needs "
            "<code>eth_getLogs</code>, and <b>the EVM gives contracts no opcode to read "
            "past logs at all</b>, so no Solidity anywhere can put those words on this "
            "page. Everything above is what the governor stores; the words live in the "
            "logs, and a client that wants them has to ask a node for them.</p>"
            "<p class=e>Voting through this page is <code>castVote(uint256,uint8)</code> "
            "&mdash; two flat words, straight from your wallet to the governor. The "
            "variant that carries a reason string is not offered, because encoding a "
            "dynamic argument needs an ABI coder and this client does not ship one; "
            "offering a reason box that silently dropped the reason would be worse than "
            "not offering it.</p>";
    }

    /// @dev Same separation, and here it mattered more than anywhere: the
    ///      ProposalState enum's zero is `Pending`, so a `state()` call that
    ///      failed rendered as a real, specific, wrong answer — a defeated
    ///      proposal shown as one that has not opened yet.
    function _govWord(address g, bytes memory data) private view returns (bool, uint256) {
        (bool ok, bytes memory out) = g.staticcall{gas: 120_000}(data);
        if (!ok || out.length < 32) return (false, 0);
        return (true, abi.decode(out, (uint256)));
    }

    /*═══════════════════ shared ═══════════════════*/

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
