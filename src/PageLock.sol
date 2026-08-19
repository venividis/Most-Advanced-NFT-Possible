// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibNum} from "./lib/LibNum.sol";
import {IChrome, IDesk} from "./interfaces/Site.sol";

interface ILockerRead {
    function MAX_TERM() external view returns (uint64);
    function count() external view returns (uint256);
    function totalLocked(address token) external view returns (uint256);
}

/*───────────────────────────────────────────────────────────────────────────
  PageLock — ten years on a slider

  The vault's whole interface is one bar. Drag it and the page says the date
  out loud, because "730 days" reads like a number and "August 2028" reads
  like a commitment — and a commitment is the product being sold here.

  Everything under the bar is the usual shape: paste a token, type an
  amount, press once to approve and once to lock. The list below it is
  yours — read from the vault with `eth_call` after you connect, claimable
  the second the clock agrees, and not one second before, because the
  contract has no function that ends a lock early and this page could not
  offer one if it wanted to.
───────────────────────────────────────────────────────────────────────────*/
contract PageLock {
    using LibNum for uint256;

    IChrome     public immutable CHROME;
    IDesk       public immutable DESK;
    ILockerRead public immutable LOCKER;

    constructor(IChrome chrome, IDesk desk, ILockerRead locker) {
        CHROME = chrome;
        DESK = desk;
        LOCKER = locker;
    }

    /*═══════════════════ /lock ═══════════════════*/

    function lockPage() external view returns (string memory) {
        return string.concat(
            CHROME.head("IPSEITY \xc2\xb7 lock"),
            CHROME.navTop(18),
            _config(),
            _card(),
            _mine(),
            _how(),
            CHROME.wallet(),
            DESK.bare(),
            DESK.core(),
            _js(),
            CHROME.foot(msg.sender, block.chainid)
        );
    }

    function _config() private view returns (string memory) {
        return string.concat(
            "<script type=\"application/json\" id=\"V\">{",
            "\"locker\":\"", LibNum.hexAddr(address(LOCKER)),
            "\",\"maxDays\":", (uint256(LOCKER.MAX_TERM()) / 1 days).str(),
            ",\"sel\":{",
            "\"lock\":\"", _sel("lock(address,uint256,uint64)"),
            "\",\"claim\":\"", _sel("claim(uint256)"),
            "\",\"extend\":\"", _sel("extend(uint256,uint64)"),
            "\",\"of\":\"", _sel("locksOf(address)"),
            "\",\"lockAt\":\"", _sel("lockAt(uint256)"),
            "\",\"totalLocked\":\"", _sel("totalLocked(address)"),
            "\",\"approve\":\"", _sel("approve(address,uint256)"),
            "\",\"allowance\":\"", _sel("allowance(address,address)"),
            "\",\"balanceOf\":\"", _sel("balanceOf(address)"),
            "\",\"symbol\":\"", _sel("symbol()"),
            "\",\"decimals\":\"", _sel("decimals()"),
            "\"}}</script>"
        );
    }

    function _sel(string memory sig) private pure returns (string memory) {
        bytes4 x = bytes4(keccak256(bytes(sig)));
        bytes memory hexd = "0123456789abcdef";
        bytes memory o = new bytes(10);
        o[0] = "0"; o[1] = "x";
        for (uint256 i; i < 4; ++i) {
            o[2 + i * 2] = hexd[uint8(x[i]) >> 4];
            o[3 + i * 2] = hexd[uint8(x[i]) & 0x0f];
        }
        return string(o);
    }

    /*═══════════════════ the card ═══════════════════*/

    function _card() private pure returns (string memory) {
        return
            "<h1>lock</h1>"
            "<p class=e>Tokens in, a date on a bar, and nothing &mdash; not you, not "
            "this site, not anyone &mdash; gets them out before the date. The vault "
            "has no owner, no pause and no rescue path, because a rescue path is an "
            "unlock with a nicer name.</p>"
            "<div class=app>"
            "<div class=hd><b>Lock tokens</b></div>"
            "<label>token</label><input id=lt placeholder=\"0x\xe2\x80\xa6 any ERC-20\">"
            "<div class=det id=ltok></div>"
            "<div class=row><label style=\"flex:1\">amount</label>"
            "<span id=lbal class=m></span></div>"
            "<div class=row><input id=la placeholder=\"0.0\" inputmode=decimal>"
            "<button class=mx id=lmx>MAX</button></div>"
            "<label>for how long <b id=ldl>365 days</b> &mdash; "
            "<b id=ldd></b> <span class=m>drag it; ten years is the far end</span></label>"
            "<input type=range id=ldR min=1 max=3650 value=365>"
            "<div class=row><input id=ld value=\"365\" inputmode=numeric "
            "style=\"max-width:8rem\"><span class=m>days, if you'd rather type</span></div>"
            "<div class=det id=lsum></div>"
            "<button class=go id=lgo>Connect</button>"
            "<div id=s></div></div>";
    }

    function _mine() private pure returns (string memory) {
        return
            "<h2>your locks</h2>"
            "<p class=e id=lnone>Connect, and what you have locked appears here.</p>"
            "<div id=llist></div>";
    }

    function _how() private view returns (string memory) {
        return string.concat(
            "<h2>what the vault records</h2>"
            "<p class=e>The amount written into a lock is the amount that actually "
            "arrived, measured &mdash; a fee-on-transfer token that skims on the way "
            "in is recorded at what landed, so what comes out is what went in. "
            "Rebasing tokens are not accounted for: a token whose balances drift "
            "will drift here too, and a vault that pretended otherwise would be "
            "lying about somebody else's contract.</p>"
            "<p class=e>A lock can be <em>extended</em> and never shortened. The "
            "ceiling is ten years per extension, counted from the moment you press "
            "&mdash; a lock with no end is a burn wearing a vault's clothing.</p>"
            "<dl><dt>the vault</dt><dd><code>", LibNum.hexAddr(address(LOCKER)),
            "</code><span class=m>this collection's own contract; every claim in the "
            "two paragraphs above is checkable in its source</span></dd></dl>"
        );
    }

    /*═══════════════════ the client ═══════════════════*/

    function _js() private pure returns (string memory) {
        return string.concat("<script>", LOCK_JS, "</script>");
    }

    string internal constant LOCK_JS =
        "(()=>{const I=window.IP;if(!I)return;const $=I.$;"
        "const E=document.getElementById('V');if(!E)return;"
        "const V=JSON.parse(E.textContent),S=V.sel;"
        "let tok=null;"

        /*  The bar and the box agree, and the date is said out loud. */
        "const DAY=86400;"
        "const show=()=>{const d=Number($('ld').value)||0;"
        "$('ldl').textContent=d+(d===1?' day':' days');"
        "const t=new Date(Date.now()+d*DAY*1000);"
        "$('ldd').textContent='until '+t.toISOString().slice(0,10);"
        "sum()};"
        "$('ldR').addEventListener('input',()=>{$('ld').value=$('ldR').value;show()});"
        "$('ld').addEventListener('input',()=>{const v=Number($('ld').value);"
        "if(v>=1&&v<=V.maxDays)$('ldR').value=v;show()});"

        /*  The token, asked what it is. */
        "const ask=async()=>{const a=String($('lt').value||'').trim().toLowerCase();"
        "if(!/^0x[0-9a-f]{40}$/.test(a)){tok=null;$('ltok').innerHTML='';return}"
        "const sy=await I.tryCall(a,S.symbol),de=await I.tryCall(a,S.decimals);"
        "if(!de){tok=null;"
        "$('ltok').innerHTML='<div><span class=w>that address does not answer like "
        "an ERC-20</span><b></b></div>';return}"
        "const d=Number(I.word(de,0));"
        "tok={a:a,d:d,s:I.TK(sy?I.STR(sy):'',a)};"
        "const tl=await I.tryCall(V.locker,S.totalLocked+I.AD(a));"
        "$('ltok').innerHTML='<div><span>token</span><b>'+tok.s+'</b></div>'"
        "+(tl&&I.word(tl,0)>0n?'<div><span>already locked here</span><b>'"
        "+I.fmt(I.word(tl,0),d,4)+' '+tok.s+'</b></div>':'');"
        "bal();sum()};"
        "$('lt').addEventListener('change',ask);$('lt').addEventListener('input',ask);"

        "const bal=async()=>{const w=I.acct();if(!w||!tok)return;"
        "const b=await I.tryCall(tok.a,S.balanceOf+I.AD(w));"
        "if(b)$('lbal').textContent='you hold '+I.fmt(I.word(b,0),tok.d,4)};"
        "$('lmx').addEventListener('click',async()=>{const w=I.acct();"
        "if(!w||!tok)return;const b=await I.tryCall(tok.a,S.balanceOf+I.AD(w));"
        "if(b)$('la').value=I.fmt(I.word(b,0),tok.d,tok.d).replace(/,/g,'');sum()});"

        "const sum=()=>{const e=$('lsum');if(!e)return;"
        "if(!tok){e.innerHTML='';return}"
        "const d=Number($('ld').value)||0;"
        "e.innerHTML='<div><span>locks</span><b>'+($('la').value||'0')+' '+tok.s"
        "+'</b></div><div><span>until</span><b>'+$('ldd').textContent.slice(6)"
        "+' \\u00b7 no early exit exists</b></div>'};"
        "$('la').addEventListener('input',sum);"

        /*  One button, three states: connect, approve, lock. The allowance
            is read fresh on every press, so the button never guesses.    */
        "let booted=false;"
        "const step=async()=>{if(!booted){booted=true;list();bal();"
        "if(!tok){$('lgo').textContent='Approve';"
        "I.say('connected \u00b7 paste a token','ok');return}}"
        "if(!tok)throw new Error('paste the token first');"
        "const amt=I.parse($('la').value,tok.d);"
        "if(amt<=0n)throw new Error('an amount');"
        "const w=I.acct();"
        "const al=await I.tryCall(tok.a,S.allowance+I.AD(w)+I.AD(V.locker));"
        "if(!al||I.word(al,0)<amt){"
        "await I.send(tok.a,S.approve+I.AD(V.locker)+I.W(amt));"
        "$('lgo').textContent='Lock it';return}"
        "const d=Number($('ld').value);"
        "if(!(d>=1&&d<=V.maxDays))throw new Error('one day to ten years');"
        "const until=BigInt(Math.floor(Date.now()/1000)+d*DAY);"
        "await I.send(V.locker,S.lock+I.AD(tok.a)+I.W(amt)+I.W(until));"
        "$('lgo').textContent='Locked';await list()};"
        "$('lgo').addEventListener('click',async()=>{try{await I.connect();"
        "await step()}catch(x){I.say(String(x&&x.message||x),'no')}});"

        /*  The list: this wallet's locks, straight off the vault. */
        "const list=async()=>{const w=I.acct();if(!w)return;"
        "const r=await I.tryCall(V.locker,S.of+I.AD(w));if(!r)return;"
        "const n=Number(I.word(r,1));"
        "$('lnone').style.display=n?'none':'';"
        "let h='';"
        "for(let i=0;i<n&&i<50;i++){const id=I.word(r,2+i);"
        "const L=await I.tryCall(V.locker,S.lockAt+I.W(id));if(!L)continue;"
        "const ta='0x'+String(L).slice(26,66);"
        "const amt=I.word(L,2),until=Number(I.word(L,3)),taken=I.word(L,4)===1n;"
        "const de=await I.tryCall(ta,S.decimals);const d=de?Number(I.word(de,0)):18;"
        "const sy=await I.tryCall(ta,S.symbol);"
        "const s=I.TK(sy?I.STR(sy):'',ta);"
        "const now=Date.now()/1000;"
        "const st=taken?'claimed':now>=until?'<b class=ok>claimable</b>'"
        ":Math.ceil((until-now)/DAY)+' days left';"
        "h+='<div class=det><div><span>#'+id+' \\u00b7 '+I.fmt(amt,d,4)+' '+s"
        "+'</span><b>'+st+'</b></div>'"
        "+(!taken&&now>=until?'<button class=go data-id=\\''+id"
        "+'\\' style=\\'margin-top:.4rem\\'>Claim</button>':'')+'</div>'}"
        "$('llist').innerHTML=h;"
        "$('llist').querySelectorAll('button').forEach(b=>"
        "b.addEventListener('click',async()=>{try{"
        "await I.send(V.locker,S.claim+I.W(BigInt(b.dataset.id)));"
        "await list()}catch(x){I.say(String(x&&x.message||x),'no')}}))};"

        "show();"
        "})();";
}
