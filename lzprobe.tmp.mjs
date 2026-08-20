import { readFileSync, existsSync } from "node:fs";
let proxied=null;
const F=async(url)=>{const p=process.env.HTTPS_PROXY||process.env.https_proxy;
 if(!p) return fetch;
 if(!proxied){const {fetch:uf,ProxyAgent}=await import("undici");
  const ca="/root/.ccr/ca-bundle.crt";
  const agent=new ProxyAgent({uri:p,requestTls:existsSync(ca)?{ca:readFileSync(ca)}:undefined});
  proxied=(u,o)=>uf(u,{...o,dispatcher:agent});}
 return proxied;};
const rpc=async(url,method,params=[])=>{
 for(let i=0;i<4;i++){try{
  const f=await F(url);
  const r=await f(url,{method:"POST",headers:{"Content-Type":"application/json"},
   body:JSON.stringify({jsonrpc:"2.0",id:1,method,params})});
  const j=await r.json(); if(j.error) return {err:j.error.message}; return {ok:j.result};
 }catch(e){ if(i===3) return {err:String(e.cause?.code||e.message)}; await new Promise(r=>setTimeout(r,400*(i+1)));}}};

const CHAINS={
 130:  ["unichain", ["https://mainnet.unichain.org","https://unichain-rpc.publicnode.com","https://unichain.drpc.org"]],
 4663: ["robinhood",["https://rpc.mainnet.chain.robinhood.com"]],
 8453: ["base",     ["https://mainnet.base.org"]],
 1:    ["ethereum", ["https://ethereum-rpc.publicnode.com"]],
 42161:["arbitrum", ["https://arbitrum-one-rpc.publicnode.com"]],
};
// selectors precomputed (keccak4)
const SEL={ eid:"0xb353aaa7", // eid()
            getSendLibrary:"0x6a14d715", // getSendLibrary(address,uint32)
            defaultReceiveLibrary:"0xdc93c8a2",
            isSupportedEid:"0xd4b4ec8f", // isSupportedEid(uint32)
            messageLibType:"0x1e30c6c5" // messageLibType()
          };
const ADDRS = process.argv.slice(3);
const cid = process.argv[2];

const run=async()=>{
 for(const [id,[name,urls]] of Object.entries(CHAINS)){
  if(cid && cid!=="all" && String(id)!==cid) continue;
  let url=null, chainOk=null;
  for(const u of urls){ const r=await rpc(u,"eth_chainId"); if(r.ok){url=u;chainOk=Number(r.ok);break;} }
  console.log(`\n### ${name} (${id})  rpc=${url||"NONE REACHABLE"} reportedChainId=${chainOk}`);
  if(!url) continue;
  for(const a of ADDRS){
   const c=await rpc(url,"eth_getCode",[a,"latest"]);
   const sz = c.ok? (c.ok.length-2)/2 : -1;
   let extra="";
   if(sz>0){
     const e=await rpc(url,"eth_call",[{to:a,data:SEL.eid},"latest"]);
     if(e.ok && e.ok!=="0x") extra += ` eid()=${parseInt(e.ok,16)}`;
     const t=await rpc(url,"eth_call",[{to:a,data:SEL.messageLibType},"latest"]);
     if(t.ok && t.ok!=="0x") extra += ` messageLibType=${parseInt(t.ok,16)}`;
   }
   console.log(`  ${a}  ${sz<0?("ERR "+c.err):(sz+" B")}${extra}`);
  }
 }
};
run();
