import { readFileSync, existsSync } from "node:fs";
import { keccak256 } from "ethereum-cryptography/keccak.js";
const sel=(x)=>"0x"+Buffer.from(keccak256(Buffer.from(x,"utf8"))).toString("hex").slice(0,8);
const w=(n)=>BigInt(n).toString(16).padStart(64,"0");
let proxied=null;
const F=async()=>{const p=process.env.HTTPS_PROXY||process.env.https_proxy; if(!p) return fetch;
 if(!proxied){const {fetch:uf,ProxyAgent}=await import("undici");
  const agent=new ProxyAgent({uri:p,requestTls:{ca:readFileSync("/root/.ccr/ca-bundle.crt")}});
  proxied=(u,o)=>uf(u,{...o,dispatcher:agent});} return proxied;};
const rpc=async(url,method,params=[])=>{ for(let i=0;i<4;i++){ try{
  const f=await F(); const r=await f(url,{method:"POST",headers:{"Content-Type":"application/json"},
   body:JSON.stringify({jsonrpc:"2.0",id:1,method,params})});
  const j=await r.json(); if(j.error) return {err:j.error.message}; return {ok:j.result};
 }catch(e){ if(i===3) return {err:String(e.cause?.code||e.message)}; await new Promise(r=>setTimeout(r,400*(i+1)));}}};

const EP="0x6f475642a6e85809b1c36fa62763669b1b48dd5b";
const CH={130:"https://mainnet.unichain.org",4663:"https://rpc.mainnet.chain.robinhood.com",
          8453:"https://mainnet.base.org",1:"https://ethereum-rpc.publicnode.com"};
const CANON="0x1a44076050125825900e736c501f859c50fE728c";
for(const [id,url] of Object.entries(CH)){
 console.log(`\n#### chain ${id}`);
 for(const [label,addr] of [["metadata-EP",EP],["canonical-EP",CANON]]){
  const c=await rpc(url,"eth_getCode",[addr,"latest"]);
  const sz=c.ok?(c.ok.length-2)/2:-1;
  if(sz<=0){ console.log(`  ${label} ${addr}: ${sz===0?"NO CODE":"ERR "+c.err}`); continue; }
  const e=await rpc(url,"eth_call",[{to:addr,data:sel("eid()")},"latest"]);
  const eid = e.ok&&e.ok!=="0x" ? parseInt(e.ok,16) : null;
  console.log(`  ${label} ${addr}: ${sz} B  eid()=${eid===null?("no/revert "+(e.err||"")):eid}`);
  if(eid===null) continue;
  // supported eids + read channel
  for(const q of [30101,30184,30110,30320,30416,4294967295]){
   const r=await rpc(url,"eth_call",[{to:addr,data:sel("isSupportedEid(uint32)")+w(q)},"latest"]);
   process.stdout.write(`    isSupportedEid(${q})=${r.ok?(BigInt(r.ok)?"YES":"no"):"ERR"}  `);
  }
  console.log("");
  for(const q of [30101,30184,30320,30416]){
   const r=await rpc(url,"eth_call",[{to:addr,data:sel("defaultSendLibrary(uint32)")+w(q)},"latest"]);
   console.log(`    defaultSendLibrary(${q}) = ${r.ok&&r.ok!=="0x"?"0x"+r.ok.slice(26):"REVERT/none"}`);
  }
  const rt=await rpc(url,"eth_call",[{to:addr,data:sel("READ_CHANNEL_EID_THRESHOLD()")},"latest"]);
  console.log(`    READ_CHANNEL_EID_THRESHOLD = ${rt.ok&&rt.ok!=="0x"?parseInt(rt.ok,16):"absent ("+(rt.err||"0x")+")"}`);
  const lz=await rpc(url,"eth_call",[{to:addr,data:sel("lzToken()")},"latest"]);
  console.log(`    lzToken = ${lz.ok&&lz.ok!=="0x"?"0x"+lz.ok.slice(26):"absent"}`);
 }
}
