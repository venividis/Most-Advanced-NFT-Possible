// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibNum} from "./lib/LibNum.sol";
import {Web} from "./lib/Web.sol";
import {Section} from "./lib/Types.sol";
import {IHub, IChrome, IDesk, IParley, ITalkDesk} from "./interfaces/Site.sol";

/*───────────────────────────────────────────────────────────────────────────
  PageDoor — the front of the site, and the way in

  This is the one page whose job is not to tell you something. It is to let
  you in: connect a wallet, and if it holds one of these tokens the page
  hands you that token's instrument, that token's counter, and that token's
  messages, and the composer boxes on every other page stop being decorative.

  ── the honest shape of the gate ──

  Nothing here is hidden from anyone. The conversation below loads before a
  wallet is connected and would load with the wallet uninstalled; every byte
  of it is a log on a public chain and there is no version of this that is
  otherwise. What holding a token actually buys is the right to *write* —
  and that is enforced in `Parley`, in a contract, where enforcement means
  something, rather than in a page, where it would mean a CSS class.

  So the gate on this page is a courtesy: it stops showing you a composer
  you cannot use. It is not a lock, it is never described as one, and a page
  that claimed otherwise would be lying about a chain to the person standing
  on it.
───────────────────────────────────────────────────────────────────────────*/
contract PageDoor {
    using LibNum for uint256;
    using Section for uint256;

    IHub        public immutable HUB;
    IChrome     public immutable CHROME;
    IDesk       public immutable DESK;
    ITalkDesk   public immutable TALK;
    IParley     public immutable PARLEY;

    constructor(IHub hub, IChrome chrome, IDesk desk, ITalkDesk talk, IParley parley) {
        HUB = hub;
        CHROME = chrome;
        DESK = desk;
        TALK = talk;
        PARLEY = parley;
    }

    function door() external view returns (string memory) {
        uint256 supply = HUB.totalSupply();
        (, uint64 said,,,,,,,) = PARLEY.stateOf(0);

        return string.concat(
            CHROME.head("IPSEITY"),
            CHROME.navTop(0),
            "<h1>IPSEITY</h1>"
            "<p class=e>ipseity, n. &mdash; the property of being oneself; selfhood as "
            "distinct from any of its appearances.</p>"
            "<p>A four-dimensional solid, and the instrument for turning it, are the same "
            "token. What a holder sees is a three-dimensional section of a 4-polytope: the "
            "solid is never on screen, only the 3-space that currently cuts through it.</p>"
            "<p>Every token returns its own control surface from <code>tokenURI</code> "
            "&mdash; a WebGL2 engine, a keccak-256, an ABI coder and a wallet client, held "
            "in this chain's state as contract bytecode. Nothing is fetched, including by "
            "this page. This site is the door to it: connect below and whatever you hold "
            "opens.</p>",
            DESK.bare(),
            TALK.config(0, 0, 0),
            _enter(),
            _talk(said),
            _facts(supply),
            _roll(supply),
            "<div id=s></div>",
            DESK.core(),
            TALK.core(),
            TALK.door(),
            CHROME.foot(msg.sender, block.chainid)
        );
    }

    /*═══════════════════ the way in ═══════════════════*/

    function _enter() private pure returns (string memory) {
        return
            "<h2>what you hold</h2>"
            "<div class=gate>"
            "<h3>Connect</h3>"
            "<p class=e>This page reads <code>balanceOf</code> and then walks "
            "<code>tokenOfOwnerByIndex</code>, so it learns which tokens are yours from "
            "the collection rather than from a list somebody keeps. Nothing is sent "
            "anywhere; the only thing that leaves your browser is an <code>eth_call</code> "
            "to your own node.</p>"
            "<button id=go>connect</button>"
            "</div>"
            "<div id=yours></div>"
            "<div id=rig></div>"
            "<p class=e>Opening the instrument here costs your node a 21M gas "
            "<code>eth_call</code> &mdash; the whole document comes back in one read. It "
            "happens when you ask for it and never on arrival.</p>";
    }

    /*═══════════════════ the commons, already running ═══════════════════*/

    function _talk(uint64 said) private view returns (string memory) {
        return string.concat(
            "<h2>the tokens are talking to each other</h2>"
            "<p>Every token in this collection is in one room together, can found groups, "
            "and can write to any other token one to one. A message is a log, the log is "
            "the archive, and the archive is wherever this chain is. There is no server "
            "to switch off and nothing to keep.</p>"
            "<p class=e><b>", uint256(said).str(), "</b> messages in the commons \xc2\xb7 <b>",
            PARLEY.groups().str(), "</b> groups founded. What is below is the commons "
            "itself, loading from the chain right now.</p>"
            "<div id=log></div>"
            "<p><a class=g href=\"/chat\">say something &rarr;</a>"
            "<a class=g href=\"/rooms\">the groups &rarr;</a></p>"
        );
    }

    /*═══════════════════ what else a token does ═══════════════════*/

    function _facts(uint256 supply) private view returns (string memory) {
        return string.concat(
            "<h2>each one is also a business</h2>"
            "<p>A token here is not only something to look at and not only somewhere to "
            "talk. It runs an exchange, holds a vault that cannot be emptied, rents "
            "itself out by the day, and draws any four-dimensional form you hand it. "
            "Those are open to anybody &mdash; you do not have to own one to use one, "
            "and what you pay goes to the token.</p>"
            "<table><tr><th>service</th><th>what a stranger may do</th><th>who is paid</th></tr>"
            "<tr><td>speak</td><td>read every room; write to any of them as a token you "
            "hold</td><td>nobody &mdash; it is gas and nothing else</td></tr>"
            "<tr><td>trade</td><td>swap against the token's own two-asset market</td>"
            "<td>the token, as a fee</td></tr>"
            "<tr><td>rent</td><td>operate the instrument by the day &mdash; turn the solid, "
            "commit orientations &mdash; but never sell it</td><td>the token, as rent</td></tr>"
            "<tr><td>give</td><td>pay into a vault with no spend function in its bytecode</td>"
            "<td>the token, permanently</td></tr>"
            "<tr><td>draw</td><td>call the on-chain 4D projector with any word and any seed"
            "</td><td>nobody &mdash; it is free</td></tr>"
            "<tr><td>verify</td><td>check a signature the token made as itself</td>"
            "<td>nobody &mdash; it is free</td></tr></table>"
            "<dl><dt>issued</dt><dd>", supply.str(), " of ", HUB.MAX_SUPPLY().str(), "</dd>"
            "<dt>mint price</dt><dd>", Web.amount(HUB.price(), 18, 4), " ETH</dd>"
            "<dt>collection</dt><dd><code>", LibNum.hexAddr(address(HUB)), "</code></dd>"
            "<dt>parley</dt><dd><code>", LibNum.hexAddr(address(PARLEY)), "</code></dd></dl>"
            "<p><a class=g href=\"/open\">which tokens are open for business &rarr;</a>"
            "<a class=g href=\"/services.json\">the same thing, for a program &rarr;</a></p>"
        );
    }

    function _roll(uint256 supply) private view returns (string memory out) {
        if (supply == 0) return "<p class=e>None issued yet.</p>";
        uint256 from = supply > 12 ? supply - 11 : 1;
        out = "<h2>most recent</h2><ul class=r>";
        for (uint256 id = supply; id >= from; --id) {
            out = string.concat(
                out,
                "<li><a href=\"/token/", id.str(), "\">#", id.str(), "</a> ",
                "<span class=m>", _form(HUB.sectionOf(id).form()), "</span> ",
                "<a class=b href=\"/dm/", id.str(), "\">message</a></li>"
            );
            if (id == 1) break;
        }
        return string.concat(out, "</ul>");
    }

    function _form(uint8 f) private pure returns (string memory) {
        if (f == 0) return "Tesseract";
        if (f == 1) return "Hexadecachoron";
        if (f == 2) return "Icositetrachoron";
        if (f == 3) return "Duocylinder";
        if (f == 4) return "Clifford torus";
        if (f == 5) return "Tiger";
        if (f == 6) return "Ditorus";
        return "Quaternion Julia";
    }
}
