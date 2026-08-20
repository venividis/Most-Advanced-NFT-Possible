import { readFileSync } from "node:fs";
import { keccak256 } from "ethereum-cryptography/keccak.js";
const sel=x=>"0x"+Buffer.from(keccak256(Buffer.from(x,"utf8"))).toString("hex").slice(0,8);
const h=(n,b)=>BigInt(n).toString(16).padStart(b*2,"0");
const w=n=>BigInt(n).toString(16).padStart(64,"0"); const wa=a=>a.toLowerCase().replace(/^0x/,"").padStart(64,"0");
let P=null;const F=async()=>{if(!P){const{fetch:uf,ProxyAgent}=await import("undici");
 const ag=new ProxyAgent({uri:process.env.HTTPS_PROXY,requestTls:{ca:readFileSync("/root/.ccr/ca-bundle.crt")}});P=(u,o)=>uf(u,{...o,dispatcher:ag});}return P;};
const rpc=async(url,m,p=[])=>{for(let i=0;i<6;i++){try{const f=await F();
 const r=await f(url,{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({jsonrpc:"2.0",id:1,method:m,params:p})});
 const j=await r.json();if(j.error){if(/rate/i.test(j.error.message)&&i<5){await new Promise(x=>setTimeout(x,1500*(i+1)));continue;}return{err:j.error.message,data:j.error.data};}return{ok:j.result};
}catch(e){if(i===5)return{err:String(e.cause?.code||e.message)};await new Promise(x=>setTimeout(x,700*(i+1)));}}};
const URL="https://unichain.drpc.org", EP="0x6f475642a6e85809b1c36fa62763669b1b48dd5b";
const SENDER="0x000000000000000000000000000000000000dEaD";
const req=(eid,to,cd,label=0,conf=15)=>{const body=h(eid,4)+h(0,1)+h(0,8)+h(conf,2)+to.slice(2).toLowerCase()+cd;
 return h(1,1)+h(label,2)+h(1,2)+h(35+cd.length/2,2)+body;};
const cmdOf=(reqs,compute=null)=>"0x"+h(1,2)+h(0,2)+h(reqs.length,2)+reqs.join("")+
 (compute?h(1,1)+h(1,2)+h(compute.setting,1)+h(compute.eid,4)+h(0,1)+h(0,8)+h(15,2)+compute.to.slice(2).toLowerCase():"");
const readOpt=(gas,size)=>{const b=h(5,1)+h(gas,16)+h(size,4);return "0x"+h(3,2)+h(1,1)+h(b.length/2,2)+b;};
const quote=async(dstEid,msg,opts)=>{
 const M=msg.replace(/^0x/,""),O=opts.replace(/^0x/,"");
 const head=w(dstEid)+wa(SENDER)+w(160)+w(160+32+Math.ceil(M.length/64)*32)+w(0);
 const data=sel("quote((uint32,bytes32,bytes,bytes,bool),address)")+w(64)+wa(SENDER)+head+
   w(M.length/2)+M.padEnd(Math.ceil(M.length/64)*64,"0")+w(O.length/2)+O.padEnd(Math.ceil(O.length/64)*64,"0");
 return rpc(URL,"eth_call",[{to:EP,data},"latest"]);};
const TS=sel("totalSupply()").slice(2);
const TARGETS={30101:["Ethereum","0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"],30184:["Base","0x4200000000000000000000000000000000000006"],
 30110:["Arbitrum","0x82aF49447D8a07e3bd95BD0d56f35241523fBab1"],30102:["BNB","0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c"],
 30111:["Optimism","0x4200000000000000000000000000000000000006"],30109:["Polygon","0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270"],
 30320:["Unichain(self)","0x4200000000000000000000000000000000000006"],30416:["Robinhood","0x4200000000000000000000000000000000000006"],
 30362:["Berachain?","0x4200000000000000000000000000000000000006"],30258:["Sei?","0x4200000000000000000000000000000000000006"]};
console.log("=== which target chains can Unichain lzRead? (quote on channel 4294967295) ===");
const okEids=[];
for(const [eid,[nm,tok]] of Object.entries(TARGETS)){
 const r=await quote(4294967295, cmdOf([req(+eid,tok,TS)]), readOpt(200000,32));
 if(r.ok&&r.ok!=="0x"){const n=BigInt("0x"+r.ok.slice(2,66));okEids.push(+eid);
   console.log(`  ${String(eid).padEnd(6)} ${nm.padEnd(15)} READABLE  fee=${n} wei (${(Number(n)/1e18).toExponential(3)} ETH)`);}
 else console.log(`  ${String(eid).padEnd(6)} ${nm.padEnd(15)} no  (${(r.data||"").slice(0,10)||r.err})`);
}
console.log("\n=== fee scaling: N requests in ONE command (targets "+okEids.slice(0,4)+") ===");
for(const n of [1,2,3,4,6,8]){
 const rs=[];for(let i=0;i<n;i++){const e=okEids[i%okEids.length];rs.push(req(e,TARGETS[e][1],TS,i));}
 const r=await quote(4294967295,cmdOf(rs),readOpt(200000,32*n));
 if(r.ok&&r.ok!=="0x"){const f=BigInt("0x"+r.ok.slice(2,66));console.log(`  ${n} reads: ${f} wei  (${(Number(f)/1e18).toExponential(3)} ETH, ${(Number(f)/n/1e18).toExponential(3)}/read)`);}
 else console.log(`  ${n} reads: ${(r.data||"").slice(0,10)||r.err}`);
}
console.log("\n=== with lzReduce (compute setting 2 = map+reduce, resolved on Unichain) ===");
for(const s of [0,1,2,3]){
 const rs=okEids.slice(0,3).map((e,i)=>req(e,TARGETS[e][1],TS,i));
 const c = s===3?null:{setting:s,eid:30320,to:SENDER};
 const r=await quote(4294967295,cmdOf(rs,c),readOpt(300000,32));
 console.log(`  computeSetting=${s} (${["map","reduce","map+reduce","none"][s]}): ${r.ok&&r.ok!=="0x"?BigInt("0x"+r.ok.slice(2,66))+" wei":((r.data||"").slice(0,10)||r.err)}`);
}
