// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*───────────────────────────────────────────────────────────────────────────
  DeskSeal — the client half of a promise Parley already made

  Parley has carried a `kind` byte and a per-token P-256 point since the
  day it was written, and the chat client has always rendered a body it
  cannot read as "sealed" rather than as text. This script is the missing
  half: the key derivation, the handshake, and the cipher — all of it
  WebCrypto, which every browser ships, because a page that carries its
  own curve arithmetic is a page whose curve arithmetic you now have to
  audit.

  ── how the key exists without being stored ──

  The private key is the hash of a wallet signature over a fixed sentence
  naming the chain and the token. Signatures from a given key over a given
  message are deterministic (RFC 6979), so the same wallet derives the
  same key in every browser forever, and there is nothing to back up and
  nothing to lose. The public point is recovered by handing WebCrypto the
  scalar in a PKCS#8 envelope with the public half omitted — the browser
  computes the point itself on import, which is the one way to get curve
  arithmetic without shipping any.

  ── what the cipher is ──

  Static-static ECDH between the two tokens' published points, the shared
  secret hashed once into an AES-256-GCM key. One key per pair, both
  directions — which is exactly what "derived, not stored" buys, and what
  it costs: there is no forward secrecy, and the page does not pretend
  otherwise. A rotated key orphans the old ciphertext; a key that differs
  from the one you remember is either a new wallet or somebody in the
  middle, and only the humans can tell which.
───────────────────────────────────────────────────────────────────────────*/
contract DeskSeal {
    function core() external pure returns (string memory) {
        return string.concat("<script>", SEAL_JS, "</script>");
    }

    string internal constant SEAL_JS =
        "(async()=>{const I=window.IP,PL=window.PARL;if(!I||!PL)return;"
        "const S=PL.S,P=PL.P,T=PL.T;"
        "if(!T||T.other==='0'||!S.announce)return;"
        "const OTHER=BigInt(T.other);"
        "const sub=(crypto&&crypto.subtle)||null;if(!sub)return;"

        /*  The order of P-256, for rejecting a hash that is not a scalar.
            The loop below re-hashes on the ~2^-32 chance; it terminates. */
        "const ORD=BigInt('0xffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551');"
        "const H2B=h=>{h=String(h).replace(/^0x/,'');const b=new Uint8Array(h.length>>1);"
        "for(let i=0;i<b.length;i++)b[i]=parseInt(h.substr(i*2,2),16);return b};"
        "const B2H=b=>Array.from(b).map(x=>x.toString(16).padStart(2,'0')).join('');"
        "const B64=u=>{const s=atob(String(u).replace(/-/g,'+').replace(/_/g,'/'));"
        "const b=new Uint8Array(s.length);for(let i=0;i<s.length;i++)b[i]=s.charCodeAt(i);return b};"

        /*  PKCS#8, P-256, private scalar only — the browser recomputes the
            public point on import. Sixty-seven bytes, thirty-five of them
            this fixed header.                                            */
        "const PK8='3041020100301306072a8648ce3d020106082a8648ce3d030107042730250201010420';"

        "const derive=async tok=>{const p=I.pv(),from=I.acct();"
        "const msg='IPSEITY seal v1 \\u00b7 chain '+I.D.chain+' \\u00b7 token '+tok;"
        "const hex='0x'+B2H(new TextEncoder().encode(msg));"
        "const sig=await p.request({method:'personal_sign',params:[hex,from]});"
        "let h=new Uint8Array(await sub.digest('SHA-256',H2B(sig)));"
        "for(;;){const d=BigInt('0x'+B2H(h));if(d>0n&&d<ORD)break;"
        "h=new Uint8Array(await sub.digest('SHA-256',h))}"
        "const priv=await sub.importKey('pkcs8',H2B(PK8+B2H(h)),"
        "{name:'ECDH',namedCurve:'P-256'},true,['deriveBits']);"
        "const jwk=await sub.exportKey('jwk',priv);"
        "return{priv:priv,x:B2H(B64(jwk.x)),y:B2H(B64(jwk.y))}};"

        "const onChain=async tok=>{const r=await I.tryCall(P,S.keyOf+I.W(tok));"
        "if(!r)return null;const x=String(r).slice(2,66),y=String(r).slice(66,130);"
        "return/[^0]/.test(x)?{x:x,y:y}:null};"

        "const pairKey=async(mine,theirs)=>{"
        "const pub=await sub.importKey('raw',H2B('04'+theirs.x+theirs.y),"
        "{name:'ECDH',namedCurve:'P-256'},false,[]);"
        "const bits=await sub.deriveBits({name:'ECDH',public:pub},mine.priv,256);"
        "const k=await sub.digest('SHA-256',bits);"
        "return sub.importKey('raw',k,'AES-GCM',false,['encrypt','decrypt'])};"

        "let KEY=null,MY=null;"
        "const seal=async h=>{if(!KEY)return{k:0,h:h};"
        "const iv=crypto.getRandomValues(new Uint8Array(12));"
        "const ct=new Uint8Array(await sub.encrypt({name:'AES-GCM',iv:iv},KEY,H2B(h)));"
        "return{k:1,h:B2H(iv)+B2H(ct)}};"

        /*  The renderer hands over every sealed row; rows this pair's key
            opens become text, the rest stay honestly shut. textContent
            only — a decrypted body is still somebody else's bytes.      */
        "window.UNSEAL=async(m,p)=>{if(m.kind!==1||!KEY)return;"
        "try{const b=H2B(m.body);"
        "const pt=new Uint8Array(await sub.decrypt({name:'AES-GCM',iv:b.slice(0,12)},KEY,b.slice(12)));"
        "p.textContent=new TextDecoder().decode(pt);p.className='sealed open'}catch(e){}};"

        /*───── the bar the page already rendered ─────*/
        "const bar=document.getElementById('sealbar');"
        "const st=document.getElementById('sealst');"
        "const btn=document.getElementById('sealpub');"
        "if(!bar||!st||!btn)return;"
        "const say=(m,warn)=>{st.textContent=m;"
        "bar.className=warn?'det only w':'det only'};"

        "const arm=async me=>{KEY=null;PL.out(async h=>({k:0,h:h}));btn.hidden=true;"
        "if(me==null){say('connect to seal this room');return}"
        "const theirs=await onChain(OTHER);"
        "const mineOn=await onChain(me);"
        "if(!mineOn){btn.hidden=false;"
        "say('#'+me+' has no published key \\u2014 this room sends plaintext until it does');return}"
        "if(!theirs){say('#'+T.other+' has not published a key \\u2014 plaintext until they do');return}"
        "MY=MY||await derive(me);"
        "if(MY.x!==mineOn.x||MY.y!==mineOn.y){"
        "say('the key this wallet derives is not the one #'+me+' published \\u2014 "
        "a different wallet published it; sending plaintext',1);return}"
        "KEY=await pairKey(MY,theirs);PL.out(seal);"
        "say('sealed \\u00b7 only #'+me+' and #'+T.other+' can read what is said here');"
        "PL.repaint()};"

        "btn.addEventListener('click',async()=>{try{"
        "const me=PL.me();if(me==null)throw new Error('connect first');"
        "MY=await derive(me);"
        "await I.send(P,S.announce+I.W(me)+MY.x+MY.y);"
        "await arm(me)}catch(x){I.say(String(x&&x.message||x),'no')}});"

        "PL.on(me=>{arm(me).catch(e=>{})});"
        "})();";
}
