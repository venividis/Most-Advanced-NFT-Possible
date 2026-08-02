// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*───────────────────────────────────────────────────────────────────────────
  DeskTrade — the trading clients, as contract code

  `DeskUni` holds the data: the addresses, the derived asset list, and every
  selector computed from its own signature string. This holds the programs
  that use it. They are separate contracts for the plainest possible reason
  — EIP-170 gives each of them 24,576 bytes and together they do not fit —
  but the split falls in a useful place anyway: what the site knows is in
  one contract, what the site does is in another, and a reader checking a
  selector against the ABI never has to read a line of JavaScript to find it.

  Nothing here is fetched. Every byte of these programs is contract code,
  handed to the browser inside the document the contract generated, on a
  page reached over `web3://` with no DNS and no server.
───────────────────────────────────────────────────────────────────────────*/
contract DeskTrade {
    /// @notice The swap card.
    function swap() external pure returns (string memory) {
        return string.concat("<script>", SWAP_JS, "</script>");
    }

    /*───────────────────────────────────────────────────────────────────────

      The swap card.

      Uniswap's hosted router considers thousands of pools, splits an order
      across several of them, and prices the gas of each route. This does
      the part of that job the browser can do honestly: it quotes the pair
      at every fee tier that has a pool, one `eth_call` each, and takes the
      best answer. Single hop, because a multi-hop path is a `bytes` argument
      and this client has no ABI coder — and a page that quietly gave you a
      worse single-hop price while implying it had searched would be worse
      than one that says what it looked at.

      The quote comes from QuoterV2, which is not a `view` function: it
      works by making the pool perform the swap and catching the revert. A
      browser can run it with `eth_call`, which executes and discards. The
      page contract cannot, which is why the number under the card at render
      time is the pool's spot price and the number in the card is the quote.

    ───────────────────────────────────────────────────────────────────────*/
    string internal constant SWAP_JS =
        "(()=>{const I=window.IP,N=window.UNI;if(!I||!N)return;"
        "const $=I.$,U=N.U,S=N.S;"
        "let A=null,B=null,ps=[],pick=null,forced=0,q=0n,slip=50,mins=30,busy=0,tmr=0;"
        "const put=(i,v)=>{const e=$(i);if(e)e.textContent=v};"
        "const paint=()=>{put('ts',A?A.s:'select');put('rs',B?B.s:'select');"
        "put('sl',(slip/100)+'%')};"
        "const bal=async(t,id)=>{const e=$(id);if(!e)return 0n;"
        "if(!t||!I.acct()){e.textContent='';return 0n}"
        "const r=await I.tryCall(t.a,S.balanceOf+I.AD(I.acct()));"
        "if(!r){e.textContent='';return 0n}"
        "const b=I.word(r,0);e.textContent='balance '+I.fmt(b,t.d,4);return b};"
        // which tiers exist, and how deep each is
        "const routes=async()=>{const t=$('rt');ps=await N.pools(A,B);pick=ps[0]||null;forced=0;"
        "if(!t)return;if(!A||!B){t.innerHTML='';return}"
        "if(!ps.length){t.innerHTML='<div><span>pools</span><b>none for this pair</b></div>';return}"
        "t.innerHTML=ps.map(p=>'<button data-fee=\\''+p.fee+'\\'"
        "class=\\'tr'+(pick&&p.fee===pick.fee?' on':'')+'\\'>'+(p.fee/10000)+'%</button>').join('');"
        "t.querySelectorAll('[data-fee]').forEach(b=>b.addEventListener('click',()=>{"
        "pick=ps.find(x=>String(x.fee)===b.dataset.fee)||pick;forced=1;"
        "t.querySelectorAll('.tr').forEach(z=>z.classList.remove('on'));"
        "b.classList.add('on');refresh()}))};"
        /*  Every tier that has a pool, unless the visitor pressed one — in
            which case exactly that one. The page says the tier can be
            overridden and this is what makes that true: before, the button
            moved the highlight and the trade still went wherever the best
            quote was, which is a control that lies about what it does.   */
        "const quoteAll=async amt=>{let best=null;"
        "for(const p of (forced&&pick?[pick]:ps)){"
        "const r=await I.tryCall(U.quoter,"
        "S.quote+I.AD(A.a)+I.AD(B.a)+I.W(amt)+I.W(p.fee)+I.W(0),30000000);"
        "if(!r)continue;const o=I.word(r,0);"
        "if(o>0n&&(!best||o>best.out))best={out:o,fee:p.fee,pool:p.pool}}"
        "return best};"
        "const refresh=async()=>{if(busy){later();return}busy=1;try{"
        "const det=$('det'),go=$('go');"
        "if(!A||!B){$('so').value='';det.innerHTML='';"
        "go.textContent='Choose two tokens';go.disabled=true;return}"
        "if(A.a===B.a){det.innerHTML='';go.textContent='Those are the same token';"
        "go.disabled=true;return}"
        "const amt=(()=>{try{return I.parse($('si').value,A.d)}catch(e){return -1n}})();"
        "if(amt<=0n){$('so').value='';det.innerHTML='';"
        "go.textContent=amt<0n?'Enter an amount':(I.acct()?'Enter an amount':'Connect wallet');"
        "go.disabled=amt<0n||!!I.acct();return}"
        "if(!ps.length){det.innerHTML='<div><span>pools</span><b>none for this pair</b></div>';"
        "go.textContent='No Uniswap pool for this pair';go.disabled=true;return}"
        "const b=await quoteAll(amt);"
        "if(!b){$('so').value='';"
        "det.innerHTML='<div><span>quote</span><b>no pool could fill this</b></div>';"
        "go.textContent='No route';go.disabled=true;return}"
        "if(!forced){pick=ps.find(p=>p.fee===b.fee)||pick;const rw=$('rt');"
        "if(rw)rw.querySelectorAll('[data-fee]').forEach(z=>"
        "z.classList.toggle('on',String(z.dataset.fee)===String(b.fee)))}q=b.out;"
        "$('so').value=I.fmt(q,B.d,8);"
        "const minOut=q*BigInt(10000-slip)/10000n;"
        "const rate=I.fmt(q*(10n**BigInt(A.d))/amt,B.d,6);"
        "det.innerHTML='<div><span>rate</span><b>1 '+A.s+' = '+rate+' '+B.s+'</b></div>'"
        "+'<div><span>through</span><b>the '+(b.fee/10000)+'% pool</b></div>'"
        "+'<div><span>you receive at least</span><b>'+I.fmt(minOut,B.d,6)+' '+B.s+'</b></div>'"
        "+'<div><span>deadline</span><b>'+(U.kind===0?mins+' minutes':"
        "'this router has no deadline field')+'</b></div>';"
        "if(!I.acct()){go.textContent='Connect wallet';go.disabled=false;return}"
        "const al=await I.tryCall(A.a,S.allowance+I.AD(I.acct())+I.AD(U.router));"
        "go.disabled=false;"
        "go.textContent=(al?I.word(al,0):0n)<amt?('Approve '+A.s):"
        "('Swap '+A.s+' for '+B.s);"
        "}catch(e){I.say(String(e&&e.message||e),'no')}finally{busy=0}};"
        "const later=()=>{clearTimeout(tmr);tmr=setTimeout(refresh,250)};"
        /*  Both shapes, chosen by the kind that came with the address.
            `amountIn` of zero is refused here as well as by the amount
            field, because on SwapRouter02 zero is not "swap nothing": it
            is the CONTRACT_BALANCE sentinel, and it means "swap everything
            this router is holding".                                      */
        "const build=(amt,minOut,fee)=>{"
        "if(amt<=0n)throw new Error('an amount of zero is a sweep sentinel on one of "
        "these routers, not an empty trade');"
        "const to=I.acct();"
        "if(/^0x0{39}[12]$/i.test(to))throw new Error('that recipient is a router sentinel');"
        "const head=I.AD(A.a)+I.AD(B.a)+I.W(fee)+I.AD(to);"
        "if(U.kind===0){const dl=BigInt(Math.floor(Date.now()/1000)+mins*60);"
        "return S.swapV3+head+I.W(dl)+I.W(amt)+I.W(minOut)+I.W(0)}"
        "return S.swap02+head+I.W(amt)+I.W(minOut)+I.W(0)};"
        "const setA=async t=>{A=t;paint();await routes();bal(A,'bi');refresh()};"
        "const setB=async t=>{B=t;paint();await routes();bal(B,'bo');refresh()};"
        "N.picker('ta','tax',setA);N.picker('tb','tbx',setB);"
        "$('si').addEventListener('input',later);"
        "const fl=$('flip');if(fl)fl.addEventListener('click',async()=>{"
        "const x=A;A=B;B=x;const sa=$('ta'),sb=$('tb');"
        "if(sa&&sb){const v=sa.value;sa.value=sb.value;sb.value=v;"
        "const xa=$('tax'),xb=$('tbx');if(xa&&xb){const w=xa.value;xa.value=xb.value;xb.value=w;"
        "xa.hidden=sa.value!=='?';xb.hidden=sb.value!=='?'}}"
        "$('si').value='';$('so').value='';paint();await routes();"
        "bal(A,'bi');bal(B,'bo');refresh()});"
        "const mx=$('mx');if(mx)mx.addEventListener('click',async()=>{"
        "if(!A)return;const b=await bal(A,'bi');$('si').value=I.fmt(b,A.d,A.d);refresh()});"
        "const cg=$('cog');if(cg)cg.addEventListener('click',()=>{const p=$('set');p.hidden=!p.hidden});"
        "document.querySelectorAll('[data-slip]').forEach(b=>b.addEventListener('click',()=>{"
        "slip=Number(b.dataset.slip);paint();refresh()}));"
        "const dl=$('dl');if(dl)dl.addEventListener('input',()=>{"
        "mins=Math.max(1,Number(dl.value)||30);refresh()});"
        "$('go').addEventListener('click',async()=>{try{"
        "if(!I.acct()){await I.connect();I.say('connected \\u00b7 '+I.nm(),'ok');"
        "await bal(A,'bi');await bal(B,'bo');return refresh()}"
        "if(!A||!B)throw new Error('choose two tokens');"
        "const amt=I.parse($('si').value,A.d);"
        "if(amt<=0n)throw new Error('enter an amount');"
        "const al=await I.tryCall(A.a,S.allowance+I.AD(I.acct())+I.AD(U.router));"
        "if((al?I.word(al,0):0n)<amt){I.say('approving \\u2026');"
        "await I.send(A.a,S.approve+I.AD(U.router)+I.W((1n<<256n)-1n));"
        "I.say('approval sent \\u00b7 once it confirms, press again to swap','ok');return}"
        "const b=await quoteAll(amt);if(!b)throw new Error('no pool could fill that');"
        "const minOut=b.out*BigInt(10000-slip)/10000n;"
        "if(minOut<=0n)throw new Error('that slippage tolerance leaves no floor at all');"
        "await I.send(U.router,build(amt,minOut,b.fee));"
        "}catch(e){I.say(String(e&&e.message||e),'no')}});"
        "paint();refresh();"
        "I.chainOk().then(o=>{if(o&&I.pv()&&I.pv().request)"
        "I.pv().request({method:'eth_accounts'}).then(a=>{if(a&&a[0])"
        "I.connect().then(()=>{bal(A,'bi');bal(B,'bo');refresh()})})});"
        "})();";

    /// @notice Liquidity: your positions, a new one at a range you choose,
    ///         and a pool that does not exist yet.
    function pos() external pure returns (string memory) {
        return string.concat("<script>", POS_JS, "</script>");
    }

    /*───────────────────────────────────────────────────────────────────────

      Concentrated liquidity, and the position that is a limit order.

      A v3 position is two ticks and an amount. Everything difficult about
      the page is that a tick is not a price and a person thinks in prices,
      so the conversion has to happen somewhere and be honest in both
      directions:

        · a price the person typed becomes an approximate tick here, with a
          logarithm in double precision — which is fine, because a tick is a
          choice and being one out is being 0.01% out;
        · that tick is snapped onto the pool's grid by `Venue.usable`, on
          chain, because the pool rejects anything else;
        · and the price that snapped tick actually means comes back from
          `Venue.priceAt`, on chain, exactly — and *that* is the number the
          page shows.

      Nobody is ever told their position sits at the price they typed. They
      are told where it actually sits.

      The one-sided case is the interesting one. A position placed entirely
      above the current tick can only be funded with token0, and as the
      price rises through it the pool converts that token0 into token1 —
      which is a sell order at a price you chose, executed by the AMM, with
      no server, no relayer, no signature and no counterparty to trust. It
      is not identical to a limit order and the page says so: it fills
      gradually across the range rather than all at once, it un-fills if the
      price comes back, it earns fees while it works, and nothing settles it
      automatically — you come back and withdraw.

      Ticks are signed and this is where that bites. Every pair priced below
      parity has a negative current tick, and a tick word padded with zeroes
      instead of sign-extended turns -201240 into a vast positive number. The
      position mints in a range nobody chose and nothing reverts. Every tick
      here goes through `I.S`.

    ───────────────────────────────────────────────────────────────────────*/
    string internal constant POS_JS =
        "(()=>{const I=window.IP,N=window.UNI;if(!I||!N)return;"
        "const $=I.$,U=N.U,S=N.S,MAXT=887272;"
        "const U128=(1n<<128n)-1n;"
        "let A=null,B=null,fee=3000,sp=60,st=null,lo=0,hi=0,slip=50,mins=30;"
        "const put=(i,v)=>{const e=$(i);if(e)e.textContent=v};"
        "const html=(i,v)=>{const e=$(i);if(e)e.innerHTML=v};"
        // token0/token1 is decided by address order and nothing else. The
        // position manager does not sort for you: an unsorted pair derives a
        // pool address that does not exist and reverts at slot0.
        "const ord=()=>{if(!A||!B)return null;"
        "return A.a.toLowerCase()<B.a.toLowerCase()?[A,B]:[B,A]};"
        // a price of token1 per token0, as a tick. Approximate on purpose.
        "const tickOf=(p,d0,d1)=>{if(!(p>0))return null;"
        "return Math.round(Math.log(p*Math.pow(10,d1-d0))/Math.log(1.0001))};"
        // and back, exactly, from the contract
        "const priceOf=async(t,d0,d1)=>{const r=await I.tryCall(U.venue,"
        "S.vPriceAt+I.S(t)+I.W(10n**BigInt(d0))+I.W(1));"
        "return r?I.fmt(I.word(r,0),d1,6):'?'};"
        "const snap=async t=>{const r=await I.tryCall(U.venue,S.vUsable+I.S(t)+I.S(sp));"
        "return r?Number(I.SW(I.word(r,0))):null};"
        "const widest=()=>Math.floor(MAXT/sp)*sp;"
        // where the pool is right now, which decides whether a range is
        // one-sided and which token can fund it
        "const look=async()=>{const o=ord();if(!o)return null;"
        "const r=await I.tryCall(U.factory,S.getPool+I.AD(o[0].a)+I.AD(o[1].a)+I.W(fee));"
        "if(!r)return null;const p='0x'+String(r).slice(26,66);"
        "if(/^0x0*$/.test(p))return null;"
        "const s0=await N.slot0(p);if(!s0)return null;return{pool:p,tick:s0.tick}};"
        "const showRange=async()=>{const o=ord();if(!o||!$('rng'))return;"
        "const p0=await priceOf(lo,o[0].d,o[1].d),p1=await priceOf(hi,o[0].d,o[1].d);"
        "html('rng','<div><span>range</span><b>'+p0+' \\u2013 '+p1+' '+o[1].s+' per '"
        "+o[0].s+'</b></div><div><span>ticks</span><b>'+lo+' \\u2026 '+hi+"
        "'<span class=m>a multiple of '+sp+', which is what the pool accepts</span>"
        "</b></div>')};"
        "const setSpan = async pct=>{const L=await look();"
        "const c=L?L.tick:0;const off=Math.round(Math.log(1+pct/100)/Math.log(1.0001));"
        "lo=await snap(Math.max(-MAXT,c-off));hi=await snap(Math.min(MAXT,c+off));"
        "if(lo===hi)hi=lo+sp;showRange()};"
        "const setFull=async()=>{lo=-widest();hi=widest();showRange()};"
        "const setCustom=async()=>{const o=ord();if(!o)return;"
        "const a=Number($('pmin').value),b=Number($('pmax').value);"
        "const ta=tickOf(a,o[0].d,o[1].d),tb=tickOf(b,o[0].d,o[1].d);"
        "if(ta===null||tb===null)throw new Error('enter two prices');"
        "lo=await snap(Math.min(ta,tb));hi=await snap(Math.max(ta,tb));"
        "if(lo===hi)hi=lo+sp;showRange()};"
        // the fee tier row, with the tiers this chain has not enabled left out
        "const tiers=()=>{const e=$('lt');if(!e)return;"
        "e.innerHTML=U.tiers.filter(t=>t.sp>0).map(t=>'<button data-fee=\\''+t.fee+"
        "'\\' class=\\'tr'+(t.fee===fee?' on':'')+'\\'>'+(t.fee/10000)+'%</button>').join('');"
        "e.querySelectorAll('[data-fee]').forEach(b=>b.addEventListener('click',async()=>{"
        "fee=Number(b.dataset.fee);"
        "sp=(U.tiers.find(t=>t.fee===fee)||{sp:60}).sp;"
        "e.querySelectorAll('.tr').forEach(z=>z.classList.remove('on'));b.classList.add('on');"
        "await setFull()}))};"
        "const need=async(t,amt)=>{if(amt<=0n)return true;"
        "const r=await I.tryCall(t.a,S.allowance+I.AD(I.acct())+I.AD(U.positions));"
        "if((r?I.word(r,0):0n)>=amt)return true;"
        "await I.send(t.a,S.approve+I.AD(U.positions)+I.W((1n<<256n)-1n));"
        "I.say('approval sent for '+t.s+' \\u00b7 press again once it confirms','ok');"
        "return false};"
        "const on=(id,fn)=>{const e=$(id);if(e)e.addEventListener('click',async()=>{"
        "try{await I.connect();await fn()}catch(x){I.say(String(x&&x.message||x),'no')}})};"
        // eleven flat words, ticks signed, in the order the struct declares
        "const mint=async(o,a0,a1,m0,m1)=>{const dl=BigInt(Math.floor(Date.now()/1000)+mins*60);"
        "await I.send(U.positions,S.mint+I.AD(o[0].a)+I.AD(o[1].a)+I.W(fee)"
        "+I.S(lo)+I.S(hi)+I.W(a0)+I.W(a1)+I.W(m0)+I.W(m1)+I.AD(I.acct())+I.W(dl))};"
        /*  The minimums, which are the part it is easy to get confidently
            wrong. The first version of this asked for 99.5% of BOTH desired
            amounts, which reverts almost every straddling mint: a position
            that spans the current price consumes the two tokens in whatever
            ratio the pool needs, and "at least 99.5% of each" is only
            satisfiable if the person happened to type that exact ratio.

            A one-sided range is the case where a floor is meaningful,
            because exactly one token is consumed and the amount is
            determined. So: a real floor there, none on a straddling range,
            and the page says which and why rather than shipping a number
            that looks protective and is not.                             */
        "on('add2',async()=>{const o=ord();if(!o)throw new Error('choose two tokens');"
        "const isA0=o[0].a===A.a,x=$('a0').value,y=$('a1').value;"
        "const a0=I.parse(isA0?x:y,o[0].d),a1=I.parse(isA0?y:x,o[1].d);"
        "if(a0<=0n&&a1<=0n)throw new Error('enter an amount for at least one side');"
        "const L=await look();const c=L?L.tick:null;"
        "let m0=0n,m1=0n;"
        "if(c!==null&&c<lo){"
        "if(a1>0n)throw new Error('that range is entirely above the current price, so "
        "the pool can only take '+o[0].s+' \u2014 leave the other amount empty');"
        "m0=a0*999n/1000n}"
        "else if(c!==null&&c>=hi){"
        "if(a0>0n)throw new Error('that range is entirely below the current price, so "
        "the pool can only take '+o[1].s+' \u2014 leave the other amount empty');"
        "m1=a1*999n/1000n}"
        "if(!await need(o[0],a0))return;if(!await need(o[1],a1))return;"
        "await mint(o,a0,a1,m0,m1)});"
        /*  A pool that does not exist yet. token0 < token1 is required here
            and the contract does not sort for you, so the price typed is
            always token1 per token0 after sorting and the page says which
            way round that came out.                                       */
        /*  The orientation, which was wrong and would have cost somebody a
            pool.

            The form says "second token per first", meaning the two pickers.
            A pool says token1 per token0, meaning address order. Those agree
            exactly half the time, and the half where they do not is not a
            small error: for WETH/USDC it is a factor of nine million, the
            pool goes live at that price, nothing reverts, and the first
            person to notice empties it.

            So the number is mapped from the form's meaning into the pool's,
            the same way `add2` already maps the amounts. The reciprocal is
            taken in double precision, which is fine — it only picks a tick,
            and the price that tick is actually worth is read back from the
            contract and shown before anything is sent.                   */
        "on('mkpool',async()=>{const o=ord();if(!o)throw new Error('choose two tokens');"
        "const v=Number($('p0').value);"
        // an empty box is Number('')===0, and 1/0 is Infinity, which would
        // sail through tickOf's own p>0 check and reach the encoder
        "if(!(v>0)||!isFinite(v))throw new Error('enter a starting price above zero');"
        "const t=tickOf(o[0].a===A.a?v:1/v,o[0].d,o[1].d);"
        "if(t===null)throw new Error('that price cannot be represented');"
        "const k=await snap(t);if(k===null)throw new Error('could not reach the venue');"
        "const r=await I.tryCall(U.venue,S.vSqrtAt+I.S(k));"
        "if(!r)throw new Error('that price is outside what a pool can represent');"
        // say what it is about to do, in the pool's own terms, before it does it
        "const back=await priceOf(k,o[0].d,o[1].d);"
        "I.say('creating at '+back+' '+o[1].s+' per '+o[0].s+' \u00b7 tick '+k);"
        "await I.send(U.positions,S.initPool+I.AD(o[0].a)+I.AD(o[1].a)+I.W(fee)"
        "+I.W(I.word(r,0)))});"
        /*  The portfolio, with no indexer. The position manager is an
            ERC-721Enumerable, so the list is balanceOf followed by that many
            tokenOfOwnerByIndex calls — every one of them a view, every one
            of them against the contract that holds the positions.        */
        "const mine=async()=>{const box=$('pos');if(!box)return;"
        "if(!I.acct()){box.innerHTML='<p class=e>Connect a wallet to see your "
        "positions.</p>';return}"
        "const b=await I.tryCall(U.positions,S.balanceOf+I.AD(I.acct()));"
        "const n=b?Number(I.word(b,0)):0;"
        "if(!n){box.innerHTML='<p class=e>No Uniswap v3 positions on this chain.</p>';return}"
        "const rows=[];const lim=Math.min(n,20);"
        "for(let i=0;i<lim;i++){"
        "const r=await I.tryCall(U.positions,S.ofOwner+I.AD(I.acct())+I.W(i));"
        "if(!r)continue;const id=I.word(r,0);"
        "const p=await I.tryCall(U.positions,S.positions+I.W(id));if(!p)continue;"
        "const t0=('0x'+String(p).slice(2+2*64+24,2+3*64)),"
        "t1=('0x'+String(p).slice(2+3*64+24,2+4*64));"
        "const f=Number(I.word(p,4)),tl=Number(I.SW(I.word(p,5))),"
        "tu=Number(I.SW(I.word(p,6))),liq=I.word(p,7),"
        "o0=I.word(p,10),o1=I.word(p,11);"
        "let s0='?',s1='?';try{s0=(await N.meta(t0)).s}catch(e){}"
        "try{s1=(await N.meta(t1)).s}catch(e){}"
        "rows.push('<tr><td>#'+id+'</td><td>'+s0+' / '+s1+'</td><td>'+(f/10000)+"
        "'%</td><td>'+tl+' \\u2026 '+tu+'</td><td>'+liq+'</td>'+"
        "'<td><button data-take=\\''+id+'\\'>collect fees</button>'+"
        "(liq>0n?'<button data-exit=\\''+id+'\\'>withdraw all</button>':'')+'</td></tr>')}"
        "box.innerHTML='<table><tr><th>position</th><th>pair</th><th>fee</th>"
        "<th>ticks</th><th>liquidity</th><th></th></tr>'+rows.join('')+'</table>'"
        "+(n>lim?'<p class=e>Showing '+lim+' of '+n+'.</p>':'');"
        // collect: four words, and the sweep sentinel is uint128 max. A
        // uint256 max word is rejected by the decoder, not truncated.
        "box.querySelectorAll('[data-take]').forEach(b=>b.addEventListener('click',async()=>{"
        "try{await I.connect();await I.send(U.positions,S.collect+I.W(b.dataset.take)"
        "+I.AD(I.acct())+I.W(U128)+I.W(U128))}"
        "catch(x){I.say(String(x&&x.message||x),'no')}}));"
        // and withdrawing is two transactions, because decreaseLiquidity
        // only credits what is owed and multicall is out of reach
        "box.querySelectorAll('[data-exit]').forEach(b=>b.addEventListener('click',async()=>{"
        "try{await I.connect();const id=b.dataset.exit;"
        "const p=await I.call(U.positions,S.positions+I.W(id));const liq=I.word(p,7);"
        "const dl=BigInt(Math.floor(Date.now()/1000)+mins*60);"
        "await I.send(U.positions,S.dec+I.W(id)+I.W(liq)+I.W(0)+I.W(0)+I.W(dl));"
        "I.say('liquidity released \\u00b7 now press collect fees to actually receive it','ok')}"
        "catch(x){I.say(String(x&&x.message||x),'no')}}))};"
        "const setA=async t=>{A=t;await setFull();mine()};"
        "const setB=async t=>{B=t;await setFull();mine()};"
        "N.picker('la','lax',setA);N.picker('lb','lbx',setB);"
        "tiers();"
        "on('rfull',async()=>{await setFull()});"
        "document.querySelectorAll('[data-span]').forEach(b=>b.addEventListener('click',"
        "async()=>{try{await setSpan(Number(b.dataset.span))}"
        "catch(x){I.say(String(x&&x.message||x),'no')}}));"
        "on('rcustom',async()=>{await setCustom()});"
        "I.chainOk().then(o=>{if(o&&I.pv()&&I.pv().request)"
        "I.pv().request({method:'eth_accounts'}).then(a=>{if(a&&a[0])"
        "I.connect().then(()=>mine())})});"
        "mine();"
        "})();";
}
