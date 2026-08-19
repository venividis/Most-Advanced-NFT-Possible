// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*───────────────────────────────────────────────────────────────────────────
  DeskLaunch — the launchpad's client

  Three things happen here that do not happen anywhere else on the site.

  ── it encodes two strings, and that is not an ABI coder ──

  Every other call this collection builds is flat words. `launch` takes a
  name and a symbol, and a `string` argument is an offset in the head and a
  length-prefixed body in the tail. That is a real encoding step and it is
  worth being precise about what has and has not been conceded: the client
  writes two offsets it computed from two known lengths, and pads two byte
  strings. It does not walk a type tree, it does not handle nesting, and it
  would not survive one more dynamic argument being added.

  The names are whitelisted to printable ASCII before they are measured,
  which is what makes the lengths trustworthy — a UTF-8 character is one
  JavaScript character and several bytes, and a length counted in the wrong
  one puts the tail at the wrong offset and the symbol becomes gibberish.

  ── it mines a CREATE2 salt with an eth_call ──

  A v4 hook must live at an address whose low fourteen bits are exactly its
  permissions, so deploying one means trying salts until one lands — about
  sixteen thousand on average. The client has no keccak. `Kiln.mine` is a
  `view`, so the visitor's own node does the search and commits nothing, and
  the client just moves a window along and counts.

  ── and it will not build a v4 liquidity call ──

  `modifyLiquidities` takes a dynamic array of dynamic bytes behind a
  decoder that rejects non-canonical encoding. That is past what is written
  above, and rather than approximate it the page sends v4 liquidity nowhere
  and says so.
