#!/usr/bin/env node
/*───────────────────────────────────────────────────────────────────────────
  IPSEITY · replacing the site without ending the conversation

  The pages are the mutable-ish half of the system: replacing them means
  deploying new page contracts and a new Premises, and pointing whatever
  name you use at the new address. Two things are deliberately NOT
  replaced: the collection (obviously), and the Parley — every message
  ever sent is a log that contract emitted, and a new Parley would not
  migrate the conversation, it would end it.

      node tools/redeploy-site.mjs deployments/base-sepolia.json
───────────────────────────────────────────────────────────────────────────*/
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { compile, artifact } from "./compile.mjs";
import { RpcChain } from "./rpc.mjs";
import { deploySite, getter } from "./site.mjs";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const recPath = process.argv[2];
if (!recPath) throw new Error("which deployment? pass its record file");
const rec = JSON.parse(fs.readFileSync(recPath, "utf8"));

const c = await RpcChain.open(rec.rpc, fs.readFileSync(path.join(ROOT, ".testnet-key"), "utf8").trim());
console.log(`\n  chain ${c.chainId} · deployer ${c.from.toString()}`);
console.log(`  keeping Parley ${rec.contracts.parley} — the conversation survives\n`);

const out = compile({ quiet: true, dirs: ["src", "test/mocks"] });
const A = (f, n) => artifact(out, f, n);

const site = await deploySite(c, A, {
  hub: rec.contracts.ipseity,
  pool: rec.contracts.pool,
  lease: rec.contracts.lease,
  sigil: rec.contracts.sigil,
  parley: rec.contracts.parley
});

rec.contracts = { ...rec.contracts, ...site, parley: rec.contracts.parley };
const tail = c.chainId === 1 ? "" : ":" + c.chainId;
rec.urls = {
  door: `web3://${site.premises}${tail}/`,
  terminal: `web3://${site.premises}${tail}/terminal`,
  chat: `web3://${site.premises}${tail}/chat`
};
fs.writeFileSync(recPath, JSON.stringify(rec, null, 1));
fs.writeFileSync(path.join(ROOT, "dist/testnet.json"), JSON.stringify(rec, null, 1));

const GET = getter(c, site.premises);
for (const p of [[], ["terminal"], ["chat"], ["agora"], ["gallery"], ["coins"], ["charts"]]) {
  const r = await GET(p);
  console.log(`  ${r.status} /${p.join("/")}  ${r.body.length}B`);
  if (r.status !== 200) process.exit(1);
}
console.log(`\n  Premises ${site.premises}`);
console.log(`  ${rec.urls.door}\n`);
