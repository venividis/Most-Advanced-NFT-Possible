#!/usr/bin/env node
/*───────────────────────────────────────────────────────────────────────────
  IPSEITY · the gas budget, measured against the caps that actually exist

  A view function costs nobody any ether. That is exactly why it is easy to
  write one nobody can call. `eth_call` is executed by a node, and every
  node puts a ceiling on how much work it will do for a call it is not
  being paid for:

    geth           --rpc.gascap          50,000,000   (its default)
    erigon         --rpc.gascap          50,000,000
    nethermind     JsonRpc.GasCap        100,000,000
    reth           --rpc.gascap          50,000,000
    hosted RPC     varies, and is often much lower

  So the number that matters for tokenURI() is not the block gas limit. It
  is the smallest gascap on the path between a wallet and this contract,
  and past that ceiling the call does not return an error about gas — it
  returns "out of gas", which reads to a marketplace as a broken token.

  This measures every read path against those ceilings and says which of
  them are reachable from where. It runs in `npm run check`, so a change
  that pushes a face over a cap is caught in the commit that does it,
  rather than by a user whose wallet renders a grey square.

    node tools/gas.mjs
    node tools/gas.mjs --json        machine-readable, for CI
───────────────────────────────────────────────────────────────────────────*/
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { compile, artifact } from "./compile.mjs";
import { Chain, enc, sel, encodeAddressArg } from "./evm.mjs";
import { createAddressFromString, hexToBytes, bytesToHex } from "@ethereumjs/util";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const JSON_OUT = process.argv.includes("--json");
const REGISTRY = "0x000000006551c19487814612e58FE06813775758";

/*  The ceilings, cheapest first. "reachable" means every node at or above
    this cap will run the call; below it, the call fails.                 */
const CAPS = [
  { at: 10_000_000n,  who: "a cautious hosted RPC" },
  { at: 30_000_000n,  who: "a node capped at one block" },
  { at: 50_000_000n,  who: "geth, erigon and reth, at their defaults" },
  { at: 100_000_000n, who: "nethermind, at its default" }
];
const FLOOR = CAPS[2].at;          // the one that decides "works by default"

const M = (n) => (Number(n) / 1e6).toFixed(2) + "M";
const head = (s) => console.log(`\n  \x1b[1m${s}\x1b[0m`);

/*──────────────────── a world with one token in it ────────────────────*/
const plan = (() => {
  const p = path.join(ROOT, "dist/shards.json");
  if (!fs.existsSync(p)) throw new Error("run tools/build-engine.mjs first");
  return JSON.parse(fs.readFileSync(p, "utf8"));
})();

const out = compile({ quiet: true, dirs: ["src", "test/mocks"] });
const A = {
  Engine:   artifact(out, "src/Engine.sol", "Engine"),
  Sigil:    artifact(out, "src/Sigil.sol", "Sigil"),
  Renderer: artifact(out, "src/Renderer.sol", "Renderer"),
  Ipseity:  artifact(out, "src/Ipseity.sol", "Ipseity"),
  Registry: artifact(out, "test/mocks/ERC6551Registry.sol", "ERC6551Registry"),
  Account:  artifact(out, "src/IpseityAccount.sol", "IpseityAccount"),
  Grip:     artifact(out, "src/GripVault.sol", "GripVault")
};

if (!JSON_OUT) console.log("\n  \x1b[1mIPSEITY · the gas budget\x1b[0m");

const c = await Chain.open();
const tmp = await c.deploy(A.Registry.bytecode, "", "registry");
await c.vm.stateManager.putCode(
  createAddressFromString(REGISTRY),
  await c.vm.stateManager.getCode(createAddressFromString(tmp)));

const engine = await c.deploy(A.Engine.bytecode, "0".repeat(63) + "1", "Engine");
const sigil = await c.deploy(A.Sigil.bytecode, "", "Sigil");
const renderer = await c.deploy(
  A.Renderer.bytecode, encodeAddressArg(engine) + encodeAddressArg(sigil), "Renderer");
const nft = await c.deploy(A.Ipseity.bytecode,
  encodeAddressArg(renderer) +
  encodeAddressArg(await c.deploy(A.Account.bytecode, "", "acct")) +
  encodeAddressArg(await c.deploy(A.Grip.bytecode, "", "grip")), "Ipseity");

for (const s of plan.head) await c.exec(engine, "loadHead(bytes)", [s.data]);
for (const s of plan.body) await c.exec(engine, "loadBody(bytes)", [s.data]);
await c.exec(engine, "setInflatedSize(uint32)", [plan.inflatedSize]);
await c.exec(engine, "freeze()", []);
await c.exec(nft, "mint()", [], { value: 10n ** 16n });

/*  Gas is measured on the call itself, not on a transaction wrapping it,
    because eth_call is what a wallet actually issues — no 21,000 intrinsic
    cost, no calldata pricing, just the execution.                        */
async function measure(to, sig, args = []) {
  const res = await c.vm.evm.runCall({
    to: createAddressFromString(to),
    caller: createAddressFromString(c.from.toString()),
    origin: createAddressFromString(c.from.toString()),
    data: hexToBytes(enc(sig, args)), gasLimit: 3_000_000_000n, value: 0n,
    block: (await import("./evm.mjs")).BLOCK
  });
  if (res.execResult.exceptionError) {
    return { gas: null, bytes: 0, err: res.execResult.exceptionError.error };
  }
  return {
    gas: res.execResult.executionGasUsed,
    bytes: (res.execResult.returnValue || new Uint8Array()).length
  };
}

