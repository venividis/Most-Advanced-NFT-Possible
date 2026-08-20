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
interface IRoomsDesk { function core() external pure returns (string memory); }

interface ITermDesk {
    function config() external view returns (string memory);
    function core() external pure returns (string memory);
}

contract PageDoor {
    using LibNum for uint256;
    using Section for uint256;

    IHub        public immutable HUB;
    IChrome     public immutable CHROME;
    IDesk       public immutable DESK;
    ITalkDesk   public immutable TALK;
    IParley     public immutable PARLEY;
    ITermDesk   public immutable TERM;
    IRoomsDesk  public immutable ROOMS;
    IRoomsDesk  public immutable WILL;

    constructor(IHub hub, IChrome chrome, IDesk desk, ITalkDesk talk,
                IParley parley, ITermDesk term, IRoomsDesk rooms,
                IRoomsDesk will_) {
        HUB = hub;
        CHROME = chrome;
        DESK = desk;
        TALK = talk;
        PARLEY = parley;
        TERM = term;
        ROOMS = rooms;
        WILL = will_;
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
            /*  The solid itself is the first interface: a 4-polytope turned
                slowly through two of its planes, its inner-cube vertices
                the eight doors of this site. Hover names one; entering it
                is a click. The page below remains for hands that prefer a
                list, and for JavaScript that is switched off.            */
            "<div class=tess4><canvas id=tess width=560 height=560></canvas>"
            "<p id=tessl>&nbsp;</p></div>",
            _tess(),
            "<p class=e>A four-dimensional solid, and the instrument for turning it, are the same "
            "token. What a holder sees is a three-dimensional section of a 4-polytope: the "
            "solid is never on screen, only the 3-space that currently cuts through it.</p>"
            "<p class=e>Every token returns its own control surface from <code>tokenURI</code> "
            "&mdash; a WebGL2 engine, a keccak-256, an ABI coder and a wallet client, held "
            "in this chain's state as contract bytecode. Nothing is fetched, including by "
            "this page. This site is the door to it: connect below and whatever you hold "
            "opens.</p>",
            DESK.bare(),
            TALK.config(0, 0, 0),
            /*  The voice: the same terminal an agent drives, on the door
                itself. `help` lists every word; `go <door>` walks.       */
            "<h2>speak</h2>"
            "<div id=tout class=\"term tdoor\" aria-live=polite></div>"
            "<input id=tin class=tinput autocomplete=off spellcheck=false "
            "placeholder=\"help \xc2\xb7 go swap \xc2\xb7 mint \xc2\xb7 say \xe2\x80\xa6\" "
            "aria-label=\"terminal input\">",
            TERM.config(),
            _enter(),
            _talk(said),
            _chains(),
            _facts(supply),
            _roll(supply),
            "<div id=s></div>",
            CHROME.wallet(),
            DESK.core(),
            TERM.core(),
            ROOMS.core(),
            WILL.core(),
            TALK.core(),
            TALK.door(),
            CHROME.foot(msg.sender, block.chainid)
        );
    }

    /*═══════════════════ the way in ═══════════════════*/

    /// @dev The tesseract: sixteen vertices of (±1,±1,±1,±1), turned in the
    ///      xw and yz planes, projected 4→3 by the w-light and 3→2 by the
    ///      z-light. The eight inner-cube vertices are this site's doors;
    ///      the geometry is the navigation. `window.TESS` carries the same
    ///      door list as data, so an agent — or a page with no canvas —
    ///      walks the identical set.
    function _tess() private pure returns (string memory) {
        return string.concat("<script>", TESS_JS, "</script>");
    }

    string internal constant TESS_JS =
        "(()=>{"
        "const D=[['terminal','/terminal'],['swap','/swap'],['launch','/launch'],"
        "['lock','/lock'],['social','/chat'],['market','/gallery'],"
        "['archive','/open'],['manifest','/services.json']];"
        "window.TESS={doors:D.map(d=>d[0]),go:i=>{const d=D[i];"
        "if(d)location.href=d[1];return d?d[1]:null}};"
        "const cv=document.getElementById('tess');"
        "if(!cv||!cv.getContext)return;"
        "const cx=cv.getContext('2d');if(!cx)return;"
        /*  vertices: index bit3 is w. The w=-1 cube (indices 0-7) carries
            the doors, and keeps them whichever cube the turn brings near. */
        "const V=[];for(let i=0;i<16;i++)"
        "V.push([i&1?1:-1,i&2?1:-1,i&4?1:-1,i&8?1:-1]);"
        "const E=[];for(let a=0;a<16;a++)for(let b=a+1;b<16;b++){"
        "let d=a^b;if(d&&!(d&(d-1)))E.push([a,b])}"
        "const W=560,C=W/2;let t=0,mx=-1,my=-1,hot=-1;"
        "const P=new Array(16);"
        "const lbl=document.getElementById('tessl');"
        "const frame=()=>{"
        "t+=.0038;"
        "const c1=Math.cos(t),s1=Math.sin(t),c2=Math.cos(t*.62),s2=Math.sin(t*.62);"
        "cx.clearRect(0,0,W,W);"
        "for(let i=0;i<16;i++){const v=V[i];"
        "let x=v[0]*c1-v[3]*s1,w=v[0]*s1+v[3]*c1;"
        "let y=v[1]*c2-v[2]*s2,z=v[1]*s2+v[2]*c2;"
        "const k4=2.6/(3.2-w);x*=k4;y*=k4;z*=k4;"
        "const k3=2.1/(3.6-z);"
        "P[i]=[C+x*k3*C*.62,C+y*k3*C*.62,k3]}"
        "hot=-1;"
        "if(mx>=0)for(let i=0;i<8;i++){const p=P[i];"
        "const dx=p[0]-mx,dy=p[1]-my;if(dx*dx+dy*dy<340){hot=i;break}}"
        "cx.lineWidth=1;"
        "for(const e of E){const p=P[e[0]],q=P[e[1]];"
        "const g=(p[2]+q[2])*.5;"
        "cx.strokeStyle='rgba(224,193,132,'+(.10+g*.16).toFixed(3)+')';"
        "cx.beginPath();cx.moveTo(p[0],p[1]);cx.lineTo(q[0],q[1]);cx.stroke()}"
        "for(let i=0;i<16;i++){const p=P[i];const door=i<8;"
        "const r=door?(i===hot?7:4.4):2;"
        "cx.beginPath();cx.arc(p[0],p[1],r,0,6.2832);"
        "cx.shadowColor='rgba(244,221,166,.9)';cx.shadowBlur=door?(i===hot?26:12):5;"
        "cx.fillStyle=door?(i===hot?'#fff4d8':'#e8cd8f'):'rgba(224,193,132,.5)';"
        "cx.fill();cx.shadowBlur=0;"
        "if(door&&i===hot){cx.font='11px ui-sans-serif,system-ui';"
        "cx.fillStyle='#f4dda6';cx.textAlign='center';"
        "cx.fillText(D[i][0].toUpperCase(),p[0],p[1]-14)}}"
        "if(lbl)lbl.textContent=hot>=0?D[hot][0]:'\u00a0';"
        "cv.style.cursor=hot>=0?'pointer':'crosshair';"
        "(window.requestAnimationFrame||(f=>setTimeout(f,40)))(frame)};"
        "const at=e=>{const b=cv.getBoundingClientRect();"
        "const k=W/b.width;mx=(e.clientX-b.left)*k;my=(e.clientY-b.top)*k};"
        "cv.addEventListener('mousemove',at);"
        "cv.addEventListener('mouseleave',()=>{mx=my=-1});"
        "cv.addEventListener('click',e=>{at(e);"
        "if(hot>=0)window.TESS.go(hot)});"
        "frame()})();";

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

    /*═══════════════════ the chains ═══════════════════*/

    /// @dev Multichain, honestly: this same contract deploys at the same
    ///      address on every chain the deployer's nonce sequence visits,
    ///      each serving its own chain's assets and its own conversation.
    ///      Nothing crosses. Moving value between chains is a bridge's job
    ///      and deliberately outside this site — a page that quietly wrapped
    ///      one would be a custodian pretending to be a hyperlink. The
    ///      buttons switch the WALLET (EIP-3326, adding the chain first if
    ///      it is missing, EIP-3085); the site you are reading stays put.
    function _chains() private view returns (string memory) {
        return string.concat(
            "<h2>chains</h2>"
            "<p class=e>This page is chain <b>", block.chainid == 1 ? "Ethereum" :
                block.chainid == 8453 ? "Base" :
                block.chainid == 84532 ? "Base Sepolia" :
                block.chainid == 11155111 ? "Ethereum Sepolia" : "another chain",
            "</b>. The same site deploys per chain; each trades its own chain's "
            "assets and holds its own conversation. These buttons move your "
            "<i>wallet</i>; moving <i>value</i> between chains is a bridge's job, "
            "and this site will never quietly be one.</p>"
            "<p>"
            "<button class=ch2 data-id=\"0x1\" data-n=\"Ethereum\" "
            "data-r=\"https://ethereum-rpc.publicnode.com\" data-s=\"ETH\">Ethereum</button>"
            "<button class=ch2 data-id=\"0x2105\" data-n=\"Base\" "
            "data-r=\"https://mainnet.base.org\" data-s=\"ETH\">Base</button>"
            "<button class=ch2 data-id=\"0x14a34\" data-n=\"Base Sepolia\" "
            "data-r=\"https://sepolia.base.org\" data-s=\"ETH\">Base Sepolia</button>"
            "<button class=ch2 data-id=\"0xaa36a7\" data-n=\"Sepolia\" "
            "data-r=\"https://ethereum-sepolia-rpc.publicnode.com\" data-s=\"ETH\">Sepolia</button>"
            "</p>"
            "<script>(()=>{const I=window.IP;"
            "document.querySelectorAll('.ch2').forEach(b=>b.addEventListener('click',async()=>{"
            "try{const p=I.pv();if(!p)throw new Error('no wallet found');"
            "try{await p.request({method:'wallet_switchEthereumChain',"
            "params:[{chainId:b.dataset.id}]})}"
            "catch(e){if(e&&(e.code===4902||/unrecognized|not added/i.test(String(e.message)))){"
            "await p.request({method:'wallet_addEthereumChain',params:[{chainId:b.dataset.id,"
            "chainName:b.dataset.n,rpcUrls:[b.dataset.r],"
            "nativeCurrency:{name:b.dataset.s,symbol:b.dataset.s,decimals:18}}]})}else throw e}"
            "I.say('wallet is on '+b.dataset.n+' \\u2014 open that chain\\u2019s site to act there','ok')}"
            "catch(e){I.say(String(e&&e.message||e),'no')}}))})()</script>"
        );
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
