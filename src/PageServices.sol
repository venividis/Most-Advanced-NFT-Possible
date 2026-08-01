// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibNum} from "./lib/LibNum.sol";
import {Web} from "./lib/Web.sol";
import {IHub, ILeaseRead, IChrome, IRendererDoc} from "./interfaces/Site.sol";

/*───────────────────────────────────────────────────────────────────────────
  PageServices — renting the instrument, and the two hands

  ── why the rent buttons are fixed terms ──

  `rent` demands an exact `msg.value`, because a contract that accepts an
  overpayment has to send change, and sending change is a call to an address
  a stranger chose in the middle of a state transition. Refusing is one
  line; refunding safely is a re-entrancy surface and a griefing surface for
  no benefit anyone asked for.

  That leaves the page to say the exact number, which it can, because it is
  a contract and it can multiply. So the terms on offer are buttons with the
  day count and the wei both stamped in at render time. The browser sends
  what it was handed. It does not compute a price, which means it cannot
  compute one wrong.

  ── the price guard ──

  Each button also carries the price it was rendered against. A holder can
  raise the rent while a transaction is in the mempool; `maxPerDay` is the
  same defence `swap` takes with `minOut`, and here the page fills it in
  because the page is the thing that knows what it quoted.
───────────────────────────────────────────────────────────────────────────*/
contract PageServices {
    using LibNum for uint256;

    IHub       public immutable HUB;
    IChrome    public immutable CHROME;
    ILeaseRead public immutable LEASE;
    address    public immutable LEASE_ADDR;

    constructor(IHub hub, IChrome chrome, ILeaseRead lease) {
        HUB = hub;
        CHROME = chrome;
        LEASE = lease;
        LEASE_ADDR = address(lease);
    }

    /*═══════════════════ /token/<id>/rent ═══════════════════*/

    function rent(uint256 id) external view returns (string memory) {
        string memory t = id.str();
        (
            bool ok, uint8 reason,
            uint128 perDay, uint32 minD, uint32 maxD,
            address renter, uint64 until,
            uint256 vested, bool bound
        ) = LEASE.listing(id);

        return string.concat(
            CHROME.head(string.concat("IPSEITY #", t, " \xc2\xb7 rent")),
            CHROME.nav(id, 4),
            "<h1>rent #", t, "</h1>",
            _whatRentingIs(),
            _state(ok, reason, renter, until, bound),
            ok ? _terms(id, perDay, minD, maxD) : "",
            _standing(id, vested),
            _rules(),
            CHROME.foot(msg.sender, block.chainid)
        );
    }

    function _whatRentingIs() private pure returns (string memory) {
        return
            "<p class=e>ERC-4907 has been in this token since the beginning, and the line "
            "it draws is the interesting part. A renter is an <em>operator</em>: they may "
            "turn the solid, commit new orientations, set the traits the holder left "
            "writable &mdash; they may drive the instrument, and every change they make is "
            "the token's real state, not a preview. What a renter can never do is sell it, "
            "approve it, lock it, or touch either vault. The contract enforces that "
            "distinction rather than asking anybody to respect it.</p>"
            "<p class=e>Rent goes to the <em>token</em>, not to the address holding it. "
            "That is the same rule the market runs on: fees land in the market's reserves, "
            "so selling the NFT sells the exchange. Sell mid-term and the unpaid rent goes "
            "with it, because the business was never the seller's.</p>";
    }

    function _state(bool ok, uint8 reason, address renter, uint64 until, bool bound)
        private pure returns (string memory)
    {
        if (ok) {
            return string.concat(
                "<p class=ok>Available now.</p>",
                bound ? "<p class=e>This token is bound &mdash; ERC-5192 locked, so it "
                        "cannot be sold at all. For a renter that is a feature: the one "
                        "way a lease here can be cut short is the holder moving the token, "
                        "and this one cannot move.</p>" : ""
            );
        }
        if (reason == 3) {
            return string.concat(
                "<p class=w>Let to <code>", LibNum.hexAddr(renter), "</code> until ",
                uint256(until).str(), " (unix). It becomes available again on its own; "
                "nobody has to do anything.</p>"
            );
        }
        if (reason == 2) {
            return
                "<p class=e>Not on offer. The holder has not named this lease market on "
                "the token, so nothing here can set a user on it &mdash; which is the "
                "correct default, and is what makes naming one a deliberate act.</p>";
        }
        return "<p class=e>Not on offer. The holder has published no terms.</p>";
    }

    /// @dev Up to four terms, each an exact number of days at an exact
    ///      number of wei. Deduplicated, and clamped into what the holder
    ///      will actually accept.
    function _terms(uint256 id, uint128 perDay, uint32 minD, uint32 maxD)
        private view returns (string memory out)
    {
        uint32[4] memory want = [minD, uint32(7), uint32(30), maxD];
        out = string.concat(
            "<h2>terms</h2><p class=e>", Web.amount(perDay, 18, 9),
            " ETH per day &middot; ", uint256(minD).str(), " to ", uint256(maxD).str(),
            " days.</p><div class=card>"
        );
        uint32 last;
        for (uint256 i; i < 4; ++i) {
            uint32 d = want[i];
            if (d < minD || d > maxD || d == last) continue;
            last = d;
            uint256 due = uint256(perDay) * uint256(d);
            out = string.concat(
                out,
                "<button data-to=\"", LibNum.hexAddr(LEASE_ADDR), "\"",
                " data-value=\"", due.str(), "\"",
                " data-call=\"", _sel("rent(uint256,uint32,uint128)"),
                    _w(id), _w(d), _w(perDay), "\">",
                uint256(d).str(), " day", d == 1 ? "" : "s", " &mdash; ",
                Web.amount(due, 18, 9), " ETH</button>"
            );
        }
        return string.concat(
            out,
            "<p class=e>Each button sends the exact wei shown and carries ",
            Web.amount(perDay, 18, 9), " ETH/day as the most it will pay, so a price "
            "raised while your transaction waits makes it fail rather than cost more.</p>"
            "</div>"
        );
    }

    function _standing(uint256 id, uint256 vested) private view returns (string memory) {
        return string.concat(
            "<h2>standing accounts</h2>"
            "<dl><dt>vested to token</dt><dd>", Web.amount(vested, 18, 9),
            " ETH <span class=m>collectable by whoever holds #", id.str(),
            " when they collect it</span></dd></dl>"
            "<p class=e>A lease that ran its term vests whole. One cut short vests the "
            "elapsed fraction and the rest becomes the renter's to reclaim &mdash; nobody "
            "declares that a lease was broken, it is read off the token: the user is no "
            "longer the renter and the term is not up.</p>"
            "<button data-to=\"", LibNum.hexAddr(LEASE_ADDR), "\" data-call=\"",
                _sel("settle(uint256)"), _w(id), "\">bring the books up to date</button>"
            "<button data-to=\"", LibNum.hexAddr(LEASE_ADDR), "\" data-call=\"",
                _sel("claim()"), "\">reclaim rent for time I did not get</button>"
        );
    }

    function _rules() private pure returns (string memory) {
        return
            "<h2>the fine print, which is short</h2>"
            "<p class=e>There is no protocol fee. No cut for the curator, no treasury "
            "address, no switch to add one later &mdash; every wei a renter pays is owed "
            "to the token they paid it to.</p>"
            "<p class=e>The holder keeps the last word: <code>setUser</code> is still "
            "theirs, so they can end a lease at any moment. Doing it costs them exactly "
            "what it was earning them, which is the most a contract can do about it "
            "without taking the token hostage. If you need certainty for the full term, "
            "rent one that is bound.</p>"
            "<p class=e>One renter at a time. Nothing here has been audited.</p>";
    }

    /*═══════════════════ /token/<id>/vault ═══════════════════*/

    function vault(uint256 id) external view returns (string memory) {
        string memory t = id.str();
        address reach = HUB.account(id);
        address grip = HUB.grip(id);

        return string.concat(
            CHROME.head(string.concat("IPSEITY #", t, " \xc2\xb7 vault")),
            CHROME.nav(id, 5),
            "<h1>the two hands</h1>"
            "<p class=e>Every token owns two addresses, derived under ERC-6551 from the "
            "registry, the implementation, this chain and this token id. They are not "
            "granted; they are computed, and you can compute them yourself.</p>",
            _hand(
                "Reach", reach,
                "The hand that acts. It can hold, spend, sign and call &mdash; and while "
                "it is sealed it is policed by measurement rather than by a list of "
                "forbidden functions: the account records what it holds before a call and "
                "after, and refuses any call that left it holding less of anything it "
                "promised to keep.",
                reach.code.length > 0
            ),
            _hand(
                "Grip", grip,
                "The hand that only receives. There is no spend function in the bytecode "
                "&mdash; not a guarded one, not an owner-only one, none. Anything paid in "
                "belongs to the token for as long as the chain lasts, which makes it a "
                "floor under the token's value that a seller cannot empty between a "
                "handshake and a settlement.",
                grip.code.length > 0
            ),
            _give(id, grip),
            _draw(id),
            _verify(reach),
            CHROME.foot(msg.sender, block.chainid)
        );
    }

    function _hand(string memory name, address a, string memory what, bool deployed)
        private pure returns (string memory)
    {
        return string.concat(
            "<div class=card><h3>", name, " &mdash; <code>", LibNum.hexAddr(a), "</code>"
            "</h3><p class=e>", what, "</p><p class=e>",
            deployed
                ? "<span class=ok>Deployed.</span> Value sent here is held by the token."
                : "<span class=w>Not deployed yet.</span> The address is fixed regardless "
                  "&mdash; value sent to it now is held at that address and becomes "
                  "reachable the moment anyone calls <code>embody</code>, which needs no "
                  "permission.",
            "</p></div>"
        );
    }

    function _give(uint256 id, address grip) private pure returns (string memory) {
        return string.concat(
            "<h2 id=give>give</h2>"
            "<p class=e>Paying into the Grip is not a donation to the holder. It is a "
            "donation to the <em>token</em>, permanently, and the only person it ever "
            "benefits is whoever holds the token &mdash; today and every day after. There "
            "is no way to undo it, including for you.</p>"
            "<label for=gv>wei to send to the Grip of #", id.str(), "</label>"
            "<input id=gv value=\"0\">"
            "<button data-to=\"", LibNum.hexAddr(grip), "\" data-call=\"0x\""
            " data-value=\"0\" data-valfrom=\"gv\">send, permanently</button>"
            "<p class=e>Plain value transfer, empty calldata. ERC-20s and NFTs work the "
            "same way: send them to that address.</p>"
        );
    }

    function _draw(uint256 id) private view returns (string memory) {
        address sigil;
        address r = HUB.renderer();
        if (r != address(0)) {
            (bool ok, bytes memory out) =
                r.staticcall(abi.encodeWithSelector(IRendererDoc.sigil.selector));
            if (ok && out.length >= 32) sigil = abi.decode(out, (address));
        }
        if (sigil == address(0)) return "";

        return string.concat(
            "<h2 id=draw>draw</h2>"
            "<p class=e>The contract that renders this token's still image is a "
            "four-dimensional projector written in Solidity, and it is "
            "<code>public pure</code>. It takes a section word and a seed, turns sixteen "
            "4-vectors through six Givens rotations, divides through by distance along w, "
            "and returns SVG path data. It does not check who is asking, and it does not "
            "check that the word belongs to any token &mdash; so it is a public good that "
            "happens to live inside this collection rather than a service of it.</p>"
            "<dl><dt>projector</dt><dd><code>", LibNum.hexAddr(sigil), "</code></dd>"
            "<dt>signature</dt><dd><code>pathAlong(uint256 word, bytes32 seed, uint8 "
            "drop)</code></dd>"
            "<dt>drop</dt><dd>which axis to project along: 0 x, 1 y, 2 z, 3 w. Three of "
            "those four are elevations nothing three-dimensional could cast.</dd></dl>"
            "<label for=dw>section word</label>"
            "<input id=dw value=\"", HUB.sectionOf(id).str(), "\">"
            "<button data-to=\"", LibNum.hexAddr(sigil), "\" data-read"
            " data-call=\"", _sel("pathAlong(uint256,bytes32,uint8)"),
            "\" data-args=\"dw:uint,ds:uint,dd:uint\" data-out=dr>call it</button>"
            "<input type=hidden id=ds value=\"0\"><input type=hidden id=dd value=\"3\">"
            "<p class=e>first word of the return: <code id=dr>&mdash;</code> "
            "<span class=m>(the answer is a byte string; a page this size shows you its "
            "head, not its contents)</span></p>"
        );
    }

    function _verify(address reach) private view returns (string memory) {
        bytes32 dom;
        if (reach.code.length > 0) {
            (bool ok, bytes memory out) =
                reach.staticcall(abi.encodeWithSignature("domainSeparator()"));
            if (ok && out.length >= 32) dom = abi.decode(out, (bytes32));
        }
        return string.concat(
            "<h2 id=verify>verify</h2>"
            "<p class=e>The token can speak as itself. Its Reach account answers ERC-1271, "
            "and the answer is deliberately narrow: it validates a digest only if that "
            "digest can be rebuilt under the account's own EIP-712 domain, from an "
            "attestation struct carrying a purpose, a payload, a nonce and a deadline. "
            "Every other digest is refused, including a valid signature by the holder over "
            "something else &mdash; a sealed vault must not be a general-purpose signing "
            "oracle for whoever holds it.</p>"
            "<dl><dt>account</dt><dd><code>", LibNum.hexAddr(reach), "</code></dd>",
            dom == bytes32(0)
                ? "<dt>domain</dt><dd class=e>not deployed yet, so it has no domain "
                  "separator to show. It will be fixed the moment it is.</dd>"
                : string.concat("<dt>domain</dt><dd><code>", LibNum.hex32(dom),
                                "</code></dd>"),
            "<dt>check with</dt><dd><code>isValidSignature(bytes32 digest, bytes "
            "signature)</code> &mdash; <code>0x1626ba7e</code> means yes</dd></dl>"
            "<p class=e>Building an attestation takes a struct this page has no room to "
            "compose. The instrument does it properly: open the token, go to Sign, and it "
            "computes the digest locally and compares it against "
            "<code>attestationDigest</code> read from the chain before it asks you to sign "
            "anything.</p>"
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
        for (uint256 i; i < 64; ++i) o[63 - i] = hexd[(v >> (i * 4)) & 0x0f];
        return string(o);
    }
}