const READS = [
  ["tokenURI(uint256)",              [1],    "the pinned face — what every wallet calls"],
  ["tokenURIAt(uint256,uint256)",    [1, 0], "face 0, the instrument: the whole GUI"],
  ["tokenURIAt(uint256,uint256)",    [1, 1], "face 1, the still: one sigil"],
  ["tokenURIAt(uint256,uint256)",    [1, 2], "face 2, the quartet: four sigils"],
  ["tokenURIs(uint256)",             [1],    "ERC-7160: every face at once"],
  ["contractURI()",                  [],     "ERC-7572: collection metadata"],
  ["viewOf(uint256)",                [1],    "the state the engine reads"],
  ["ownerOf(uint256)",               [1],    "plain ERC-721"]
];

const rows = [];
for (const [sig, args, note] of READS) {
  const r = await measure(nft, sig, args);
  const label = sig.startsWith("tokenURIAt")
    ? `tokenURIAt(id,${args[1]})` : sig.replace(/\(.*/, "()");
  rows.push({ label, sig, note, ...r });
}

/*──────────────────── the ERC-5219 path, for comparison ────────────────────*/
/*  Premises serves the same page over ERC-5219 without the base64 data:
    URI wrapper. It is worth measuring beside tokenURI because it is the
    cheaper route to an identical document, and the one a web3:// gateway
    or a 5219-aware wallet will take.                                     */
let premises = null;
{
  const P = artifact(out, "src/Premises.sol", "Premises");
  const addr = await c.deploy(P.bytecode, encodeAddressArg(nft), "Premises");
  /*  Two dynamic arrays in the head; the shared encoder in evm.mjs does
      not do string[], so the calldata is laid out here.                */
  const w = (n) => BigInt(n).toString(16).padStart(64, "0");
  const encStr = (str) => {
    const h = Buffer.from(str, "utf8").toString("hex");
    return w(str.length) + h.padEnd(Math.ceil(h.length / 64) * 64, "0");
  };
  const parts = ["token", "1", "live"].map(encStr);
  let off = parts.length * 32, heads = "";
  for (const b of parts) { heads += w(off); off += b.length / 2; }
  const res = w(parts.length) + heads + parts.join("");
  const data = sel("request(string[],(string,string)[])") +
               w(0x40) + w(0x40 + res.length / 2) + res + w(0);
  const rr = await c.vm.evm.runCall({
    to: createAddressFromString(addr), caller: createAddressFromString(c.from.toString()),
    origin: createAddressFromString(c.from.toString()),
    data: hexToBytes(data), gasLimit: 3_000_000_000n, value: 0n,
    block: (await import("./evm.mjs")).BLOCK
  });
  premises = rr.execResult.exceptionError
    ? { err: rr.execResult.exceptionError.error }
    : { gas: rr.execResult.executionGasUsed, bytes: rr.execResult.returnValue.length };
}

/*──────────────────── report ────────────────────*/
const over = rows.filter((r) => r.gas !== null && r.gas > FLOOR);

if (JSON_OUT) {
  console.log(JSON.stringify({
    floor: String(FLOOR),
    rows: rows.map((r) => ({ ...r, gas: r.gas === null ? null : String(r.gas) })),
    overFloor: over.map((r) => r.label)
  }, null, 2));
} else {
  head("what a read costs, and who will run it");
  console.log("      \x1b[2m" + "call".padEnd(24) + "gas".padStart(9) +
              "  returned".padStart(11) + "   runs on\x1b[0m");
  for (const r of rows) {
    if (r.gas === null) {
      console.log(`      ${r.label.padEnd(24)}${"reverted".padStart(9)}  ${r.err}`);
      continue;
    }
    const runs = CAPS.filter((k) => r.gas <= k.at);
    const colour = r.gas > FLOOR ? "\x1b[31m" : r.gas > CAPS[0].at ? "\x1b[33m" : "\x1b[32m";
    const where = runs.length === CAPS.length ? "everywhere"
                : runs.length === 0 ? "nowhere — over every cap measured"
                : "nodes at " + M(runs[0].at) + " and above";
    console.log(`      ${r.label.padEnd(24)}${colour}${M(r.gas).padStart(9)}\x1b[0m` +
                `  ${(r.bytes.toLocaleString() + " B").padStart(9)}   \x1b[2m${where}\x1b[0m`);
    console.log(`      \x1b[2m${" ".repeat(24)}${r.note}\x1b[0m`);
  }

  if (premises && premises.gas) {
    head("the same document, through the ERC-5219 front door");
    console.log(`      Premises /token/1/live  ${M(premises.gas).padStart(9)}` +
                `  ${premises.bytes.toLocaleString()} B`);
    console.log(`      \x1b[2mno base64, no data: URI wrapper — a web3:// gateway or an` +
                `\n      ERC-5219 aware wallet reads this instead, and it is the` +
                `\n      cheaper path to the identical page.\x1b[0m`);
  }

  head("verdict");
  if (over.length === 0) {
    console.log(`      \x1b[32mevery read is under ${M(FLOOR)}\x1b[0m — a default geth, ` +
                `erigon or reth\n      will serve all of them.`);
  } else {
    for (const r of over) {
      console.log(`      \x1b[31m${r.label} needs ${M(r.gas)}\x1b[0m, over the ` +
                  `${M(FLOOR)} default.`);
    }
    console.log(`\n      \x1b[2mA call over the cap does not fail politely. The node` +
                `\n      returns "out of gas" and the caller cannot tell that from a` +
                `\n      broken contract.\x1b[0m`);
  }
  console.log("");
}

process.exit(over.length === 0 ? 0 : 1);
