// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*───────────────────────────────────────────────────────────────────────────
  DeskCivic — the writes for the three pages that are mostly reads

  `/explore`, `/earn` and `/vote` are rendered by the page contract: the
  pool table, the chart, the vault's own declaration of what it holds, the
  proposal counts. All of that arrives as HTML and is there with JavaScript
  switched off.

  What needs a client is the small part that sends a transaction, and one
  read that cannot be rendered because it is about *you* rather than about
  the chain — your balance, your allowance, your voting power. That is what
  is here, and it is deliberately short.

  The one piece of judgement in it: on the governance page the client reads
  your current voting power *before* offering the vote button, because
  voting power is snapshotted at each proposal's start block and a vote cast
  with zero delegated tokens is accepted, counted as nothing, and never
  mentioned again.
───────────────────────────────────────────────────────────────────────────*/
contract DeskCivic {
    function civic() external pure returns (string memory) {
        return string.concat("<script>", CIVIC_JS, "</script>");
    }

    string internal constant CIVIC_JS =
        "(()=>{const I=window.IP,N=window.UNI;if(!I||!N)return;"
        "const $=I.$,U=N.U,S=N.S,MAXU=(1n<<256n)-1n;"
        "const val=i=>String(($(i)||{}).value||'').trim();"
        "const on=(id,fn)=>{const e=$(id);if(e)e.addEventListener('click',async()=>{"
        "try{await fn()}catch(x){I.say(String(x&&x.message||x),'no')}})};"
        "const onc=(id,fn)=>on(id,async()=>{await I.connect();await fn()});"
        "const addr=v=>{if(!/^0x[0-9a-fA-F]{40}$/.test(v))"
        "throw new Error('that is not an address');return v.toLowerCase()};"

        /*─── explore: the lookup box, and lengthening a pool's memory ───*/
        "on('xgo',()=>{location.href='/explore/'+addr(val('xa'))});"
        "const xa=$('xa');if(xa)xa.addEventListener('keydown',e=>{"
        "if(e&&e.key==='Enter')location.href='/explore/'+String(xa.value||'').trim()});"
        // increaseObservationCardinalityNext takes a uint16. A number past
        // 65535 is not a bigger buffer, it is a revert.
        "onc('grow',async()=>{const n=Number(val('gv'))||0;"
        "if(!(n>1&&n<=65535))throw new Error('between 2 and 65535 observations');"
        "await I.send(val('gp'),S.grow+I.W(n))});"

        /*─── earn: an ERC-4626 vault, after the page has verified it ───*/
        "on('vgo',()=>{location.href='/earn/'+addr(val('va'))});"
        "const vv=()=>val('vv'),vt=()=>val('vt');"
        "const vshow=async()=>{if(!$('vd')||!I.acct())return;"
        "const b=await I.tryCall(vt(),S.balanceOf+I.AD(I.acct()));"
        "const sb=await I.tryCall(vv(),S.balanceOf+I.AD(I.acct()));"
        "const da=await I.tryCall(vt(),S.decimals),dv=await I.tryCall(vv(),S.decimals);"
        "const na=da?Number(I.word(da,0)):18,nv=dv?Number(I.word(dv,0)):18;"
        "if($('vb')&&b)$('vb').textContent='balance '+I.fmt(I.word(b,0),na,4);"
        "if($('vsb')&&sb)$('vsb').textContent='shares '+I.fmt(I.word(sb,0),nv,4);"
        "const mr=await I.tryCall(vv(),S.vMaxRedeem+I.AD(I.acct()));"
        "$('vd').innerHTML=mr?'<div><span>you may redeem</span><b>'"
        "+I.fmt(I.word(mr,0),nv,6)+' shares</b></div>':''};"
        "onc('vdep',async()=>{const da=await I.call(vt(),S.decimals);"
        "const amt=I.parse(val('vi'),Number(I.word(da,0)));"
        "if(amt<=0n)throw new Error('enter an amount');"
        "const al=await I.tryCall(vt(),S.allowance+I.AD(I.acct())+I.AD(vv()));"
        "if((al?I.word(al,0):0n)<amt){"
        "await I.send(vt(),S.approve+I.AD(vv())+I.W(MAXU));"
        "I.say('approval sent \\u00b7 press again once it confirms','ok');return}"
        // deposit(assets, receiver) — two words, receiver is you
        "await I.send(vv(),S.vDeposit+I.W(amt)+I.AD(I.acct()));vshow()});"
        "onc('vred',async()=>{const dv=await I.call(vv(),S.decimals);"
        "const sh=I.parse(val('vr'),Number(I.word(dv,0)));"
        "if(sh<=0n)throw new Error('enter a number of shares');"
        // redeem(shares, receiver, owner) — three words, both of them you
        "await I.send(vv(),S.vRedeem+I.W(sh)+I.AD(I.acct())+I.AD(I.acct()));vshow()});"

        /*─── vote: power first, then the vote ───*/
        "const gg=()=>val('gg'),gt=()=>val('gt');"
        "const power=async()=>{const e=$('vp');if(!e||!I.acct()||!gt())return;"
        "const r=await I.tryCall(gt(),S.votes+I.AD(I.acct()));"
        "if(!r){e.textContent='unreadable';return}"
        "const v=I.word(r,0);"
        "const d=await I.tryCall(gt(),S.delegates+I.AD(I.acct()));"
        "const to=d?('0x'+String(d).slice(26,66)):'';"
        "e.textContent=I.fmt(v,18,2)+' votes'+(v===0n?"
        "(/^0x0*$/.test(to)?' \\u2014 you have never delegated, so it is zero':"
        "' \\u2014 delegated away to '+to.slice(0,10)):'')};"
        "onc('gdel',async()=>{await I.send(gt(),S.delegate+I.AD(I.acct()));"
        "I.say('delegation sent \\u00b7 it counts from the next block, and only for "
        "proposals that open after it','ok')});"
        "let sup=null;"
        "document.querySelectorAll('[data-support]').forEach(b=>"
        "b.addEventListener('click',()=>{sup=Number(b.dataset.support);"
        "const e=$('vsel');if(e)e.innerHTML='<div><span>your vote</span><b>'"
        "+(sup===1?'for':sup===0?'against':'abstain')+'</b></div>'}));"
        "document.querySelectorAll('[data-vote]').forEach(b=>"
        "b.addEventListener('click',()=>{const e=$('pid');if(e)e.value=b.dataset.vote}));"
        "onc('cast',async()=>{const id=val('pid');"
        "if(!/^\\d+$/.test(id))throw new Error('choose a proposal');"
        "if(sup===null)throw new Error('choose for, against or abstain');"
        "const r=await I.tryCall(gt(),S.votes+I.AD(I.acct()));"
        "if(r&&I.word(r,0)===0n)throw new Error('you have no voting power \\u2014 "
        "delegate first, and note that it will not count for proposals already open');"
        "await I.send(gg(),S.castVote+I.W(id)+I.W(sup))});"

        "I.chainOk().then(o=>{if(o&&I.pv()&&I.pv().request)"
        "I.pv().request({method:'eth_accounts'}).then(a=>{if(a&&a[0])"
        "I.connect().then(()=>{power();vshow()})})});"
        "})();";
}
