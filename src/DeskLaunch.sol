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

  ── liquidity is encoded by Solidity, never approximated here ──

  `modifyLiquidities` takes a dynamic array of dynamic bytes behind a
  decoder that rejects non-canonical encoding. `V4PositionPlanner` now owns
  exactly that encoding job. This client sends it the choices a person can
  understand, reads back canonical PositionManager calldata, displays the
  authority and amount limits, and forwards those bytes unchanged.
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
        "let mined=null,landed=null,made=null,liqPlan=null;"
        "const say=(m,c)=>I.say(m,c);"

        /*  A string argument, by hand.

            Printable ASCII only, so one character is one byte and the length
            the head advertises is the length the tail actually has. Anything
            else is dropped rather than encoded carefully — a token whose
            name does not survive is a cosmetic loss, and a length that does
            not match its body moves every following argument.            */
        "const ASCII=s=>String(s==null?'':s).replace(/[^\\x20-\\x7e]/g,'').slice(0,64);"
        "const HTML=s=>s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');"
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
        /*  The band runs to 100% in hundredths of a basis point, so it is
            logarithmic for the same reason the pool fee is: the interesting
            fees all live in the first thousandth of a straight bar.       */
        "LOG('fflR','ffl',100);LOG('fclR','fcl',100);"
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
        "+'<div><span>supply</span><b>'+I.fmt(f.v,f.d,6)+' '+HTML(f.y)+'</b></div>';"
        "say('read from the launchpad \\u00b7 nothing sent','ok')});"

        "onc('cgo',async()=>{const f=form();"
        "await I.wait(await I.send(K.kiln,launchData(f.tok,f.n,f.y,f.d,f.v,f.salt)))});"

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

        /*  Which hook. The two kinds are not interchangeable and the page
            must not pretend they are: a Gate never sets a fee, so a pool
            initialised dynamic behind one charges zero for ever and a pool
            key cannot be edited afterwards. A Facet only ever sets a fee,
            so it reverts at `beforeInitialize` on a pool that is not
            dynamic. Each is wrong exactly where the other is right, which
            is why both guards below exist and why neither is a warning. */
        "const hkind=()=>Number(($('hk')||{}).value||0);"
        "const facetBand=()=>{const t=BigInt(String($('ft').value||'0').trim()||'0');"
        "const fl=Number($('ffl').value)||0,ce=Number($('fcl').value)||0;"
        "if(!(t>0n&&t<=0xffffffffffffffffn))throw new Error('which token sets the fee?');"
        "if(fl>ce)throw new Error('the fee at rest is above the fee at the furthest cut');"
        "if(ce>K.maxFee)throw new Error('a fee cannot be more than 100%');"
        "return{token:t,floor:fl,ceiling:ce}};"
        "const pc=x=>(Number(x)/10000).toFixed(Number(x)<1000?4:2)+'%';"

        /*  The reading, taken from the Kiln rather than recomputed here.
            The number a person is choosing against is the one the hook will
            actually charge, and the only way to be sure of that is to ask
            the contract that shares the hook's `Curve`.                  */
        "const fsum=async()=>{const e=$('fsum');if(!e)return;"
        "let g;try{g=facetBand()}catch(x){"
        "e.innerHTML='<div><span class=w>'+(x&&x.message||'')+'</span><b></b></div>';return}"
        "const r=await I.tryCall(K.kiln,S.band+I.W(g.token)+I.W(g.floor)+I.W(g.ceiling));"
        "if(!r){e.innerHTML='<div><span class=w>that token has no section to read "
        "\u2014 does it exist on this chain?</span><b></b></div>';return}"
        "const conc=I.word(r,1),now=I.word(r,2);"
        "e.innerHTML='<div><span>your solid is</span><b>'"
        "+(Number(conc)*100/80000).toFixed(1)+'% of the way to its furthest cut</b></div>'"
        "+'<div><span>so the pool would charge</span><b>'+pc(now)+' right now</b></div>'"
        "+'<div><span>and turning it moves that</span><b>'"
        "+pc(g.floor)+' to '+pc(g.ceiling)+'</b></div>'"
        "+'<div><span>nobody can set it by hand</span><b>no setter, no owner</b></div>'};"
        "['ft','ffl','fcl'].forEach(i=>{const e=$(i);"
        "if(e)e.addEventListener('input',()=>{fsum()})});"

        "const hshow=()=>{const k=hkind();"
        "const g=$('hkg'),f=$('hkf');"
        "if(g)g.style.display=k===1?'none':'';if(f)f.style.display=k===0?'none':'';"
        "if($('hmined'))$('hmined').innerHTML='';mined=null;"
        "if($('hgo'))$('hgo').disabled=true;"
        "if(k!==0)fsum();if(k!==1)gsum();psum()};"
        "const hk=$('hk');if(hk)hk.addEventListener('change',hshow);"

        /*  The search. Windows of sixty thousand, because an eth_call has a
            gas ceiling and a function that ignored it would fail at some
            size with no partial answer — so the page asks for a window,
            gets told whether it landed, and moves along.                 */
        "on('hmine',async()=>{const kd=hkind();let word;"
        /*  The Facet's argument is packed by the Kiln, not here. Its layout
            is a token in the high bits and two fees below it, and a client
            that shifted by the wrong eight would put the token id inside
            the fee band and mine a hook that prices a token nobody owns —
            silently, because every word involved is a valid word. The
            contract that unpacks it is the one that packs it.          */
        "if(kd===1){const b=facetBand();"
        "const a=await I.call(K.kiln,S.facetArg+I.W(b.token)+I.W(b.floor)+I.W(b.ceiling));"
        "word='0x'+String(a).slice(2,66)}"
        "else if(kd===2){const b=facetBand(),g=gateArg();"
        "const a=await I.call(K.kiln,S.gateFacetArg+I.W(b.token)+I.W(b.floor)+I.W(b.ceiling)"
        "+I.W(g.opens)+I.W(g.unlocks));word='0x'+String(a).slice(2,66)}"
        "else word=gateArg().word;"
        "const rh=await I.call(K.kiln,S.recipeHash+I.W(kd)+I.pad(word));"
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
        /*  `sets` is the only property the pool step cares about, and it is
            a fact about the kind rather than about the address: a Gate's
            beforeSwap returns a zero fee override for ever.             */
        "mined={salt:salt,at:at,arg:word,flags:flags,kind:kd,sets:kd!==0};"
        "out.innerHTML='<div><span>found after</span><b>'+tried+' tried</b></div>'"
        "+'<div><span>the hook would live at</span><b>'+at+'</b></div>'"
        "+'<div><span>its low 14 bits</span><b>0x'"
        "+(BigInt(at)&0x3fffn).toString(16)+' \\u2014 '"
        "+(kd===2?'beforeInitialize + beforeSwap + beforeRemoveLiquidity':kd?'beforeInitialize + beforeSwap':'beforeSwap + beforeRemoveLiquidity')"
        "+'</b></div>'"
        "+'<div><span>it sets the fee</span><b>'"
        "+(kd?'yes \\u2014 pair it with a dynamic-fee pool':'no \\u2014 pair it with a fixed fee')"
        "+'</b></div>';"
        "$('hgo').disabled=false;"
        "say('found by your own node \\u00b7 nothing was sent','ok');return}"
        "from+=WIN}"
        "throw new Error('no address in '+tried+' tries \\u2014 press again to keep going')});"

        "onc('hgo',async()=>{if(!mined)throw new Error('find an address first');"
        "await I.wait(await I.send(K.kiln,S.deployHook+I.W(mined.kind)+I.pad(mined.salt)"
        "+I.pad(mined.arg)))});"

        /*───── 3 · the pool ─────*/
        "const tickOf=(p,d0,d1)=>Math.round(Math.log(p*Math.pow(10,d1-d0))/Math.log(1.0001));"
        "const psum=async()=>{const e=$('psum');if(!e)return;"
        "const fee=Number(($('pf')||{}).value||3000);"
        /*  The warning used to read `mined ? '' : …`, which asked whether a
            hook existed rather than whether it sets a fee — and the only
            hook this page could mine was a Gate, which never does. The
            reassuring case and the broken case were the same case.     */
        "e.innerHTML=(fee===K.dynamicFee"
        "?'<div><span>fee</span><b>dynamic \\u2014 set by the hook, per swap</b></div>'"
        "+((mined&&mined.sets)?'':'<div><span class=w>a dynamic-fee pool starts at "
        "zero and only its hook can move it \\u2014 without a Facet nothing ever will, "
        "and a pool key cannot be changed afterwards</span><b></b></div>')"
        ":'<div><span>fee</span><b>'+(fee/10000)+'%</b></div>'"
        "+((mined&&mined.sets)?'<div><span class=w>a Facet reverts unless the pool is "
        "dynamic \\u2014 tick dynamic, or mine a Gate instead</span><b></b></div>':''))"
        "+'<div><span>hook</span><b>'+(mined?mined.at:'none')+'</b></div>'"
        "+'<div><span>pool</span><b>'+(K.v4&&mined?'v4':K.v4?'v4':'v3')+'</b></div>'};"
        "['pf','ps','pq'].forEach(i=>{const e=$(i);if(e)e.addEventListener('input',psum);"
        "if(e)e.addEventListener('change',psum)});psum();"

        /*  The first `hshow` belongs here rather than beside its own
            definition. It paints the pool summary too, and `psum` is a
            `const` declared further down — calling it any earlier reaches
            into the temporal dead zone and throws, which does not break the
            hook step alone, it kills the whole script and with it every
            button on the page. The listener above is bound early because
            binding is not calling; the first paint waits until everything
            it paints exists.                                            */
        "hshow();"

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
        /*  Both directions, because each hook is wrong exactly where the
            other is right. v4 starts a dynamic-fee pool at zero and lets
            only the hook move it; a Gate's beforeSwap returns a zero
            override for ever, so that pool is priced at nothing and a pool
            key is immutable. A Facet is the reverse: its beforeInitialize
            reverts `NotDynamic` on a fixed-fee pool, which is a revert the
            page can explain here instead of letting the wallet show it as
            an unnamed failure.                                         */
        "if(fee===K.dynamicFee&&!(mined&&mined.sets))"
        "throw new Error('a dynamic fee needs a hook that sets one \\u2014 mine a Facet, "
        "or choose a fixed fee. A Gate never sets a fee, and a pool that starts at zero "
        "with nothing to move it stays there');"
        "if(mined&&mined.sets&&fee!==K.dynamicFee)"
        "throw new Error('a Facet only attaches to a dynamic-fee pool \\u2014 it reverts "
        "at initialize otherwise. Tick dynamic, or mine a Gate');"
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
        "const hook=mined?mined.at:'0x0000000000000000000000000000000000000000';"
        "const sqrt=I.word(sq,0);made={token:fToken(),coin:a,c0:lo,c1:hi,fee:fee,sp:sp,"
        "hook:hook,sqrt:sqrt,d0:d0,d1:d1};"
        "await I.wait(await I.send(K.manager,S.initV4+I.AD(lo)+I.AD(hi)+I.W(fee)+I.S(sp)"
        "+I.AD(hook)+I.W(sqrt)))});"

        /*───── 4 · the position ─────*/
        "const fToken=()=>BigInt(String($('ct').value||'0').trim()||'0');"
        "const hexBytes=x=>{x=String(x||'0x').trim();"
        "if(!/^0x(?:[0-9a-fA-F]{2})*$/.test(x))throw new Error('hook data must be whole bytes of hex');"
        "return x.slice(2)};"
        "const tail=b=>I.W(b.length/2)+b+'0'.repeat((64-b.length%64)%64);"
        "const extract=(r,wi)=>{const off=Number(I.word(r,wi));"
        "const n=Number(BigInt('0x'+r.slice(2+off*2,2+off*2+64)));"
        "return'0x'+r.slice(2+off*2+64,2+off*2+64+n*2)};"
        "const lot=$('lot');if(lot)lot.addEventListener('change',()=>{"
        "$('lo').style.display=lot.value==='other'?'':'none'});"
        "const positionForm=async()=>{if(!made)throw new Error('create the pool first');"
        "const lower=Number(String($('ll').value||'').trim()),upper=Number(String($('lu').value||'').trim());"
        "if(!Number.isInteger(lower)||!Number.isInteger(upper)||lower>=upper)"
        "throw new Error('choose two ticks, lower then upper');"
        "if(lower%made.sp||upper%made.sp)throw new Error('both ticks must be multiples of '+made.sp);"
        "const a0=I.parse($('l0').value,made.d0),a1=I.parse($('l1').value,made.d1);"
        "if(a0<=0n&&a1<=0n)throw new Error('put at least one currency into the position');"
        "if(a0>(1n<<128n)-1n||a1>(1n<<128n)-1n)throw new Error('an amount is too large');"
        "const ownKind=String(($('lot')||{}).value||'wallet');let owner;"
        "if(ownKind==='reach'){const ar=await I.call(K.hub,S.account+I.W(made.token));"
        "owner='0x'+String(ar).slice(26,66)}else if(ownKind==='other')owner=String($('lo').value||'').trim();"
        "else owner=String(I.acct()||'').trim();"
        "if(!/^0x[0-9a-fA-F]{40}$/.test(owner)||/^0x0{40}$/i.test(owner))"
        "throw new Error('connect, or name who owns the position and its fees');"
        "const mins=Number($('ld').value);if(!(mins>0&&mins<=10080))"
        "throw new Error('deadline must be 1 minute to 7 days');"
        "const deadline=BigInt(Math.floor(Date.now()/1000)+Math.round(mins*60));"
        "const hd=hexBytes($('lh').value);return{lower,upper,a0,a1,owner,deadline,hd}};"
        "const planData=f=>{const st=I.AD(made.c0)+I.AD(made.c1)+I.W(made.fee)+I.S(made.sp)"
        "+I.AD(made.hook)+I.S(f.lower)+I.S(f.upper)+I.W(made.sqrt)+I.W(f.a0)+I.W(f.a1)"
        "+I.AD(f.owner)+I.W(f.deadline)+I.W(13*32)+tail(f.hd);"
        "return S.mintPlan+I.W(made.token)+I.AD(made.coin)+I.W(3*32)+st};"
        "on('lcheck',async()=>{await I.connect();const f=await positionForm();"
        "const lp=await I.call(K.planner,S.livePrice+I.AD(made.c0)+I.AD(made.c1)+I.W(made.fee)"
        "+I.S(made.sp)+I.AD(made.hook)+I.W(made.sqrt));made.sqrt=I.word(lp,0);const priceBlock=I.word(lp,1);"
        "const r=await I.call(K.planner,planData(f));"
        "liqPlan={f:f,liquidity:I.word(r,0),value:I.word(r,1),data:extract(r,2)};"
        "$('lplan').innerHTML='<div><span>position owner + all LP fees</span><b>'+f.owner+'</b></div>'"
        "+'<div><span>range</span><b>ticks '+f.lower+' to '+f.upper+'</b></div>'"
        "+'<div><span>liquidity</span><b>'+liqPlan.liquidity+'</b></div>'"
        "+'<div><span>live price read at block</span><b>'+priceBlock+'</b></div>'"
        "+'<div><span>maximum token 0</span><b>'+I.fmt(f.a0,made.d0,8)+'</b></div>'"
        "+'<div><span>maximum token 1</span><b>'+I.fmt(f.a1,made.d1,8)+'</b></div>'"
        "+'<div><span>position manager</span><b>'+K.positionManager+'</b></div>';"
        "$('lgo').disabled=false;say('canonical plan built by Solidity \\u00b7 nothing sent','ok')});"
        "on('lapprove',async()=>{await I.connect();const f=await positionForm();"
        "for(const z of [[made.c0,f.a0],[made.c1,f.a1]]){const t=z[0],amt=z[1];"
        "if(/^0x0{40}$/i.test(t)||amt===0n)continue;"
        "const er=await I.tryCall(t,S.allowance+I.AD(I.acct())+I.AD(K.permit2));"
        "const ea=er?I.word(er,0):0n;if(ea<amt){if(ea>0n)await I.wait(await I.send(t,S.approve+I.AD(K.permit2)+I.W(0)));"
        "await I.wait(await I.send(t,S.approve+I.AD(K.permit2)+I.W(amt)))}"
        "const pr=await I.tryCall(K.permit2,S.permitAllowance+I.AD(I.acct())+I.AD(t)+I.AD(K.positionManager));"
        "const pa=pr?I.word(pr,0):0n,pe=pr?I.word(pr,1):0n;"
        "if(pa<amt||pe<f.deadline)await I.wait(await I.send(K.permit2,S.permitApprove+I.AD(t)+I.AD(K.positionManager)+I.W(amt)+I.W(f.deadline)))}"
        "say('approvals confirmed \\u00b7 rebuild the plan if anything changed','ok')});"
        "on('lrevoke',async()=>{await I.connect();if(!made)throw new Error('create or load the pool first');"
        "for(const t of [made.c0,made.c1]){if(/^0x0{40}$/i.test(t))continue;"
        "await I.wait(await I.send(K.permit2,S.permitApprove+I.AD(t)+I.AD(K.positionManager)+I.W(0)+I.W(0)))}"
        "say('PositionManager allowances revoked','ok')});"
        "on('lgo',async()=>{await I.connect();if(!liqPlan)throw new Error('build and inspect the position first');"
        "await I.wait(await I.send(K.positionManager,liqPlan.data,liqPlan.value));"
        "liqPlan=null;$('lgo').disabled=true;say('position confirmed','ok')});"

        /*───── 5 · an existing position ─────*/
        "let managePlan=null,manageKey=null;const mid=()=>{const x=BigInt(String($('mi').value||'0'));"
        "if(x<=0n)throw new Error('a PositionManager NFT id above zero');return x};"
        "const mu=x=>{const n=BigInt(String(x||'0').trim()||'0');if(n<0n)throw new Error('amounts cannot be negative');return n};"
        "const dynCall=(sel,ws,b)=>sel+ws.join('')+I.W((ws.length+1)*32)+tail(b);"
        "on('minfo',async()=>{const id=mid();const o=await I.call(K.positionManager,S.ownerOf+I.W(id));"
        "const q=await I.call(K.positionManager,S.positionInfo+I.W(id));"
        "const l=await I.call(K.positionManager,S.positionLiquidity+I.W(id));"
        "manageKey={c0:'0x'+String(q).slice(26,66),c1:'0x'+String(q).slice(90,130)};"
        "$('minfod').innerHTML='<div><span>owner</span><b>0x'+String(o).slice(26,66)+'</b></div>'"
        "+'<div><span>currency 0</span><b>0x'+String(q).slice(26,66)+'</b></div>'"
        "+'<div><span>currency 1</span><b>0x'+String(q).slice(90,130)+'</b></div>'"
        "+'<div><span>liquidity</span><b>'+I.word(l,0)+'</b></div>'});"
        "on('mpreview',async()=>{await I.connect();const id=mid(),a=$('ma').value,l=mu($('ml').value),"
        "x0=mu($('mm0').value),x1=mu($('mm1').value),hd=hexBytes($('mh').value);"
        "const mins=Number($('md').value);if(!(mins>0&&mins<=10080))throw new Error('deadline must be 1 minute to 7 days');"
        "const dl=BigInt(Math.floor(Date.now()/1000)+Math.round(mins*60));"
        "const rc=String($('mr').value||I.acct()||'').trim();if(!/^0x[0-9a-fA-F]{40}$/.test(rc))throw new Error('a recipient address');"
        "let d,wi=0;if(a==='increase'){if(l<=0n)throw new Error('liquidity must be above zero');"
        "d=dynCall(S.increasePlan,[I.W(id),I.W(l),I.W(x0),I.W(x1),I.W(dl)],hd);wi=1}"
        "else if(a==='decrease'){if(l<=0n)throw new Error('liquidity must be above zero');"
        "d=dynCall(S.decreasePlan,[I.W(id),I.W(l),I.W(x0),I.W(x1),I.AD(rc),I.W(dl)],hd)}"
        "else if(a==='burn')d=dynCall(S.burnPlan,[I.W(id),I.W(x0),I.W(x1),I.AD(rc),I.W(dl)],hd);"
        "else d=dynCall(S.collectPlan,[I.W(id),I.AD(rc),I.W(dl)],hd);"
        "const r=await I.call(K.planner,d);managePlan={data:extract(r,wi),value:wi?I.word(r,0):0n};"
        "$('mplan').innerHTML='<div><span>action</span><b>'+a+'</b></div><div><span>recipient</span><b>'+rc+'</b></div>'"
        "+'<div><span>PositionManager</span><b>'+K.positionManager+'</b></div>';$('mgo').disabled=false;"
        "say('canonical lifecycle plan built by Solidity \\u00b7 nothing sent','ok')});"
        "on('mapprove',async()=>{await I.connect();if(!manageKey)throw new Error('inspect the position first');"
        "const dl=BigInt(Math.floor(Date.now()/1000)+1200),am=[mu($('mm0').value),mu($('mm1').value)];"
        "for(const z of [[manageKey.c0,am[0]],[manageKey.c1,am[1]]]){if(/^0x0{40}$/i.test(z[0])||z[1]===0n)continue;"
        "const er=await I.tryCall(z[0],S.allowance+I.AD(I.acct())+I.AD(K.permit2)),ea=er?I.word(er,0):0n;"
        "if(ea<z[1]){if(ea>0n)await I.wait(await I.send(z[0],S.approve+I.AD(K.permit2)+I.W(0)));"
        "await I.wait(await I.send(z[0],S.approve+I.AD(K.permit2)+I.W(z[1])))}"
        "await I.wait(await I.send(K.permit2,S.permitApprove+I.AD(z[0])+I.AD(K.positionManager)+I.W(z[1])+I.W(dl)))}"
        "say('add-liquidity approvals confirmed','ok')});"
        "on('mgo',async()=>{if(!managePlan)throw new Error('build and inspect an action first');"
        "await I.wait(await I.send(K.positionManager,managePlan.data,managePlan.value));managePlan=null;"
        "$('mgo').disabled=true;say('position action confirmed','ok')});"

        /*───── reading a hook ─────*/
        "on('hxgo',()=>{const v=String($('hx').value||'').trim();"
        "if(!/^0x[0-9a-fA-F]{40}$/.test(v))throw new Error('that is not an address');"
        "location.href='/hook/'+v.toLowerCase()});"
        "const hx=$('hx');if(hx)hx.addEventListener('keydown',e=>{"
        "if(e&&e.key==='Enter'){const v=String(hx.value||'').trim();"
        "if(/^0x[0-9a-fA-F]{40}$/.test(v))location.href='/hook/'+v.toLowerCase()}});"
        "})();";
}
