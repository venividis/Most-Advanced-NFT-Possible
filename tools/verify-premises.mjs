#!/usr/bin/env node
/*───────────────────────────────────────────────────────────────────────────
  IPSEITY · the front door

  Every token is already a website. This is the thing that was missing:
  somewhere to send a person who does not own one yet.

  The claim under test is not "the index works". It is the constraint that
  makes an index safe to have at all:

      PREMISES NEVER SERVES THE ARTWORK.

  It serves a document that names the artwork, by emitting the token's own
  data: URI read from the hub at request time. So the strongest assertion in
  this file is a byte-for-byte comparison: what the page hands a viewer must
  equal tokenURI(id) exactly. If that holds, then an attacker who owns this
  contract owns a page that links to the artwork and cannot alter one byte
  of it — and if the contract is never deployed, or is abandoned, every
  token renders exactly the same.

  Also under test: a request for nonsense is a 404, not a revert. A client
  asking for a path that does not exist deserves an answer.

    node tools/verify-premises.mjs
───────────────────────────────────────────────────────────────────────────*/
import { compile, artifact } from "./compile.mjs";
import { Chain, decUint, encodeAddressArg } from "./evm.mjs";
import { createAddressFromString } from "@ethereumjs/util";

let pass = 0, fail = 0;
const ok = (n, c, d) => {
  c ? pass++ : fail++;
  console.log(`  ${c ? "\x1b[32m✓\x1b[0m" : "\x1b[31m✗\x1b[0m"} ${n}`);
  if (!c && d !== undefined) console.log(`      ${d}`);
};
const eq = (n, g, w) => ok(n, String(g) === String(w), `got ${g}\n      want ${w}`);
const head = (s) => console.log(`\n  \x1b[1m${s}\x1b[0m`);
const REGISTRY = "0x000000006551c19487814612e58FE06813775758";

const evm = await import("./evm.mjs");
const out = compile({ quiet: true, dirs: ["src", "test/mocks"] });
const A = (f, n) => artifact(out, f, n);
const c = await Chain.open();

/*──────────────── encoding a request ────────────────*/
const w = (n) => BigInt(n).toString(16).padStart(64, "0");
const encStr = (s) => {
  const b = Buffer.from(s, "utf8");
  return w(b.length) + b.toString("hex").padEnd(Math.ceil(b.length / 32) * 64, "0");
};
const encStrArray = (arr) => {
  const bodies = arr.map(encStr);
  let off = arr.length * 32;
  const heads = bodies.map((b) => { const h = w(off); off += b.length / 2; return h; });
  return w(arr.length) + heads.join("") + bodies.join("");
};
/* request(string[],(string,string)[]) — two dynamic arrays in the head */
const SEL = evm.sel("request(string[],(string,string)[])");
const encRequest = (resource) => {
  const res = encStrArray(resource);
  const params = w(0);                       // no query parameters are read
  return SEL + w(0x40) + w(0x40 + res.length / 2) + res + params;
};

/*──────────────── decoding the response ────────────────*/
const decResponse = (hex) => {
  const h = hex.replace(/^0x/, "");
  const status = Number(BigInt("0x" + h.substr(0, 64)));
  const bodyOff = Number(BigInt("0x" + h.substr(64, 64))) * 2;
  const hdrOff = Number(BigInt("0x" + h.substr(128, 64))) * 2;

  const bodyLen = Number(BigInt("0x" + h.substr(bodyOff, 64)));
  const body = Buffer.from(h.substr(bodyOff + 64, bodyLen * 2), "hex").toString("utf8");

  const n = Number(BigInt("0x" + h.substr(hdrOff, 64)));
  const headers = [];
  for (let i = 0; i < n; i++) {
    const t = hdrOff + 64 + Number(BigInt("0x" + h.substr(hdrOff + 64 + i * 64, 64))) * 2;
    const readAt = (at) => {
      const o = t + Number(BigInt("0x" + h.substr(at, 64))) * 2;
      const len = Number(BigInt("0x" + h.substr(o, 64)));
      return Buffer.from(h.substr(o + 64, len * 2), "hex").toString("utf8");
    };
    headers.push([readAt(t), readAt(t + 64)]);
  }
  return { status, body, headers };
};
const GET = async (path) => decResponse(await c.call(premises, encRequest(path)));

/*──────────────── deploy ────────────────*/
head("deploy");
const tmpReg = await c.deploy(A("test/mocks/ERC6551Registry.sol", "ERC6551Registry").bytecode);
await c.vm.stateManager.putCode(createAddressFromString(REGISTRY),
  await c.vm.stateManager.getCode(createAddressFromString(tmpReg)));

const impl = await c.deploy(A("src/IpseityAccount.sol", "IpseityAccount").bytecode);
const gripImpl = await c.deploy(A("src/GripVault.sol", "GripVault").bytecode);
const engine = await c.deploy(A("src/Engine.sol", "Engine").bytecode, "0".repeat(63) + "1");
const sigil = await c.deploy(A("src/Sigil.sol", "Sigil").bytecode);
const renderer = await c.deploy(A("src/Renderer.sol", "Renderer").bytecode,
  encodeAddressArg(engine) + encodeAddressArg(sigil));
const nft = await c.deploy(A("src/Ipseity.sol", "Ipseity").bytecode,
  encodeAddressArg(renderer) + encodeAddressArg(impl) + encodeAddressArg(gripImpl));

