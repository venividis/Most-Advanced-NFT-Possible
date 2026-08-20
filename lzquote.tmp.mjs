import { readFileSync } from "node:fs";
import { keccak256 } from "ethereum-cryptography/keccak.js";
const sel=(x)=>"0x"+Buffer.from(keccak256(Buffer.from(x,"utf8"))).toString("hex").slice(0,8);
const h=(n,bytes)=>BigInt(n).toString(16).padStart(bytes*2,"0");
const w=(n)=>BigInt(n).toString(16).padStart(64,"0"); const wa=a=>a.toLowerCase().replace(/^0x/,"").padStart(64,"0");
let P=null;const F=async()=>{if(!P){const{fetch:uf,ProxyAgent}=await import("undici");
 const ag=new ProxyAgent({uri:process.env.HTTPS_PROXY,requestTls:{ca:readFileSync("/root/.ccr/ca-bundle.crt")}});P=(u,o)=>uf(u,{...o,dispatcher:ag});}return P;};
const rpc=async(url,m,p=[])=>{for(let i=0;i<6;i++){try{const f=await F();
 const r=await f(url,{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({jsonrpc:"2.0",id:1,method:m,params:p})});
 const j=await r.json();if(j.error){if(/rate/i.test(j.error.message)&&i<5){await new Promise(x=>setTimeout(x,1500*(i+1)));continue;}return{err:j.error.message,data:j.error.data};}return{ok:j.result};
}catch(e){if(i===5)return{err:String(e.cause?.code||e.message)};await new Promise(x=>setTimeout(x,700*(i+1)));}}};

// ---- build a v1 read command: read WETH.totalSupply() on Ethereum (eid 30101)
const WETH_ETH="0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";
const callData=sel("totalSupply()").slice(2);           // 4 bytes
const reqBody = h(30101,4)+h(0,1)+h(0,8)+h(15,2)+WETH_ETH.slice(2).toLowerCase()+callData;
const requestSize = 35 + callData.length/2;
const request = h(1,1)+h(0,2)+h(1,2)+h(requestSize,2)+reqBody;  // ver, appReqLabel, resolverType=1, size, body
const cmd = "0x"+h(1,2)+h(0,2)+h(1,2)+request;                   // cmdVersion=1, appCmdLabel=0, requestCount=1

// options type3: 0x0003 | workerId 1 | size | optType 1 (lzReceive) | gas(uint128) | value(uint128)
// option type 5 = LZREAD : gas(uint128) + calldataSize(uint32) [+ value(uint128)]
const lzReadOpt=(gas,size)=>{const params=h(gas,16)+h(size,4); const body=h(5,1)+params;
  return "0x"+h(3,2)+h(1,1)+h(body.length/2,2)+body;};
const lzRecvOpt=(gas)=>{const body=h(1,1)+h(gas,16); return "0x"+h(3,2)+h(1,1)+h(body.length/2,2)+body;};
const OPTS = lzReadOpt(200000, 32);

const EP="0x6f475642a6e85809b1c36fa62763669b1b48dd5b";
const URL=process.env.U || "https://unichain.drpc.org";
const SENDER="0x000000000000000000000000000000000000dEaD";
const quote=async(dstEid,receiver,message,options,sender)=>{
 // quote((uint32,bytes32,bytes,bytes,bool),address)
 const msgHex=message.replace(/^0x/,""), optHex=options.replace(/^0x/,"");
 const head=w(dstEid)+wa(receiver)+w(160)+w(160+32+Math.ceil(msgHex.length/64)*32)+w(0);
 const msgPart=w(msgHex.length/2)+msgHex.padEnd(Math.ceil(msgHex.length/64)*64,"0");
 const optPart=w(optHex.length/2)+optHex.padEnd(Math.ceil(optHex.length/64)*64,"0");
 const data=sel("quote((uint32,bytes32,bytes,bytes,bool),address)")+w(64)+wa(sender)+head+msgPart+optPart;
 return rpc(URL,"eth_call",[{to:EP,data},"latest"]);
};
console.log("read cmd:",cmd,"\noptions:",OPTS,"\n");
for(const ch of [4294967295,4294967294]){
 const r=await quote(ch,SENDER,cmd,OPTS,SENDER);
 if(r.ok&&r.ok!=="0x"){const nat=BigInt("0x"+r.ok.slice(2,66)),lz=BigInt("0x"+r.ok.slice(66,130));
  console.log(`lzRead quote on channel ${ch}: nativeFee=${nat} wei (${Number(nat)/1e18} ETH)  lzTokenFee=${lz}`);}
 else console.log(`lzRead quote channel ${ch}: ${r.err} ${r.data||""}`);
}
console.log("\n--- ordinary message quote, unichain -> Base (30184), default (DeadDVN) config ---");
const q=await quote(30184,SENDER,"0x"+"aa".repeat(64),lzRecvOpt(200000),SENDER);
if(q.ok&&q.ok!=="0x"){console.log("nativeFee=",BigInt("0x"+q.ok.slice(2,66)).toString());}
else console.log("REVERT:",q.err, q.data?("data="+q.data):"");
