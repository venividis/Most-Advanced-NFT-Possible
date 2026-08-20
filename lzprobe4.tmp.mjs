import { readFileSync } from "node:fs";
import { keccak256 } from "ethereum-cryptography/keccak.js";
const sel=(x)=>"0x"+Buffer.from(keccak256(Buffer.from(x,"utf8"))).toString("hex").slice(0,8);
const w=(n)=>BigInt(n).toString(16).padStart(64,"0");
const wa=(a)=>a.toLowerCase().replace(/^0x/,"").padStart(64,"0");
let P=null; const F=async()=>{ if(!P){const {fetch:uf,ProxyAgent}=await import("undici");
 const ag=new ProxyAgent({uri:process.env.HTTPS_PROXY,requestTls:{ca:readFileSync("/root/.ccr/ca-bundle.crt")}});
 P=(u,o)=>uf(u,{...o,dispatcher:ag});} return P;};
const rpc=async(url,m,p=[])=>{for(let i=0;i<6;i++){try{const f=await F();
 const r=await f(url,{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({jsonrpc:"2.0",id:1,method:m,params:p})});
 const j=await r.json(); if(j.error){ if(/rate/i.test(j.error.message)&&i<5){await new Promise(r=>setTimeout(r,1500*(i+1)));continue;} return {err:j.error.message};} return {ok:j.result};
}catch(e){if(i===5)return{err:String(e.cause?.code||e.message)};await new Promise(r=>setTimeout(r,700*(i+1)));}}};

// getConfig(address oapp, address lib, uint32 eid, uint32 configType) -> bytes
const getCfg=async(url,ep,lib,eid,ct)=>{
 const data=sel("getConfig(address,address,uint32,uint32)")+wa("0x0000000000000000000000000000000000000000")+wa(lib)+w(eid)+w(ct);
 return rpc(url,"eth_call",[{to:ep,data},"latest"]);
};
const decExec=(hex)=>{const d=hex.slice(2); const off=parseInt(d.slice(0,64),16)*2; const len=parseInt(d.slice(off,off+64),16)*2;
 const b=d.slice(off+64,off+64+len); return {maxMessageSize:parseInt(b.slice(0,64),16), executor:"0x"+b.slice(64+24,128)};};
const decUln=(hex)=>{const d=hex.slice(2); const off=parseInt(d.slice(0,64),16)*2; const len=parseInt(d.slice(off,off+64),16)*2;
 const b=d.slice(off+64,off+64+len);
 const conf=parseInt(b.slice(0,64),16), rc=parseInt(b.slice(64,128),16), oc=parseInt(b.slice(128,192),16), ot=parseInt(b.slice(192,256),16);
 const rOff=parseInt(b.slice(256,320),16)*2, oOff=parseInt(b.slice(320,384),16)*2;
 const rd=[],od=[];
 const rn=parseInt(b.slice(rOff,rOff+64),16); for(let i=0;i<rn;i++) rd.push("0x"+b.slice(rOff+64+i*64+24,rOff+64+(i+1)*64));
 const on=parseInt(b.slice(oOff,oOff+64),16); for(let i=0;i<on;i++) od.push("0x"+b.slice(oOff+64+i*64+24,oOff+64+(i+1)*64));
 return {confirmations:conf, requiredDVNCount:rc, optionalDVNCount:oc, optionalDVNThreshold:ot, requiredDVNs:rd, optionalDVNs:od};};

const M=JSON.parse(readFileSync("/tmp/claude-0/-home-user-Most-Advanced-NFT-Possible/c08c200c-e735-5437-9945-fe03b4c92d76/scratchpad/meta_d2f716.json","utf8"));
const dvnName=(chainKey,a)=>{const d=M[chainKey]?.dvns?.[a.toLowerCase()]; return d?`${d.canonicalName}${d.lzReadCompatible?" [lzRead]":""}`:"unknown";};

const EP="0x6f475642a6e85809b1c36fa62763669b1b48dd5b";
const T=[
 ["unichain",130,"https://mainnet.unichain.org",EP,"0xc39161c743d0307eb9bcc9fef03eeb9dc4802de7","0x178f93794328c04988bcd52a1b820ec105b17f2f"],
 ["robinhood",4663,"https://rpc.mainnet.chain.robinhood.com",EP,"0xc39161c743d0307eb9bcc9fef03eeb9dc4802de7",null],
];
for(const [key,id,url,ep,sendLib,readLib] of T){
 console.log(`\n=========== ${key} (${id})`);
 for(const eid of [30101,30184,30110,30320,30416]){
  const e=await getCfg(url,ep,sendLib,eid,1), u=await getCfg(url,ep,sendLib,eid,2);
  if(e.err||!e.ok||e.ok==="0x"){console.log(`  eid ${eid}: no default config (${e.err||"empty"})`);continue;}
  const ec=decExec(e.ok);
  console.log(`  --> to eid ${eid}: maxMessageSize=${ec.maxMessageSize} bytes  executor=${ec.executor}`);
  if(u.ok&&u.ok!=="0x"){const uc=decUln(u.ok);
   console.log(`      confirmations=${uc.confirmations} requiredDVNs(${uc.requiredDVNCount}): ${uc.requiredDVNs.map(a=>a+" ("+dvnName(key,a)+")").join(", ")}`);
   console.log(`      optionalDVNs(${uc.optionalDVNCount}, threshold ${uc.optionalDVNThreshold}): ${uc.optionalDVNs.map(a=>a+" ("+dvnName(key,a)+")").join(", ")||"none"}`);}
 }
 if(readLib){
  console.log(`  --- READ CHANNEL (lzRead) via ${readLib}`);
  for(const ch of [4294967295,4294967294,4294967293]){
   const e=await getCfg(url,ep,readLib,ch,1);
   const r=await getCfg(url,ep,readLib,ch,2); // READ config type may differ
   if(e.ok&&e.ok!=="0x"){const ec=decExec(e.ok);console.log(`      channel ${ch}: maxMessageSize=${ec.maxMessageSize} executor=${ec.executor}`);}
   else console.log(`      channel ${ch}: exec cfg ${e.err||"empty"}`);
  }
 }
}