/* a small real document, so tokenURI returns something whole */
const doc = Buffer.from("<!doctype html><title>x</title><body>the instrument</body>", "utf8");
const { gzipSync } = await import("node:zlib");
const packed = gzipSync(doc, { level: 9 });
const loadArg = (b) => w(0x20) + w(b.length) + b.toString("hex").padEnd(Math.ceil(b.length / 32) * 64, "0");
await c.send({ to: engine, data: evm.sel("loadHead(bytes)") + loadArg(packed) });
await c.send({ to: engine, data: evm.sel("loadBody(bytes)") + loadArg(packed) });
await c.exec(engine, "setInflatedSize(uint32)", [doc.length]);

const premises = await c.deploy(A("src/Premises.sol", "Premises").bytecode,
  encodeAddressArg(nft), "Premises");
ok("deployed", (await c.codeSize(premises)) > 0);
console.log(`      ${premises}`);

await c.exec(nft, "mint()", [], { value: 10n ** 16n });
await c.exec(nft, "mint()", [], { value: 10n ** 16n });

/*──────────────── the index ────────────────*/
head("the index answers HTTP, from a contract");
const idx = await GET([]);
eq("200", idx.status, 200);
eq("Content-Type", idx.headers[0][1], "text/html; charset=utf-8");
eq("Cache-Control", idx.headers[1][0], "Cache-Control");
ok("it is a document", idx.body.startsWith("<!doctype html>"));
ok("it names the collection", idx.body.includes("IPSEITY"));
ok("it counts what has been issued", idx.body.includes("2 of 4096"));
ok("and lists the most recent", idx.body.includes('href="/token/2"'));
console.log(`      ${idx.body.length} bytes, no server involved`);

/*──────────────── one token ────────────────*/
head("a token's page");
const one = await GET(["token", "1"]);
eq("200", one.status, 200);
ok("it names the token", one.body.includes("IPSEITY #1"));
ok("it reports the hands", one.body.toLowerCase().includes("reach") && one.body.toLowerCase().includes("grip"));
ok("and the kernel", one.body.includes("kernel"));

/*════════════ the constraint that makes this safe ════════════*/
head("what the page hands you is the token's own bytes");
const uri = await c.read(nft, "tokenURI(uint256)", [1]);
const tokenUri = (() => {
  const h = uri.replace(/^0x/, "");
  const off = Number(BigInt("0x" + h.substr(0, 64))) * 2;
  const len = Number(BigInt("0x" + h.substr(off, 64)));
  return Buffer.from(h.substr(off + 64, len * 2), "hex").toString("utf8");
})();

const m = one.body.match(/<iframe[^>]*src="([^"]*)"/);
ok("the page embeds a src", m !== null);
eq("and it is tokenURI(1), byte for byte", m && m[1] === tokenUri, true);
console.log("      an attacker who owned this contract would own a page that");
console.log("      links to the artwork, and could not alter one byte of it");

const raw = await GET(["token", "1", "raw"]);
eq("/raw returns the URI itself", raw.body, tokenUri);
eq("as text/plain", raw.headers[0][1], "text/plain; charset=utf-8");

/*──────────────── nonsense gets an answer ────────────────*/
head("a request for nonsense is a 404, never a revert");
for (const [name, path] of [
  ["a token that does not exist", ["token", "9999"]],
  ["a path that is not a number", ["token", "abc"]],
  ["a number too long to be an id", ["token", "99999999999"]],
  ["a route nobody defined", ["nonsense"]],
  ["token with nothing after it", ["token"]],
  ["an empty segment", ["token", ""]]
]) {
  let r = null;
  try { r = await GET(path); } catch (e) { /* a revert is the failure */ }
  ok(name, r !== null && r.status === 404,
     r === null ? "it reverted instead of answering" : `status ${r.status}`);
}

/*──────────────── the shape ────────────────*/
head("read off the compiled ABI and the deployed code");
const abi = A("src/Premises.sol", "Premises").abi;
const writes = abi.filter((f) => f.type === "function" &&
  f.stateMutability !== "view" && f.stateMutability !== "pure");
eq("there is no state-changing function at all", writes.length, 0);
ok("nothing that could hold or move an asset",
   !abi.some((f) => /transfer|withdraw|approve|execute|receive|admin|owner|set/i.test(f.name || "")),
   "a front door is a reader; anything else is a liability with a URL");

/* the independence claim, checked rather than asserted: the artwork is not
   inside this contract, so it cannot be changed by changing this contract */
const code = await c.vm.stateManager.getCode(createAddressFromString(premises));
const engineCode = await c.vm.stateManager.getCode(createAddressFromString(engine));
const hay = Buffer.from(code).toString("hex");
const needle = Buffer.from(engineCode.slice(1, 33)).toString("hex");
ok("it holds none of the artwork's bytes", !hay.includes(needle),
   "the index has a copy of the document — then it is infrastructure, not convenience");
console.log("      the tokens render identically whether this contract exists,");
console.log("      is abandoned, or is replaced by something else entirely");

console.log(`\n  ${fail === 0 ? "\x1b[32m" : "\x1b[31m"}${pass} passed, ${fail} failed\x1b[0m\n`);
process.exit(fail === 0 ? 0 : 1);