───────────────────────────────────────────────────────────────────────────*/
contract DeskLaunch {
    function launch() external pure returns (string memory) {
        return string.concat("<script>", LAUNCH_JS, "</script>");
    }

    string internal constant LAUNCH_JS =
        "(()=>{const I=window.IP;if(!I)return;const $=I.$;"
        "const E=document.getElementById('K');if(!E)return;"
        "const K=JSON.parse(E.textContent),S=K.sel;"
        "const U=(window.UNI&&window.UNI.U)||null;"
        "let mined=null,landed=null;"
        "const say=(m,c)=>I.say(m,c);"

        /*  A string argument, by hand.

            Printable ASCII only, so one character is one byte and the length
            the head advertises is the length the tail actually has. Anything
            else is dropped rather than encoded carefully — a token whose
            name does not survive is a cosmetic loss, and a length that does
            not match its body moves every following argument.            */
        "const ASCII=s=>String(s==null?'':s).replace(/[^\\x20-\\x7e]/g,'').slice(0,64);"
        "const HEX=s=>{let h='';for(let i=0;i<s.length;i++)"
        "h+=s.charCodeAt(i).toString(16).padStart(2,'0');return h};"
        // length word + body padded up to a whole number of words
        "const TAIL=s=>{const b=HEX(s);const pad=b.length%64?64-(b.length%64):0;"
        "return I.W(s.length)+b+'0'.repeat(pad)};"
        "const WORDS=s=>2+(s.length?Math.ceil(s.length/32):0);"

        /*  launch(uint256,string,string,uint8,uint256,bytes32)
            head is six words: the signing token, two offsets, three flat
            values. The offsets moved when the token arrived — an offset is
            a promise about where the tail starts, and adding a head word
            moves the tail.                                               */
        "const launchData=(tok,n,y,d,v,salt)=>{"
        "const o1=6*32,o2=o1+32*(1+(n.length?Math.ceil(n.length/32):0));"
        "return S.launch+I.W(tok)+I.W(o1)+I.W(o2)+I.W(d)+I.W(v)+I.pad(salt)"
        "+TAIL(n)+TAIL(y)};"
        "const coinAtData=(by,n,y,d,v,salt)=>{"
        "const o1=6*32,o2=o1+32*(1+(n.length?Math.ceil(n.length/32):0));"
        "return S.coinAt+I.AD(by)+I.W(o1)+I.W(o2)+I.W(d)+I.W(v)+I.pad(salt)"
        "+TAIL(n)+TAIL(y)};"

        "const form=()=>{const n=ASCII($('cn').value),y=ASCII($('cs').value);"
        "const d=Number($('cd').value);"
        "const tok=BigInt(String($('ct').value||'0').trim()||'0');"
        "if(tok<=0n)throw new Error('which token signs it \u2014 the number of one you hold');"
        "if(!n||!y)throw new Error('a name and a symbol');"
        "if(!(d>=0&&d<=36))throw new Error('decimals must be 0 to 36');"
        "const v=I.parse($('cv').value,d);"
        "if(v<=0n)throw new Error('a supply of nothing is not a launch');"
        "let salt=String($('ck').value||'0x1').trim();"
        "if(!/^0x[0-9a-fA-F]{1,64}$/.test(salt))throw new Error('the salt is 32 bytes of hex');"
        "return{tok:tok,n:n,y:y,d:d,v:v,salt:salt}};"

        "const on=(id,fn)=>{const e=$(id);if(e)e.addEventListener('click',async()=>{"
        "try{await fn()}catch(x){say(String(x&&x.message||x),'no')}})};"
        "const onc=(id,fn)=>on(id,async()=>{await I.connect();await fn()});"

        /*  A slider and a number box, telling each other the truth. The box
            is canonical — it is what every handler reads — and the slider
            is a hand on it. Two are straight; two are logarithmic, because
            a fee that runs to 100% and a supply that runs to quadrillions
            are not walkable on a straight bar.                           */
        "const LOG=(r,b,k,fmt)=>{const R=$(r),B=$(b);if(!R||!B)return;"
        "R.addEventListener('input',()=>{const x=Math.round(Math.pow(10,Number(R.value)/k));"
        "B.value=x;B.dispatchEvent(new Event('input'));if(fmt)fmt(x)});"
        "B.addEventListener('input',()=>{const x=Number(B.value);"
        "if(x>0&&isFinite(x))R.value=Math.round(Math.log10(x)*k);if(fmt)fmt(x)})};"
        "const LIN=(r,b)=>{const R=$(r),B=$(b);if(!R||!B)return;"
        "R.addEventListener('input',()=>{B.value=R.value;"
        "B.dispatchEvent(new Event('input'))});"
        "B.addEventListener('input',()=>{R.value=B.value})};"
        "LIN('hoR','ho');LIN('hlR','hl');"
        "LOG('cvR','cv',10);LOG('psR','ps',100);"
        "const feeShow=x=>{const e=$('pfl');if(e)e.textContent="
        "x===K.dynamicFee?'dynamic':(x/10000).toFixed(x<100?4:2)+'%'};"
        "LOG('pfR','pf',100,feeShow);"
        "const pfd=$('pfd');if(pfd)pfd.addEventListener('change',()=>{"
        "$('pf').value=pfd.checked?K.dynamicFee:Math.round(Math.pow(10,Number($('pfR').value)/100));"
        "feeShow(Number($('pf').value));"
        "$('pf').dispatchEvent(new Event('input'))});"
        "feeShow(3000);"

        /*───── 1 · the token ─────*/
        "on('cchk',async()=>{const f=form();"
        "const who=I.acct()||(await I.connect(),I.acct());"
        "const r=await I.call(K.kiln,coinAtData(who,f.n,f.y,f.d,f.v,f.salt));"
        "landed='0x'+String(r).slice(26,66);"
        "$('cpre').innerHTML='<div><span>it would land at</span><b>'+landed+'</b></div>'"
        "+'<div><span>supply</span><b>'+I.fmt(f.v,f.d,6)+' '+f.y+'</b></div>';"
        "say('read from the launchpad \\u00b7 nothing sent','ok')});"

        "onc('cgo',async()=>{const f=form();"
        "await I.send(K.kiln,launchData(f.tok,f.n,f.y,f.d,f.v,f.salt))});"

        /*───── 2 · the hook ─────*/
        "const gateArg=()=>{const h=Number($('ho').value)||0,d=Number($('hl').value)||0;"
        "if(h<0||d<0)throw new Error('times run forwards');"
        "const now=BigInt(Math.floor(Date.now()/1000));"
        "const opens=now+BigInt(Math.round(h*3600));"
        "const unlocks=now+BigInt(Math.round(d*86400));"
        "return{opens:opens,unlocks:unlocks,word:'0x'+((opens<<64n)|unlocks).toString(16)}};"
        "const gsum=()=>{const e=$('hsum');if(!e)return;try{const g=gateArg();"
        "e.innerHTML='<div><span>trading opens</span><b>'"
        "+new Date(Number(g.opens)*1000).toISOString().slice(0,16).replace('T',' ')+' UTC</b></div>'"
        "+'<div><span>liquidity unlocks</span><b>'"
        "+new Date(Number(g.unlocks)*1000).toISOString().slice(0,16).replace('T',' ')+' UTC</b></div>'"
        "+'<div><span>both are fixed at deployment</span><b>no setter, no owner</b></div>'}"
        "catch(x){e.innerHTML=''}};"
        "['ho','hl'].forEach(i=>{const e=$(i);if(e)e.addEventListener('input',gsum)});gsum();"

        /*  The search. Windows of sixty thousand, because an eth_call has a
            gas ceiling and a function that ignored it would fail at some
            size with no partial answer — so the page asks for a window,
            gets told whether it landed, and moves along.                 */
        "on('hmine',async()=>{const g=gateArg();"
        "const rh=await I.call(K.kiln,S.recipeHash+I.W(0)+I.pad(g.word));"
        "const hash='0x'+String(rh).slice(2,66);"
        "const flags=I.word(rh,1);"
        "let from=0n,tried=0n;const WIN=60000n;"
        "const out=$('hmined');"
        "for(let i=0;i<12;i++){"
        "out.innerHTML='<div><span>searching</span><b>'+tried+' addresses tried</b></div>';"
        "const r=await I.tryCall(K.kiln,"
        "S.mine+I.pad(hash)+I.W(flags)+I.W(from)+I.W(WIN),30000000);"
        "if(!r)throw new Error('the search call would not run \\u2014 try a smaller window');"
        "tried+=WIN;"
        "if(I.word(r,0)===1n){"
        "const salt='0x'+String(r).slice(2+64,2+128);"
        "const at='0x'+String(r).slice(2+128+24,2+192);"
        "mined={salt:salt,at:at,arg:g.word,flags:flags};"
        "out.innerHTML='<div><span>found after</span><b>'+tried+' tried</b></div>'"
        "+'<div><span>the hook would live at</span><b>'+at+'</b></div>'"
        "+'<div><span>its low 14 bits</span><b>0x'"
        "+(BigInt(at)&0x3fffn).toString(16)+' \\u2014 beforeSwap + beforeRemoveLiquidity</b></div>';"
        "$('hgo').disabled=false;"
        "say('found by your own node \\u00b7 nothing was sent','ok');return}"
        "from+=WIN}"
        "throw new Error('no address in '+tried+' tries \\u2014 press again to keep going')});"

        "onc('hgo',async()=>{if(!mined)throw new Error('find an address first');"
        "await I.send(K.kiln,S.deployHook+I.W(0)+I.pad(mined.salt)+I.pad(mined.arg))});"

        /*───── 3 · the pool ─────*/
        "const tickOf=(p,d0,d1)=>Math.round(Math.log(p*Math.pow(10,d1-d0))/Math.log(1.0001));"
        "const psum=async()=>{const e=$('psum');if(!e)return;"
        "const fee=Number(($('pf')||{}).value||3000);"
        "e.innerHTML=(fee===K.dynamicFee"
        "?'<div><span>fee</span><b>dynamic \\u2014 set by the hook, per swap</b></div>'"
        "+(mined?'':'<div><span class=w>a dynamic fee with no hook is a pool nothing "
        "can ever price</span><b></b></div>')"
        ":'<div><span>fee</span><b>'+(fee/10000)+'%</b></div>')"
        "+'<div><span>hook</span><b>'+(mined?mined.at:'none')+'</b></div>'"
        "+'<div><span>pool</span><b>'+(K.v4&&mined?'v4':K.v4?'v4':'v3')+'</b></div>'};"
        "['pf','ps','pq'].forEach(i=>{const e=$(i);if(e)e.addEventListener('input',psum);"
        "if(e)e.addEventListener('change',psum)});psum();"

        /*  initialize((address,address,uint24,int24,address),uint160) — the
            PoolKey is five fixed-size fields, so the whole call is six flat
            words with no offset. This is the one v4 entry point a client
            with no ABI coder can build on its own.                       */
        "onc('pgo',async()=>{"
        "if(!K.v4)throw new Error('no v4 PoolManager on this chain');"
        "const a=landed;"
        "if(!a)throw new Error('check where your token lands first, so this page knows "
        "which token to pair');"
        "const q=String($('pq').value||'').trim();"
        "if(!/^0x[0-9a-fA-F]{40}$/.test(q))throw new Error('paste the token to pair with');"
        "const fee=Number($('pf').value),sp=Number($('ps').value);"
        "if(!(sp>0&&sp<32768))throw new Error('tick spacing is 1 to 32767');"
        "if(fee===K.dynamicFee&&!mined)"
        "throw new Error('a dynamic fee needs a hook that sets one, or the pool can "
        "never be priced');"
        "const price=Number($('pp').value);"
        "if(!(price>0)||!isFinite(price))throw new Error('a starting price above zero');"
        // sorted, because a PoolKey's currencies must be in address order
        "const lo=a.toLowerCase()<q.toLowerCase()?a:q,hi=lo===a?q:a;"
        "const da=Number($('cd').value)||18;"
        "const dq=await I.tryCall(q,(U&&U.sel.decimals)||'0x313ce567');"
        "const dqn=dq?Number(I.word(dq,0)):18;"
        "const d0=lo===a?da:dqn,d1=lo===a?dqn:da;"
        // the form says "per one of yours"; a pool says token1 per token0
        "const t=tickOf(lo===a?price:1/price,d0,d1);"
        "const snapped=Math.round(t/sp)*sp;"
        "const sq=await I.call(U?U.venue:K.kiln,((U&&U.sel.vSqrtAt)||'')+I.S(snapped));"
        "await I.send(K.manager,S.initV4+I.AD(lo)+I.AD(hi)+I.W(fee)+I.S(sp)"
        "+I.AD(mined?mined.at:'0x0000000000000000000000000000000000000000')"
        "+I.W(I.word(sq,0)))});"

        /*───── reading a hook ─────*/
        "on('hxgo',()=>{const v=String($('hx').value||'').trim();"
        "if(!/^0x[0-9a-fA-F]{40}$/.test(v))throw new Error('that is not an address');"
        "location.href='/hook/'+v.toLowerCase()});"
        "const hx=$('hx');if(hx)hx.addEventListener('keydown',e=>{"
        "if(e&&e.key==='Enter'){const v=String(hx.value||'').trim();"
        "if(/^0x[0-9a-fA-F]{40}$/.test(v))location.href='/hook/'+v.toLowerCase()}});"
        "})();";
}
