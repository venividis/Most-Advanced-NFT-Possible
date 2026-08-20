import { readFileSync } from "node:fs";
import { keccak256 } from "ethereum-cryptography/keccak.js";
const sel=(x)=>"0x"+Buffer.from(keccak256(Buffer.from(x,"utf8"))).toString("hex").slice(0,8);
const w=(n)=>BigInt(n).toString(16).padStart(64,"0");
const wa=(a)=>a.toLowerCase().replace("0x","").padStart(64,"0");
let proxied=null;
const F=async()=>{const p=process.env.HTTPS_PROXY; if(!proxied){const {fetch:uf,ProxyAgent}=await import("undici");
  const agent=new ProxyAgent({uri:p,requestTls:{ca:readFileSync("/root/.ccr/ca-bundle.crt")}});
  proxied=(u,o)=>uf(u,{...o,dispatcher:agent});} return proxied;};
const rpc=async(url,m,p=[])=>{for(let i=0;i<5;i++){try{const f=await F();
  const r=await f(url,{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({jsonrpc:"2.0",id:1,method:m,params:p})});
  const j=await r.json(); if(j.error) return {err:j.error.message}; return {ok:j.result};
 }catch(e){if(i===4)return{err:String(e.cause?.code||e.message)};await new Promise(r=>setTimeout(r,500*(i+1)));}}};
const EP="0x6f475642a6e85809b1c36fa62763669b1b48dd5b", CANON="0x1a44076050125825900e736c501f859c50fE728c";
const T=[[130,"https://mainnet.unichain.org",EP],[4663,"https://rpc.mainnet.chain.robinhood.com",EP],
         [1,"https://ethereum-rpc.publicnode.com",CANON],[8453,"https://mainnet.base.org",CANON],
         [42161,"https://arbitrum-one-rpc.publicnode.com",CANON]];
// read channel eids descend from 0xFFFFFFFF
const CHANS=[4294967295,4294967294,4294967293];
for(const [id,url,ep] of T){
 console.log(`\n### chain ${id}  endpoint ${ep}`);
 for(const c of CHANS){
  const s=await rpc(url,"eth_call",[{to:ep,data:sel("defaultSendLibrary(uint32)")+w(c)},"latest"]);
  const r=await rpc(url,"eth_call",[{to:ep,data:sel("defaultReceiveLibrary(uint32)")+w(c)},"latest"]);
  const sup=await rpc(url,"eth_call",[{to:ep,data:sel("isSupportedEid(uint32)")+w(c)},"latest"]);
  console.log(`  readChannel ${c}: supported=${sup.ok?(BigInt(sup.ok)?"YES":"no"):"ERR:"+sup.err}`+
    ` sendLib=${s.ok&&s.ok!=="0x"?"0x"+s.ok.slice(26):"—"} recvLib=${r.ok&&r.ok!=="0x"?"0x"+r.ok.slice(26):"—"}`);
 }
 // registered libraries
 const g=await rpc(url,"eth_call",[{to:ep,data:sel("getRegisteredLibraries()")},"latest"]);
 if(g.ok&&g.ok!=="0x"){const d=g.ok.slice(2);const n=parseInt(d.slice(64,128),16);
  const libs=[];for(let i=0;i<n;i++)libs.push("0x"+d.slice(128+i*64+24,128+(i+1)*64));
  console.log(`  registeredLibraries(${n}): ${libs.join(" ")}`);}
 else console.log(`  registeredLibraries: ${g.err||"—"}`);
}
