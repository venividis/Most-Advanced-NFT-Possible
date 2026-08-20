import { readFileSync } from "node:fs";
import { keccak256 } from "ethereum-cryptography/keccak.js";
const sel=(x)=>"0x"+Buffer.from(keccak256(Buffer.from(x,"utf8"))).toString("hex").slice(0,8);
const w=(n)=>BigInt(n).toString(16).padStart(64,"0"); const wa=(a)=>a.toLowerCase().replace(/^0x/,"").padStart(64,"0");
let P=null; const F=async()=>{if(!P){const {fetch:uf,ProxyAgent}=await import("undici");
 const ag=new ProxyAgent({uri:process.env.HTTPS_PROXY,requestTls:{ca:readFileSync("/root/.ccr/ca-bundle.crt")}}); P=(u,o)=>uf(u,{...o,dispatcher:ag});}return P;};
const rpc=async(url,m,p=[])=>{for(let i=0;i<6;i++){try{const f=await F();
 const r=await f(url,{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({jsonrpc:"2.0",id:1,method:m,params:p})});
 const j=await r.json(); if(j.error){if(/rate/i.test(j.error.message)&&i<5){await new Promise(x=>setTimeout(x,1500*(i+1)));continue;}return{err:j.error.message};}return{ok:j.result};
}catch(e){if(i===5)return{err:String(e.cause?.code||e.message)};await new Promise(x=>setTimeout(x,700*(i+1)));}}};
const unwrap=(hex)=>{const d=hex.slice(2);const o=parseInt(d.slice(0,64),16)*2;const l=parseInt(d.slice(o,o+64),16)*2;return d.slice(o+64,o+64+l);};
const M=JSON.parse(readFileSync("/tmp/claude-0/-home-user-Most-Advanced-NFT-Possible/c08c200c-e735-5437-9945-fe03b4c92d76/scratchpad/meta_d2f716.json","utf8"));
const nm=(k,a)=>{const d=M[k]?.dvns?.[a.toLowerCase()];return d?`${d.canonicalName}${d.lzReadCompatible?"[READ]":""}${d.deprecated?"(deprecated)":""}`:a;};
const EP={130:"0x6f475642a6e85809b1c36fa62763669b1b48dd5b",4663:"0x6f475642a6e85809b1c36fa62763669b1b48dd5b",
          1:"0x1a44076050125825900e736c501f859c50fE728c",8453:"0x1a44076050125825900e736c501f859c50fE728c"};
const getCfg=(url,ep,lib,eid,ct)=>rpc(url,"eth_call",[{to:ep,data:sel("getConfig(address,address,uint32,uint32)")+wa("0x"+"0".repeat(40))+wa(lib)+w(eid)+w(ct)},"latest"]);
const decRead=(b)=>{const base=parseInt(b.slice(0,64),16)*2;const s=b.slice(base);const g=i=>s.slice(i*64,(i+1)*64);
 const arr=p=>{const o=parseInt(p,16)*2;const n=parseInt(s.slice(o,o+64),16);const r=[];for(let i=0;i<n;i++)r.push("0x"+s.slice(o+64+i*64+24,o+64+(i+1)*64));return r;};
 return{executor:"0x"+g(0).slice(24),req:parseInt(g(1),16),opt:parseInt(g(2),16),thr:parseInt(g(3),16),reqD:arr(g(4)),optD:arr(g(5))};};
const decUln=(b)=>{const base=parseInt(b.slice(0,64),16)*2;const s=b.slice(base);const g=i=>s.slice(i*64,(i+1)*64);
 const arr=p=>{const o=parseInt(p,16)*2;const n=parseInt(s.slice(o,o+64),16);const r=[];for(let i=0;i<n;i++)r.push("0x"+s.slice(o+64+i*64+24,o+64+(i+1)*64));return r;};
 return{conf:parseInt(g(0),16),req:parseInt(g(1),16),opt:parseInt(g(2),16),thr:parseInt(g(3),16),reqD:arr(g(4)),optD:arr(g(5))};};

console.log("### READ-CHANNEL default ReadLibConfig (configType 1)");
for(const [key,id,url,readLib] of [["unichain",130,"https://mainnet.unichain.org","0x178f93794328c04988bcd52a1b820ec105b17f2f"],
   ["ethereum",1,"https://ethereum-rpc.publicnode.com","0x74f55bc2a79a27a0bf1d1a35db5d0fc36b9fdb9d"]]){
 for(const ch of [4294967295,4294967294,4294967293]){
  const r=await getCfg(url,EP[id],readLib,ch,1);
  if(r.ok&&r.ok!=="0x"){const c=decRead(unwrap(r.ok));
   console.log(` ${key} ch${ch}: executor=${c.executor}\n    requiredDVNs(${c.req}): ${c.reqD.map(a=>nm(key,a)).join(" + ")||"—"}\n    optionalDVNs(${c.opt}, thr ${c.thr}): ${c.optD.map(a=>nm(key,a)).join(" + ")||"none"}`);}
  else console.log(` ${key} ch${ch}: ${r.err||"empty"}`);
 }
}
console.log("\n### COMPARISON: default send ULN config, Ethereum -> Unichain/Base");
for(const eid of [30320,30184,30416]){
 const u=await getCfg("https://ethereum-rpc.publicnode.com",EP[1],"0xbb2ea70c9e858123480642cf96acbcce1372dce1",eid,2);
 if(u.ok&&u.ok!=="0x"){const c=decUln(unwrap(u.ok));
  console.log(` ETH->eid ${eid}: conf=${c.conf} required(${c.req}): ${c.reqD.map(a=>nm("ethereum",a)).join(" + ")||"—"} | optional(${c.opt},thr ${c.thr}): ${c.optD.map(a=>nm("ethereum",a)).join(" + ")||"none"}`);}
 else console.log(` ETH->eid ${eid}: ${u.err||"empty"}`);
}
// DeadDVN behaviour
console.log("\n### DeadDVN probe on unichain");
const DEAD="0x6788f52439aca6bff597d3eec2dc9a44b8fee842";
const c=await rpc("https://mainnet.unichain.org","eth_getCode",[DEAD,"latest"]);
console.log(" codeSize:",(c.ok.length-2)/2,"B  bytecode:",c.ok);
