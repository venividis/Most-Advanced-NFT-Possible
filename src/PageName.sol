// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibNum} from "./lib/LibNum.sol";
import {IChrome, IDesk} from "./interfaces/Site.sol";

interface IPlateRead {
    function ENS() external view returns (address);
    function parentNode() external view returns (bytes32);
}

/*───────────────────────────────────────────────────────────────────────────
  PageName — a name, pointed at a token

  The resolver takes every write twice over: once as a namehash, and once as
  DNS wire format. This page uses the second, and the reason is the whole
  shape of this site's client — there is no keccak in the browser. A
  namehash cannot be typed and must not be guessed at; it has to be hashed
  from the name. So the client builds `05 alice 03 eth 00` out of nothing
  but label lengths and bytes, which is string arithmetic a page can do
  honestly, and the chain does the hashing in `nodeOf`. That is why the
  `*ByName` variants exist at all.

  Binding is half of what makes a name work, and the half this page cannot
  do is the louder one: the name's resolver has to be set to the Nameplate
  in the ENS app, which is a write to the registry rather than to us. A
  page that showed a tick after binding and said nothing about the registry
  would be lying by omission, so that sentence is a `p.w` and never folds.

  The parent claim sits at the bottom, in its own card, because it is a
  decision nobody can take back — the slot is written once, by whoever owns
  that name at that moment, and no function in the resolver moves it
  afterwards. Putting it beside the bind button would invite a mis-click
  into permanence.

  Where there is no ENS registry — Base, for one — the page renders the
  explanation and no controls. Buttons that always revert are worse than no
  buttons, because they read as an outage rather than as an absence.
───────────────────────────────────────────────────────────────────────────*/
contract PageName {
    using LibNum for uint256;

    IChrome     public immutable CHROME;
    IDesk       public immutable DESK;
    IPlateRead  public immutable PLATE;
    address     public immutable HUB;

    constructor(IChrome chrome, IDesk desk, address plate, address hub) {
        CHROME = chrome;
        DESK = desk;
        PLATE = IPlateRead(plate);
        HUB = hub;
    }

    /*═══════════════════ /name ═══════════════════*/

    function namePage() external view returns (string memory) {
        return string.concat(
            CHROME.head("IPSEITY \xc2\xb7 name"),
            CHROME.navTop(12),
            "<h1>name</h1>",
            "<p class=e>A name you own, recorded against a token in this "
            "collection&#39;s own ENS resolver. The name goes in as bytes, not as a "
            "hash, so nothing here has to be taken on trust from a browser.</p>",
            _config(),
            _card(),
            "<div id=s></div>",
            CHROME.wallet(),
            DESK.bare(),
            DESK.core(),
            _js(),
            CHROME.foot(msg.sender, block.chainid)
        );
    }

    /*  `here` is the one flag the client reads before it does anything: a
        chain with no registry gets no controls, so the script has nothing
        to bind listeners to and returns instead of throwing on a null.   */
    function _config() private view returns (string memory) {
        address ens = PLATE.ENS();
        bytes32 p = PLATE.parentNode();
        return string.concat(
            "<script type=\"application/json\" id=\"N\">{",
            "\"plate\":\"", LibNum.hexAddr(address(PLATE)),
            "\",\"hub\":\"", LibNum.hexAddr(HUB),
            "\",\"ens\":\"", LibNum.hexAddr(ens),
            "\",\"here\":", ens != address(0) ? "true" : "false",
            ",\"parent\":\"", LibNum.hex32(p),
            "\",\"claimed\":", p != bytes32(0) ? "true" : "false",
            ",\"sel\":{",
            "\"nodeOf\":\"", _sel("nodeOf(bytes)"),
            "\",\"bind\":\"", _sel("bindByName(bytes,uint256)"),
            "\",\"unbind\":\"", _sel("unbindByName(bytes)"),
            "\",\"claimParent\":\"", _sel("claimParentByName(bytes)"),
            "\",\"tokenFor\":\"", _sel("tokenForName(bytes)"),
            "\",\"tokenOf\":\"", _sel("tokenOf(bytes32)"),
            "\",\"addr\":\"", _sel("addr(bytes32)"),
            "\",\"text\":\"", _sel("text(bytes32,string)"),
            "\",\"owner\":\"", _sel("owner(bytes32)"),
            "\",\"account\":\"", _sel("account(uint256)"),
            "\",\"ownerOf\":\"", _sel("ownerOf(uint256)"),
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

    function _card() private view returns (string memory) {
        if (PLATE.ENS() == address(0)) return _absent();
        return string.concat(_terms(), _bind(), _parent());
    }

    /*  A chain with no registry. The resolver is here anyway, at the address
        it holds on every chain, and it still answers the one record that
        needs no binding — which is worth saying, because "not supported
        here" and "returns nothing here" are different claims.            */
    function _absent() private view returns (string memory) {
        return string.concat(
            "<p class=w>There is no ENS registry on chain ", block.chainid.str(),
            ", so there is nothing on this chain to bind against and this page "
            "offers no controls rather than buttons that always revert. The "
            "resolver is deployed regardless, at the address it has everywhere "
            "else, and every bind on it refuses with "
            "<code>NoRegistryHere()</code>.</p>"
            "<p class=e>It still answers reads. "
            "<code>text(node,&quot;contentcontract&quot;)</code> returns this "
            "chain&#39;s premises for any node at all &mdash; the ERC-6821 record "
            "is about where the site is, not about which token a name means, so "
            "it is true before anything is bound.</p>"
        );
    }

    function _terms() private pure returns (string memory) {
        return
            "<p class=w>Binding is half the job. The name&#39;s <em>resolver</em> "
            "must also be pointed at this contract in the ENS app &mdash; that is a "
            "write to the registry, which this page cannot make for you and will "
            "not pretend to. Until it is set, everything below is recorded and "
            "nothing reads it.</p>"
            "<p class=e>What binding buys: the name resolves to the token&#39;s own "
            "account, so ETH sent to the name funds the token; the token&#39;s sigil "
            "becomes the ENS avatar; and <code>text(&quot;contentcontract&quot;)</code> "
            "is the ERC-6821 record that makes a <code>web3://</code> browser resolve "
            "the name straight into this site &mdash; no IPFS, no gateway, no "
            "server.</p>"
            "<p class=e>The name is sent as DNS wire format: each label prefixed by "
            "its length in one byte, a zero byte at the end, so <code>alice.eth</code> "
            "goes in as <code>05 alice 03 eth 00</code>. The chain hashes that into "
            "the node. This page cannot &mdash; it carries no keccak, on purpose "
            "&mdash; and a namehash you could not check is a namehash you should not "
            "sign.</p>";
    }

    function _bind() private pure returns (string memory) {
        return
            "<div class=app>"
            "<div class=hd><b>Bind a name</b></div>"
            "<label>the name</label>"
            "<input id=nnm placeholder=\"alice.eth\">"
            "<div class=det id=nwire></div>"
            "<label>the token</label>"
            "<input id=ntok placeholder=\"a number \xe2\x80\x94 whose account the "
            "name will mean\" inputmode=numeric>"
            "<div class=det id=ntdet></div>"
            "<div class=det id=nnow></div>"
            "<button class=go id=ngo>Connect</button>"
            "<button id=nun>Unbind this name</button>"
            "</div>";
    }

    /*  The wildcard, kept apart. Claimed, it is a fact to read; unclaimed,
        it is the only irreversible button on the page.                   */
    function _parent() private view returns (string memory) {
        bytes32 p = PLATE.parentNode();
        if (p != bytes32(0)) {
            return string.concat(
                "<h2>the wildcard parent</h2>"
                "<p class=e>Claimed, and there is no function that moves it. Every "
                "<code>&lt;id&gt;.that-name</code> resolves to that token by ENSIP-10 "
                "wildcard &mdash; no subdomain registered, nothing bound, and the "
                "name exists the moment the token does.</p>"
                "<dl><dt>parent node</dt><dd><code>", LibNum.hex32(p),
                "</code><span class=m>written once, by whoever owned the name at that "
                "block</span></dd></dl>"
            );
        }
        return
            "<h2>the wildcard parent</h2>"
            "<p class=w>This slot is written once. Whoever owns the name at the "
            "moment of claiming takes it, and nothing in the resolver moves it "
            "afterwards &mdash; not the claimer, not the collection, not anyone. "
            "There is no second attempt.</p>"
            "<p class=e>Claimed, <code>7.yourname.eth</code> resolves to token 7 as "
            "soon as token 7 exists, with no registration and no bind call. Point "
            "the parent&#39;s own resolver here as well, or the wildcard is a record "
            "nothing asks for.</p>"
            "<div class=app>"
            "<div class=hd><b>Claim the parent</b></div>"
            "<label>the parent name</label>"
            "<input id=npn placeholder=\"yourname.eth\">"
            "<div class=det id=npdet></div>"
            "<button class=go id=npgo>Claim it, once</button>"
            "</div>";
    }

    /*═══════════════════ the client ═══════════════════*/

    function _js() private pure returns (string memory) {
        return string.concat("<script>", NAME_JS, "</script>");
    }

    string internal constant NAME_JS =
        "(()=>{const I=window.IP;if(!I)return;const $=I.$;"
        "const E=document.getElementById('N');if(!E)return;"
        "const N=JSON.parse(E.textContent),S=N.sel;"
        /*  No registry, no controls, nothing to bind listeners to. */
        "if(!N.here)return;"

        /*  DNS wire format, which is the reason the *ByName functions exist.
            A label's length as one byte, then the label, then the next, then
            a zero byte: "alice.eth" is 05 61 6c 69 63 65 03 65 74 68 00. No
            hashing, no library, no ABI coder — lengths and character codes,
            which is the most a page with no keccak is entitled to do.

            Unicode names are refused rather than encoded. ENSIP-15
            normalisation is not something to approximate: a name normalised
            wrong hashes to a different node, and the bind lands somewhere
            nobody looked at.                                             */
        "const H=s=>{let o='';for(let i=0;i<s.length;i++)"
        "o+=s.charCodeAt(i).toString(16).padStart(2,'0');return o};"
        "const NR=/^[a-z0-9-]+(\\.[a-z0-9-]+)*$/;"
        "const wire=v=>{const n=String(v||'').trim().toLowerCase()"
        ".replace(/^\\.+|\\.+$/g,'');"
        "if(!n)throw new Error('a name');"
        "if(!NR.test(n))throw new Error('letters, digits and hyphens \\u2014 this "
        "page will not guess at the normalised form of a unicode name');"
        "let h='';for(const l of n.split('.')){"
        "if(l.length>63)throw new Error('a label is 63 bytes at most');"
        "h+=l.length.toString(16).padStart(2,'0')+H(l)}"
        "return h+'00'};"

        /*  A `bytes` tail and a `string` tail are the same three things: the
            length in one word, the data, then zeros out to a whole word. One
            helper, because getting the padding wrong shifts every later
            argument by a word and the call still goes through.           */
        "const T=h=>I.W(h.length/2)+h+'0'.repeat((64-h.length%64)%64);"
        "const B=v=>T(wire(v));"
        /*  text(bytes32,string): head is [node, 0x40], then the key's tail.
            The key never changes, so it is built once.                   */
        "const CC=I.W(64)+T(H('contentcontract'));"
        "const ZA='0x0000000000000000000000000000000000000000';"
        "const A20=r=>'0x'+String(r).slice(26,66);"
        "const nodeFor=async h=>{"
        "const r=await I.tryCall(N.plate,S.nodeOf+I.W(32)+T(h));"
        "return r?String(r).slice(2,66):null};"

        /*  What the name means right now, asked of the resolver rather than
            worked out here. Debounced: every keystroke is otherwise five
            eth_calls, and the answer only matters where typing stops.    */
        "let node=null,t1=null;"
        "const look=async()=>{node=null;"
        "const nw=$('nwire'),nn=$('nnow');nn.innerHTML='';"
        "let h;try{h=wire($('nnm').value)}catch(e){"
        "nw.innerHTML=String($('nnm').value||'').trim()"
        "?'<div><span class=w>'+e.message+'</span><b></b></div>':'';return}"
        "nw.innerHTML='<div><span>wire</span><b><code>0x'+h+'</code></b></div>';"
        "node=await nodeFor(h);"
        "if(!node){nw.innerHTML+='<div><span class=w>no provider to hash it "
        "through</span><b></b></div>';return}"
        "nw.innerHTML+='<div><span>node</span><b><code>0x'+node+'</code></b></div>';"
        "const tf=await I.tryCall(N.plate,S.tokenFor+I.W(32)+T(h));"
        "const bd=await I.tryCall(N.plate,S.tokenOf+node);"
        "const ad=await I.tryCall(N.plate,S.addr+node);"
        "const tx=await I.tryCall(N.plate,S.text+node+CC);"
        "const ow=await I.tryCall(N.ens,S.owner+node);"
        "const t=tf?I.word(tf,0):0n,b=bd?I.word(bd,0):0n;"
        "let o='<div><span>this name means</span><b>'"
        "+(t>0n?'token #'+t:'nothing yet')+'</b></div>';"
        /*  tokenForName answers for wildcards too. A name that resolves
            without being bound is a different fact, and unbind will not
            touch it — so it is said rather than blurred into "bound".   */
        "if(t>0n&&b===0n)o+='<div><span>through the wildcard parent</span>"
        "<b>not a binding \\u2014 unbinding will not change it</b></div>';"
        "if(ad){const a=A20(ad);if(a!==ZA)"
        "o+='<div><span>addr \\u2014 ETH sent to the name lands here</span><b>'"
        "+a+'</b></div>'}"
        "if(tx){const s=I.STR(tx);if(s)"
        "o+='<div><span>contentcontract</span><b>'+s+'</b></div>'}"
        "if(ow){const a=A20(ow);"
        "o+='<div><span>the registry says the name is</span><b>'"
        "+(a===ZA?'unregistered \\u2014 nothing to bind':a)+'</b></div>';"
        "const w=I.acct();"
        "if(w&&a!==ZA&&a.toLowerCase()!==w.toLowerCase())"
        "o+='<div><span class=m>a wrapped name shows the wrapper here, and the "
        "resolver checks the wrapper as well</span><b></b></div>'}"
        "nn.innerHTML=o};"
        "const poke=()=>{clearTimeout(t1);t1=setTimeout(look,260)};"
        "$('nnm').addEventListener('input',poke);"
        "$('nnm').addEventListener('change',poke);"

        /*  Who the bind will actually be refused for, said before the press:
            the resolver takes the holder or the token's own account, and
            nobody else.                                                   */
        "let t2=null;"
        "const tokl=async()=>{const e=$('ntdet');e.innerHTML='';"
        "const t=String($('ntok').value||'').trim();"
        "if(!/^[0-9]+$/.test(t)||t==='0')return;"
        "const a=await I.tryCall(N.hub,S.account+I.W(t));if(!a)return;"
        "const ac=A20(a);"
        "let o='<div><span>the name would resolve to</span><b>'+ac+'</b></div>';"
        "const ov=await I.tryCall(N.hub,S.ownerOf+I.W(t));"
        "if(ov){const ow=A20(ov);"
        "o+='<div><span>token #'+t+' is held by</span><b>'+ow+'</b></div>';"
        "const w=I.acct();"
        "if(w&&ow.toLowerCase()!==w.toLowerCase()&&ac.toLowerCase()!==w.toLowerCase())"
        "o+='<div><span class=w>not yours</span><b>the bind is refused unless you "
        "hold the token or are its account</b></div>'}"
        "e.innerHTML=o};"
        "$('ntok').addEventListener('input',()=>{clearTimeout(t2);t2=setTimeout(tokl,260)});"

        /*  One button, two states, like every card on this site. Token zero
            is refused here rather than on chain: the resolver stores unbound
            as zero, so binding zero is an unbind that looks like a bind.  */
        "let booted=false;"
        "$('ngo').addEventListener('click',async()=>{try{await I.connect();"
        "if(!booted){booted=true;$('ngo').textContent='Bind this name';"
        "await look();await tokl();"
        "I.say('connected \\u00b7 a name and a number','ok');return}"
        "const t=String($('ntok').value||'').trim();"
        "if(!/^[0-9]+$/.test(t)||t==='0')throw new Error('a token number \\u2014 "
        "zero is how the resolver stores unbound');"
        /*  bindByName(bytes,uint256): two head words — the offset to the
            name at 0x40, then the token — and the name's tail after them. */
        "await I.send(N.plate,S.bind+I.W(64)+I.W(t)+B($('nnm').value));"
        "await look()}catch(x){I.say(String(x&&x.message||x),'no')}});"

        /*  One bytes argument: a single offset of 0x20, then the same tail. */
        "$('nun').addEventListener('click',async()=>{try{await I.connect();"
        "await I.send(N.plate,S.unbind+I.W(32)+B($('nnm').value));"
        "await look()}catch(x){I.say(String(x&&x.message||x),'no')}});"

        /*  The claim exists only while the slot is empty; when it is taken
            the page renders a fact instead of a card, and there is no button
            here to wire.                                                  */
        "const pg=$('npgo');"
        "if(pg){let t3=null;"
        "const pl=async()=>{const e=$('npdet');e.innerHTML='';"
        "let h;try{h=wire($('npn').value)}catch(x){"
        "e.innerHTML=String($('npn').value||'').trim()"
        "?'<div><span class=w>'+x.message+'</span><b></b></div>':'';return}"
        "const nd=await nodeFor(h);if(!nd)return;"
        "let o='<div><span>node</span><b><code>0x'+nd+'</code></b></div>';"
        "const ow=await I.tryCall(N.ens,S.owner+nd);"
        "if(ow){const a=A20(ow);"
        "o+='<div><span>the registry says it is</span><b>'"
        "+(a===ZA?'unregistered':a)+'</b></div>'}"
        "o+='<div><span class=w>once</span><b>every number under this name becomes "
        "a token, and the slot never moves again</b></div>';"
        "e.innerHTML=o};"
        "$('npn').addEventListener('input',()=>{clearTimeout(t3);t3=setTimeout(pl,260)});"
        "pg.addEventListener('click',async()=>{try{await I.connect();"
        "await I.send(N.plate,S.claimParent+I.W(32)+B($('npn').value));"
        "I.say('claimed \\u00b7 the slot is written and no function moves it','ok')}"
        "catch(x){I.say(String(x&&x.message||x),'no')}})}"
        "})();";
}
