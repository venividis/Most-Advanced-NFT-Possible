// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibNum} from "./lib/LibNum.sol";
import {Web} from "./lib/Web.sol";
import {IChrome, IDesk, ITalkDesk} from "./interfaces/Site.sol";

interface IAgoraRead {
    function count() external view returns (uint256);
    function proposalAt(uint256 id)
        external view
        returns (uint256 by, uint64 opened, uint64 closes, uint32 yes, uint32 no,
                 bool open, string memory title, string memory body_);
}

/*───────────────────────────────────────────────────────────────────────────
  PageAgora — the tokens decide things out loud

  The proposals and their tallies render on the server, so the record reads
  with scripting off. Voting is the page's one write, and proposing lives in
  the terminal — `propose 7 Title :: Body` — because a governance page that
  is also a text editor is two pages sharing one URL badly.
───────────────────────────────────────────────────────────────────────────*/
contract PageAgora {
    using LibNum for uint256;

    IChrome    public immutable CHROME;
    IDesk      public immutable DESK;
    ITalkDesk  public immutable TALK;
    IAgoraRead public immutable AGORA;

    constructor(IChrome chrome, IDesk desk, ITalkDesk talk, IAgoraRead agora) {
        CHROME = chrome; DESK = desk; TALK = talk; AGORA = agora;
    }

    function agora() external view returns (string memory) {
        uint256 n = AGORA.count();
        return string.concat(
            CHROME.head("IPSEITY \xc2\xb7 agora"),
            CHROME.navTop(21),
            "<h1>agora</h1>"
            "<p class=e><b>", n.str(), "</b> proposal(s). One token, one voice, cast "
            "before the close and never changed after. <b>Nothing executes</b> &mdash; "
            "this contract holds no treasury and calls nothing; what a passed proposal "
            "does is what the holders then do. Propose from the "
            "<a href=\"/terminal\">terminal</a>: <code>propose &lt;days&gt; Title :: "
            "Body</code>.</p>",
            DESK.bare(),
            TALK.config(0, 0, 0),
            _board(n),
            "<div id=s></div>",
            CHROME.wallet(),
            DESK.core(),
            TALK.core(),
            _voteJs(),
            CHROME.foot(msg.sender, block.chainid)
        );
    }

    function _board(uint256 n) private view returns (string memory out) {
        if (n == 0) return "<p class=e>Nothing proposed yet.</p>";
        uint256 from = n > 12 ? n - 12 : 0;
        for (uint256 i = n; i > from; --i) out = string.concat(out, _one(i - 1));
    }

    function _one(uint256 id) private view returns (string memory) {
        (uint256 by,, uint64 closes, uint32 yes, uint32 no, bool open,
         string memory title, string memory body_) = AGORA.proposalAt(id);
        return string.concat(
            "<div class=card><h3>#", id.str(), " \xc2\xb7 ", Web.esc(title), "</h3>",
            "<p class=e>by <a href=\"/token/", by.str(), "\">token #", by.str(),
            "</a> \xc2\xb7 closes at ", uint256(closes).str(), " \xc2\xb7 ",
            open ? "<span class=ok>open</span>" : "<span class=mut>closed</span>",
            "</p><p>", Web.esc(body_), "</p>",
            "<p class=e>yes <b>", uint256(yes).str(), "</b> \xc2\xb7 no <b>",
            uint256(no).str(), "</b></p>",
            open ? string.concat(
                "<div class=only><button class=vy data-id=\"", id.str(),
                "\">vote yes</button><button class=vn data-id=\"", id.str(),
                "\">vote no</button></div>") : "",
            "</div>"
        );
    }

    /// @dev One selector, derived here like every other selector on the
    ///      site, and one handler that reads which token is speaking from
    ///      the same client the chat uses.
    function _voteJs() private view returns (string memory) {
        bytes32 h = keccak256("vote(uint256,uint256,bool)");
        bytes memory sel_ = new bytes(8);
        bytes16 hx = "0123456789abcdef";
        for (uint256 i; i < 4; ++i) {
            sel_[i * 2] = hx[uint8(h[i]) >> 4];
            sel_[i * 2 + 1] = hx[uint8(h[i]) & 15];
        }
        return string.concat(
            "<script>(()=>{const I=window.IP,K=window.IPT;if(!K)return;"
            "const AG=\"", LibNum.hexAddr(address(AGORA)), "\";"
            "const cast=async(id,y)=>{try{"
            "const me=K.me();if(me==null)throw new Error('connect a wallet holding a token');"
            "await I.send(AG,'0x", string(sel_), "'+I.W(me)+I.W(id)+I.W(y?1:0));"
            "I.say('voted \\u00b7 the tally moves when the block lands','ok')}"
            "catch(e){I.say(String(e&&e.message||e),'no')}};"
            "document.querySelectorAll('.vy').forEach(b=>b.addEventListener('click',()=>cast(b.dataset.id,1)));"
            "document.querySelectorAll('.vn').forEach(b=>b.addEventListener('click',()=>cast(b.dataset.id,0)));"
            "})()</script>"
        );
    }
}
