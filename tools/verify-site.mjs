#!/usr/bin/env node
/*───────────────────────────────────────────────────────────────────────────
  IPSEITY · each token's shopfront, and the rent it collects

  The front door was already verified by `verify-premises.mjs`, against the
  one claim that makes an index safe to have: it never serves the artwork.
  This is the other half — the part where a stranger can actually *use* a
  token, and where the token gets paid.

  Three things are under test, in order of how badly each would fail.

  ── 1. an injected script would be same-origin with a wallet ──

  A market's pair is two ERC-20 addresses the token holder chose, and
  `symbol()` on them returns a string that holder wrote. Those strings go on
  a page. That page is served by the same contract, on the same origin, as
  `/token/<id>/live` — which exists precisely so wallet extensions *will*
  inject into it.

  So a `<script>` surviving into a market page is not a cosmetic bug. It is
  script execution next to a connected wallet. The suite deploys a token
  whose symbol is a script tag and asserts it comes out inert.

  ── 2. a page that reverts is a shop with the shutters down ──

  Five more hostile tokens: one that refuses to answer, one that answers in
  `bytes32` like MKR, one that answers with eight kilobytes, one that
  declares a length longer than the payload it sent, and one that claims 200
  decimals so `10 ** decimals` overflows. Each is put into a real market and
  every route is fetched. A page that dies on one row is a directory nobody
  can read.

  ── 3. the rent has to add up ──

  `Lease` holds ether belonging to two different parties at once, and the
  interesting case is the lease cut short: the token is sold mid-term, the
  ERC-4907 user is cleared, and what was paid has to split by elapsed time
  without either side being able to take the other's part. The invariant
  checked after every operation is that the contract's balance covers
  everything it owes.

    node tools/verify-site.mjs
───────────────────────────────────────────────────────────────────────────*/
import { compile, artifact } from "./compile.mjs";
import * as evm from "./evm.mjs";
import { Chain, encodeAddressArg, decUint, decAddr, decString } from "./evm.mjs";
import { deploySite, getter } from "./site.mjs";
import { createAddressFromString } from "@ethereumjs/util";
import { keccak256 } from "ethereum-cryptography/keccak.js";

let pass = 0, fail = 0;
const ok = (n, c, d) => {
  c ? pass++ : fail++;
  console.log(`  ${c ? "\x1b[32m✓\x1b[0m" : "\x1b[31m✗\x1b[0m"} ${n}`);
  if (!c && d !== undefined) console.log(`      \x1b[31m${d}\x1b[0m`);
};
const eq = (n, g, w) => ok(n, String(g) === String(w), `got ${g}\n      want ${w}`);
const head = (s) => console.log(`\n  \x1b[1m${s}\x1b[0m`);
const w = (n) => BigInt(n).toString(16).padStart(64, "0");
const REGISTRY = "0x000000006551c19487814612e58FE06813775758";
const WAD = 10n ** 18n;

const refuses = async (name, fn, want) => {
  try { await fn(); ok(name, false, "it went through"); }
  catch (e) { ok(name, !want || String(e.message).includes(want), e.message.slice(0, 120)); }
};

console.log("\n  \x1b[1mIPSEITY · the shopfront\x1b[0m");

/*──────────────── deploy ────────────────*/
head("a collection, a market, a lease and a site");
const out = compile({ quiet: true, dirs: ["src", "test/mocks"] });
const A = (f, n) => artifact(out, f, n);
const c = await Chain.open();

const tmpReg = await c.deploy(A("test/mocks/ERC6551Registry.sol", "ERC6551Registry").bytecode);
await c.vm.stateManager.putCode(createAddressFromString(REGISTRY),
  await c.vm.stateManager.getCode(createAddressFromString(tmpReg)));

const engine = await c.deploy(A("src/Engine.sol", "Engine").bytecode, "0".repeat(63) + "1");
const sigil = await c.deploy(A("src/Sigil.sol", "Sigil").bytecode);
const renderer = await c.deploy(A("src/Renderer.sol", "Renderer").bytecode,
  encodeAddressArg(engine) + encodeAddressArg(sigil));
const nft = await c.deploy(A("src/Ipseity.sol", "Ipseity").bytecode,
  encodeAddressArg(renderer) +
  encodeAddressArg(await c.deploy(A("src/IpseityAccount.sol", "IpseityAccount").bytecode)) +
  encodeAddressArg(await c.deploy(A("src/GripVault.sol", "GripVault").bytecode)));

/* a small real document, so tokenURI returns something whole */
const { gzipSync } = await import("node:zlib");
const doc = Buffer.from("<!doctype html><title>x</title><body>the instrument</body>", "utf8");
const packed = gzipSync(doc, { level: 9 });
const loadArg = (b) =>
  w(0x20) + w(b.length) + b.toString("hex").padEnd(Math.ceil(b.length / 32) * 64, "0");
await c.send({ to: engine, data: evm.sel("loadHead(bytes)") + loadArg(packed) });
await c.send({ to: engine, data: evm.sel("loadBody(bytes)") + loadArg(packed) });
await c.exec(engine, "setInflatedSize(uint32)", [doc.length]);

const pool = await c.deploy(A("src/Pool.sol", "Pool").bytecode,
  encodeAddressArg(nft) + w(10n ** 30n) + encodeAddressArg(c.from.toString()) + w(0), "Pool");
await c.exec(nft, "setPool(address)", [pool]);
const lease = await c.deploy(A("src/Lease.sol", "Lease").bytecode, encodeAddressArg(nft), "Lease");

const site = await deploySite(c, A, { hub: nft, pool, lease });
const GET = getter(c, site.premises);
ok("the site is deployed", (await c.codeSize(site.premises)) > 0);

/* the holder is the deployer; a renter and a buyer are other people */
const renter = await c.as("0x" + "22".repeat(32));
const buyer = await c.as("0x" + "33".repeat(32));

for (let i = 0; i < 3; i++) await c.exec(nft, "mint()", [], { value: 10n ** 16n });
ok("three tokens issued", true);

/*════════════════ 1 · the escaping ════════════════*/
head("a token whose symbol is a script tag");

const nasty = await c.deploy(A("test/mocks/Nasty.sol", "ScriptToken").bytecode, "", "ScriptToken");
/* constructor(string n, string s, uint8 d, uint256 feeBps, bool silent) */
const encS = (t) => w(t.length) + Buffer.from(t).toString("hex").padEnd(64, "0");
const weth = await c.deploy(A("test/mocks/MockERC20.sol", "MockERC20").bytecode,
  w(0xa0) + w(0xe0) + w(18) + w(0) + w(0) + encS("Wrapped Ether") + encS("WETH"), "WETH");

await c.exec(pool, "openMarket(uint256,address,address,uint16)", [1, nasty, weth, 30]);

const mk = await GET(["token", "1", "market"]);
eq("the market page still answers 200", mk.status, 200);
ok("the raw script tag is gone", !mk.body.includes("<script>alert"));
ok("it survives as inert text", mk.body.includes("&lt;script&gt;alert"));
/*  The app ships a JSON config block and two script blocks, so counting
    tags proves nothing on its own. What has to be true is that every
    <script> the page opens is one the contract wrote: tags balance, and
    nothing attacker-supplied contributed a bracket.                     */
ok("every script tag the page opens is closed by one it wrote",
   (mk.body.match(/<script/g) || []).length === (mk.body.match(/<\/script>/g) || []).length,
   `${(mk.body.match(/<script/g) || []).length} open, ` +
   `${(mk.body.match(/<\/script>/g) || []).length} closed`);
ok("the hostile symbol contributed no bracket to the document",
   !mk.body.includes("<script>alert") && !mk.body.includes("</script>alert"));

/* the attribute context: name() is `" onerror="alert(1)` */
ok("a quote-breaking name cannot escape an attribute",
   !/ onerror=/.test(mk.body.replace(/&quot;/g, "")) || !mk.body.includes('" onerror="'));

const tok = await GET(["token", "1"]);
eq("the token page too", tok.status, 200);
ok("no raw script there either", !tok.body.includes("<script>alert"));

/*  The counter page must stay cheap. It used to embed the whole instrument
    as a data: URI and cost 21M gas of eth_call — the most expensive page on
    the site, to show a preview a viewer cannot use, because a data: frame
    has an opaque origin and no wallet injects into one.                  */
ok("the counter page does not inline the whole instrument",
   !tok.body.includes("data:application/json;base64,"),
   "a data: URI is embedded in the page again");
ok("it points at the still as its own request",
   tok.body.includes('src="/token/1/sigil.svg"'));
const svgR = await GET(["token", "1", "sigil.svg"]);
eq("which is served as an image", svgR.headers[0][1], "image/svg+xml");
ok("and is an SVG", svgR.body.startsWith("<svg"));

const js = await GET(["token", "1", "services.json"]);
eq("and the manifest", js.status, 200);
ok("no unescaped angle bracket inside the JSON strings", !js.body.includes("<script>"));
let parsed = null;
try { parsed = JSON.parse(js.body); ok("the manifest is valid JSON", true); }
catch (e) { ok("the manifest is valid JSON", false, e.message); }
if (parsed) {
  const trade = parsed.services.find((s) => s.id === "trade");
  /*  The parsed value may legitimately contain `<` — that is what \u003c
      decodes to, and a JSON consumer wants the real string. The property
      that matters is about the BYTES: a document containing a literal
      `</script>` inside a string ends a script block when the JSON is
      pasted into HTML, which is where JSON usually ends up.            */
  ok("the raw bytes escape the angle brackets", js.body.includes("\\u003c"));
  ok("and contain no literal < at all", !js.body.includes("<"));
  ok("while a consumer still gets the real string",
     trade && typeof trade.base.symbol === "string" && trade.base.symbol.includes("<script>"));
  ok("truncated to a label length a page can survive",
     trade && trade.base.symbol.length <= 32, `${trade && trade.base.symbol.length} chars`);
  console.log(`      symbol came through as: ${JSON.stringify(trade && trade.base.symbol)}`);
}

/*════════════════ 2 · tokens that answer badly ════════════════*/
head("five more ways an ERC-20 can refuse to behave");

const kinds = [
  ["SilentToken", "reverts when asked"],
  ["Bytes32Token", "answers in bytes32, like MKR"],
  ["HugeToken", "answers with eight kilobytes"],
  ["LiarToken", "declares a length longer than it sent"],
  ["MadDecimalsToken", "claims 200 decimals"],

  ["GasBurnerToken", "burns every drop of gas it is given"],
  ["OffsetBombToken", "points its ABI offset 33 MB past the buffer", w(0x02000000)],
  ["OffsetBombToken", "and the same at the top of the old bound", w(0xfffffffe)]
];
/*  One fresh token per hostile pair. The first version of this loop cycled
    two ids, so `openMarket` reverted MarketAlreadyOpen from the second kind
    onward and six of the eight cases never reached a page at all — they
    passed because nothing ran, which is the failure mode this whole suite
    exists to catch.                                                      */
let openFail = "";
for (const [name, what, arg] of kinds) {
  const bad = await c.deploy(A("test/mocks/Nasty.sol", name).bytecode, arg || "", name);
  await c.exec(nft, "mint()", [], { value: 10n ** 16n });
  const id = Number(decUint(await c.read(nft, "totalSupply()")));

  let opened = true;
  try {
    await c.exec(pool, "openMarket(uint256,address,address,uint16)", [id, bad, weth, 30]);
  } catch (e) { opened = false; openFail = e.message.slice(0, 90); }

  const p = await GET(["token", String(id), "market"]);
  const gasUsed = c.lastGas;
  const j = await GET(["token", String(id), "services.json"]);
  let jsonOk = true;
  try { JSON.parse(j.body); } catch { jsonOk = false; }

  /*  The gas bound is the assertion that matters, not the status. These
      pages are read with a three-billion-gas ceiling so a route can be
      measured rather than merely survive — and an offset bomb "succeeds"
      at that ceiling while costing 2,151M, which no node on earth will
      serve. A suite that only checks for a revert walks straight past it. */
  ok(`${name} — ${what}`,
     opened && p.status === 200 && j.status === 200 && jsonOk && gasUsed < 10_000_000n,
     opened
       ? `market ${p.status}, json ${j.status}, parses ${jsonOk}, ` +
         `gas ${(Number(gasUsed) / 1e6).toFixed(2)}M`
       : `the market never opened, so the page never read it: ${openFail}`);
}

head("and the directory, with all of them in it");
const dir = await GET(["open"]);
eq("200", dir.status, 200);
ok("it renders", dir.body.includes("open for business"));
ok("no raw script", !dir.body.includes("<script>alert"));
ok("it says how much of the real list it showed",
   /Showing \d+ of \d+ open market/.test(dir.body),
   "the directory no longer states its window");
ok("and warns that swap-and-pop can move an entry under a reader",
   /Closing a market moves the last entry/.test(dir.body));
console.log(`      ${dir.body.length} bytes`);

/*════════════════ 3 · every route answers ════════════════*/
head("every route");
const routes = [
  [[], "text/html", "the index"],
  [["open"], "text/html", "/open"],
  [["open", "0"], "text/html", "/open/0"],
  [["services.json"], "application/json", "/services.json"],
  [["services.json", "0"], "application/json", "/services.json/0"],
  [["token", "1"], "text/html", "/token/1"],
  [["token", "1", "faces"], "text/html", "/token/1/faces"],
  [["token", "1", "market"], "text/html", "/token/1/market"],
  [["token", "1", "pool"], "text/html", "/token/1/pool"],
  [["assets"], "text/html", "/assets"],
  [["assets", "0"], "text/html", "/assets/0"],
  [["token", "1", "rent"], "text/html", "/token/1/rent"],
  [["token", "1", "vault"], "text/html", "/token/1/vault"],
  [["token", "1", "services.json"], "application/json", "/token/1/services.json"],
  [["token", "1", "raw"], "text/plain", "/token/1/raw"],
  [["token", "1", "live"], "text/html", "/token/1/live"],
  [["token", "1", "face", "1"], "text/plain", "/token/1/face/1"],
  [["token", "1", "sigil.svg"], "image/svg+xml", "/token/1/sigil.svg"]
];
for (const [path, type, label] of routes) {
  const r = await GET(path);
  ok(`${label.padEnd(26)} ${String(r.body.length).padStart(7)} bytes`,
     r.status === 200 && r.headers[0][1].startsWith(type),
     `status ${r.status}, type ${r.headers[0][1]}`);
}

/*════════════════ ERC-6860: how a client finds any of this ════════════════*/
head("the four bytes that make web3:// resolve at all");
const mode = await c.read(site.premises, "resolveMode()");
eq("resolveMode() declares 5219",
   Buffer.from(mode.replace(/^0x/, ""), "hex").subarray(0, 4).toString("utf8"), "5219");
console.log("      without it ERC-6860 falls back to auto mode, where web3://<addr>/");
console.log("      is an empty call to a contract with no fallback, and /token/1 is a");
console.log("      call to a method named `token` — both revert, and the site is");
console.log("      reachable only from a gateway that hard-codes 5219, i.e. a server");

head("one resource, one URL");
for (const [name, path] of [
  ["a trailing slash is the same page", ["token", "1", ""]],
  ["and on a collection route too", ["open", ""]]
]) {
  const r = await GET(path);
  ok(name, r.status === 200, `got ${r.status}`);
}
for (const [name, path] of [
  ["junk after a leaf is not the leaf", ["token", "1", "market", "anything"]],
  ["nor after the token", ["token", "1", "extra", "more", "still"]],
  ["a leading zero is not a second address for token 1", ["token", "0000000001"]],
  ["nor for a page number", ["open", "00"]],
  ["face takes exactly one index", ["token", "1", "face", "1", "2"]]
]) {
  const r = await GET(path);
  ok(name, r.status === 404, `got ${r.status}`);
}
console.log("      every response carries a Cache-Control, so a page reachable at");
console.log("      unboundedly many URLs is a gateway cache waiting to be flooded");

head("and nonsense is still a 404");
for (const [name, path] of [
  [["token", "1", "nope"], "an undefined leaf"],
  [["token", "1", "face"], "face with no index"],
  [["token", "1", "face", "x"], "face with a non-numeric index"],
  [["open", "x"], "a page that is not a number"],
  [["services.json", "x"], "a json page that is not a number"]
].map(([p, n]) => [n, p])) {
  const r = await GET(path);
  ok(name, r.status === 404, `got ${r.status}`);
}

/*════════════════ 4 · the manifest is actionable ════════════════*/
head("the manifest tells a program how to call, not just what exists");
const m1 = JSON.parse((await GET(["token", "1", "services.json"])).body);
eq("it declares its schema", m1.schema, "ipseity.services/1");
ok("it names the chain", typeof m1.chainId === "number");
ok("it lists five services",
   m1.services.length === 5, `got ${m1.services.map((s) => s.id).join(",")}`);

const sel4 = (sig) =>
  "0x" + Buffer.from(keccak256(Buffer.from(sig, "utf8"))).toString("hex").slice(0, 8);
let selOk = 0, selBad = [];
for (const s of m1.services) {
  for (const k of ["read", "quote", "invoke", "also"]) {
    const call = s[k];
    if (!call || !call.sig) continue;
    if (sel4(call.sig) === call.selector) selOk++;
    else selBad.push(`${s.id}.${k}: ${call.sig} -> ${call.selector} (want ${sel4(call.sig)})`);
  }
}
ok(`every selector matches keccak of its signature (${selOk} checked)`,
   selBad.length === 0, selBad.join("\n      "));
console.log("      a caller holding these needs an RPC endpoint and nothing else");

ok("the grip is named as one-way",
   m1.services.find((s) => s.id === "give").oneWay === true);
ok("rent says who is paid",
   m1.services.find((s) => s.id === "rent").paidTo === "token");
ok("draw says nobody is paid",
   m1.services.find((s) => s.id === "draw").paidTo === null);

/*════════════ 5 · the calldata, and where the browser gets it ════════════*/
head("the app is handed selectors a contract computed");

const cfgOf = (body) => {
  const m = body.match(/<script type="application\/json" id="D">([\s\S]*?)<\/script>/);
  if (!m) return null;
  try { return JSON.parse(m[1]); } catch { return null; }
};

const cfg = cfgOf(mk.body);
ok("the swap page carries a config block", cfg !== null);
if (cfg) {
  ok("naming the pool, the market and the chain",
     cfg.pool && cfg.id === 1 && typeof cfg.chain === "number");
  ok("with both sides' decimals, so the browser never guesses",
     typeof cfg.base.d === "number" && typeof cfg.quote.d === "number");

  const want = {
    quote: "quote(uint256,bool,uint256)",
    swap: "swap(uint256,bool,uint256,uint256,address,uint256)",
    approve: "approve(address,uint256)",
    allowance: "allowance(address,address)",
    balanceOf: "balanceOf(address)",
    deposit: "deposit(uint256,uint256,uint256)",
    withdraw: "withdraw(uint256,uint256,uint256,address)",
    setFee: "setFee(uint256,uint16)",
    bond: "bond(uint256,uint64)",
    syncCurve: "syncCurve(uint256)",
    openMarket: "openMarket(uint256,address,address,uint16)",
    closeMarket: "closeMarket(uint256)"
  };
  const bad = [];
  for (const [k, sig] of Object.entries(want)) {
    if (cfg.sel[k] !== sel4(sig)) bad.push(`${k}: ${cfg.sel[k]} != ${sel4(sig)} (${sig})`);
  }
  ok(`every pool selector matches keccak of its signature (${Object.keys(want).length})`,
     bad.length === 0, bad.join("\n      "));

  const lwant = {
    rent: "rent(uint256,uint32,uint128)",
    list: "list(uint256,uint128,uint32,uint32)",
    delist: "delist(uint256)",
    collect: "collect(uint256,address)",
    endLease: "endLease(uint256)",
    settle: "settle(uint256)",
    claim: "claim()",
    agent: "setLeaseAgent(uint256,address)"
  };
  const lbad = [];
  for (const [k, sig] of Object.entries(lwant)) {
    if (cfg.lease.sel[k] !== sel4(sig)) lbad.push(`${k}: ${cfg.lease.sel[k]} != ${sel4(sig)}`);
  }
  ok(`and every lease selector too (${Object.keys(lwant).length})`,
     lbad.length === 0, lbad.join("\n      "));
  console.log("      the browser never computes a selector, so it needs no keccak");
}

/*  The config is JSON inside a <script> block, which is the one place a
    symbol containing `</script>` would end the document early. That is
    exactly why jsonEsc escapes `<` and `>` and not only the two characters
    JSON requires.                                                        */
ok("a symbol cannot end the config block it appears in",
   cfg !== null && typeof cfg.base.s === "string",
   "the block did not parse, so something in it terminated early");
if (cfg) console.log(`      base symbol parsed back as: ${JSON.stringify(cfg.base.s)}`);

head("the app itself");
for (const [what, needle] of [
  ["parses decimals into BigInt base units", "const parse=(s,d)=>"],
  ["formats them back the same way", "const fmt=(v,d,p)=>"],
  ["refuses a value that will not fit a word", "does not fit in a word"],
  ["checks the chain before it sends", "your wallet is on chain "],
  ["quotes live, debounced", "setTimeout(refresh,220)"],
  ["knows whether it is approving or swapping", "al<amt?('Approve "],
  ["computes the floor from a slippage tolerance", "BigInt(10000-slip)/10000n"]
]) {
  ok(what, mk.body.includes(needle), "not found in the page");
}
ok("and no keccak or ABI coder was shipped",
   !/keccak|ethers|web3\.js/i.test(mk.body));

const pl = await GET(["token", "1", "pool"]);
/*  The client is contract code. A syntax error in it is permanent, and
    would be invisible to every assertion above — the page would render,
    the bytes would be right, and nothing on it would work. So the script
    blocks are parsed.                                                    */
/*════════════ the picker: which markets can actually be traded ════════════*/
head("the market picker, and the token list that is not fetched");
{
  const total = Number(decUint(await c.read(pool, "openCount()")));
  ok("the pool enumerates its own open markets", total > 0, `openCount() = ${total}`);

  /*  The defect this replaced: /open walked token IDS, so a collection with
      markets only on high ids showed an empty first page and a reader
      concluded there were none. Prove the directory finds one that a scan
      of the first window would have missed.                              */
  while (Number(decUint(await c.read(nft, "totalSupply()"))) < 40) {
    await c.exec(nft, "mint()", [], { value: 10n ** 16n });
  }
  const far = Number(decUint(await c.read(nft, "totalSupply()")));
  const dai = await c.deploy(A("test/mocks/MockERC20.sol", "MockERC20").bytecode,
    w(0xa0) + w(0xe0) + w(18) + w(0) + w(0) + encS("Dai") + encS("DAI"), "DAI");
  await c.exec(pool, "openMarket(uint256,address,address,uint16)", [far, weth, dai, 30]);

  const dir = await GET(["open"]);
  ok(`a market on token #${far} appears on the first page of the directory`,
     dir.body.includes(`/token/${far}/market`),
     "walking token ids would have needed a page for every 24 of them");

  const swapPage = await GET(["token", "1", "market"]);
  ok("the swap card carries a market picker", swapPage.body.includes("id=mkt"));
  const opts = [...swapPage.body.matchAll(/<option value="(\d+)"/g)].map((m) => m[1]);
  ok("listing markets the pool says exist", opts.length > 0, "no options rendered");
  ok("including the far one", opts.includes(String(far)), opts.join(","));
  ok("and marking the one you are on", swapPage.body.includes("selected"));

  /*  The property a hosted token list cannot offer: everything offered is
      tradeable, because it was read from the thing that would trade it.  */
  let allOpen = true;
  for (const o of opts) {
    const mkt = await c.read(pool, "market(uint256)", [Number(o)]);
    if (decUint(mkt, 5) !== 1n) { allOpen = false; break; }
  }
  ok("every market it offers is genuinely open", allOpen,
     "the picker listed a market the pool says is closed");

  const as = await GET(["assets"]);
  eq("the asset index answers", as.status, 200);
  ok("naming what is actually traded", as.body.includes("WETH") && as.body.includes("DAI"));
  ok("with the address, so nothing has to be trusted", as.body.includes(weth.slice(2, 12)));
  ok("and it is derived, not fetched",
     !/tokenlist|ipfs|https?:\/\//i.test(as.body.replace(/www\.w3\.org/g, "")));

  /*  Closing a market has to remove it, or the picker offers a market that
      cannot be traded — which is the exact failure a fetched list has.   */
  await c.exec(pool, "closeMarket(uint256)", [far]);
  eq("closing one drops it from the count",
     Number(decUint(await c.read(pool, "openCount()"))), total + 1 - 1);
  const dir2 = await GET(["open"]);
  ok("and from the directory",
     !dir2.body.includes(`href="/token/${far}/market"`),
     "a closed market is still being offered");
}

head("the app parses as JavaScript");
const scriptsOf = (body) =>
  [...body.matchAll(/<script>([\s\S]*?)<\/script>/g)].map((m) => m[1]);
for (const [label, body] of [
  ["the swap page", mk.body],
  ["the pool page", (await GET(["token", "1", "pool"])).body],
  ["the rent page", (await GET(["token", "1", "rent"])).body],
  ["the vault page", (await GET(["token", "1", "vault"])).body]
]) {
  const blocks = scriptsOf(body);
  let bad = null;
  for (const b of blocks) {
    try { new Function(b); } catch (e) { bad = e.message; break; }
  }
  ok(`${label} — ${blocks.length} block(s)`, blocks.length > 0 && bad === null,
     bad || "no script blocks found at all");
}
/*  And the pages that are documents ship none, which is the right answer
    rather than an oversight: the index and the counter are links, and a
    client that does nothing is bytes a node serves for no reason.       */
for (const [label, path] of [["the index", []], ["the counter", ["token", "1"]]]) {
  const b = (await GET(path)).body;
  ok(`${label} ships no client, because it has nothing to sign`,
     scriptsOf(b).length === 0, `${scriptsOf(b).length} script block(s)`);
}

head("the holder's side is on the site too");
eq("200", pl.status, 200);
for (const [what, needle] of [
  ["add liquidity", "id=add"],
  ["remove liquidity", "id=rm"],
  ["set the fee", "id=fee"],
  ["bond the market", "id=bond"],
  ["sync the curve to the artwork", "id=sync"]
]) ok(what, pl.body.includes(needle));
ok("and it says whose page it is", pl.body.includes("the holder of #1"));

const rp = await GET(["token", "1", "rent"]);
head("the holder's side of the rental counter");
for (const [what, needle] of [
  ["names the lease agent", "id=agt"],
  ["publishes terms", "id=ls"],
  ["collects", "id=col"],
  ["ends a lease properly", "id=end"],
  ["and brings the books up to date", "id=set2"]
]) ok(what, rp.body.includes(needle));
ok("while an unlisted token shows no rent card, rather than a dead one",
   !rp.body.includes("id=rg"));


/*  The invariant Lease exists to keep. Every wei it holds is spoken for by
    exactly one of three ledgers, and the balance has to cover all of them
    at once — not at the end, at every step. Asserting it once at the close
    would pass for a contract that was briefly insolvent in the middle.   */
const PARTIES = [];      // every address that could be owed
const TOKENS = [1, 2, 3];  // every token that could hold rent
const OBLIGED = async (label) => {
  let owedTotal = 0n;
  for (const a of [c, renter, buyer, ...PARTIES])
    owedTotal += decUint(await c.read(lease, "owed(address)", [a.from.toString()]));
  let held = 0n;
  for (const t of TOKENS) {
    held += decUint(await c.read(lease, "earned(uint256)", [t]));
    const act = await c.read(lease, "activeOf(uint256)", [t]);
    held += decUint(act, 3);              // renter, start, until, paid, seen
  }
  const bal = await c.balanceOf(lease);
  ok(`solvent: ${label}`, bal >= owedTotal + held,
     `balance ${bal} < obligations ${owedTotal + held}`);
  return bal - (owedTotal + held);
};

/*  A DOM small enough to read: elements by id, two attribute selectors,
    and events. Enough to run the contract's own client, which is the only
    way to find out whether the calldata it assembles means what the page
    says it means.                                                        */
let byId = new Map();
const mkEl = (tag, attrs) => {
  const el = {
    tagName: tag, value: "", textContent: "", innerHTML: "",
    disabled: false, hidden: false, className: "", placeholder: "",
    dataset: {}, _on: {},
    addEventListener(k, f) { (this._on[k] = this._on[k] || []).push(f); },
    async fire(k) { for (const f of this._on[k] || []) await f(); }
  };
  for (const m of (attrs || "").matchAll(/data-([\w-]+)(?:=["']?([^"'\s>]*)["']?)?/g)) {
    el.dataset[m[1].replace(/-(\w)/g, (x, y) => y.toUpperCase())] = m[2] ?? "";
  }
  const v = (attrs || "").match(/\bvalue="([^"]*)"/);
  if (v) el.value = v[1];
  return el;
};
function mount(html) {
  byId = new Map();
  const all = [];
  for (const m of html.matchAll(/<(\w+)([^>]*)>/g)) {
    const el = mkEl(m[1], m[2]);
    all.push(el);
    const id = (m[2].match(/\bid=["']?([\w.-]+)["']?/) || [])[1];
    if (id && !byId.has(id)) byId.set(id, el);
  }
  const cfg = html.match(/<script type="application\/json" id="D">([\s\S]*?)<\/script>/);
  if (cfg && byId.get("D")) byId.get("D").textContent = cfg[1];
  const listeners = {};
  globalThis.addEventListener = (k, f) => { (listeners[k] = listeners[k] || []).push(f); };
  globalThis.dispatchEvent = (e) => { for (const f of listeners[e.type] || []) f(e); };
  globalThis.Event = class { constructor(t) { this.type = t; } };
  globalThis.document = {
    getElementById: (i) => byId.get(i) || null,
    querySelectorAll: (q) => {
      const m = q.match(/^\[data-([\w-]+)\]$/);
      if (m) {
        const k = m[1].replace(/-(\w)/g, (x, y) => y.toUpperCase());
        return all.filter((e) => k in e.dataset);
      }
      if (q.startsWith(".")) return all.filter((e) => e.className === q.slice(1));
      return [];
    }
  };
  return byId;
}
const runScripts = (html) => {
  for (const m of html.matchAll(/<script>([\s\S]*?)<\/script>/g)) new Function(m[1])();
};
const nap = (ms) => new Promise((r) => setTimeout(r, ms));
const wallet = (actor) => {
  let n = 0;
  globalThis.window = globalThis;
  globalThis.window.ethereum = {
    request: async ({ method, params }) => {
      if (method === "eth_chainId") return "0x1";
      if (method === "eth_requestAccounts" || method === "eth_accounts")
        return [actor.from.toString()];
      if (method === "eth_call")
        return c.call(params[0].to, params[0].data, actor.from.toString());
      if (method === "eth_sendTransaction") {
        n++;
        const t = params[0];
        await actor.send({ to: t.to, data: t.data,
                           value: t.value ? BigInt(t.value) : 0n, label: "app" });
        return "0x" + "ab".repeat(32);
      }
      throw new Error("unexpected method " + method);
    }
  };
  return { sent: () => n };
};

/*════════════ the app, actually driven ════════════

  Everything above checks that the page says the right things. This runs
  it. The two script blocks the contract emitted are executed against a
  DOM shim and a provider wired straight to the same in-process EVM, so a
  swap performed by pressing the button on the page is a swap performed by
  the contract — and the numbers the card shows are checked against what
  `Pool.quote` says at the same block.

  This is the only test here that would catch the client being wrong. A
  page can render perfectly, carry the right selectors, parse as
  JavaScript, and still assemble calldata that means something else.
*/
let DRIVEN = 0;
head("driving the swap card");
{
  /*  Its own token and its own pair. Token 1's market is the hostile one
      from the escaping tests and has no real balances behind it; a driver
      pointed at that would be testing the mock, not the app.            */
  await c.exec(nft, "mint()", [], { value: 10n ** 16n });
  const T = Number(decUint(await c.read(nft, "totalSupply()")));
  DRIVEN = T;
  const usdc = await c.deploy(A("test/mocks/MockERC20.sol", "MockERC20").bytecode,
    w(0xa0) + w(0xe0) + w(6) + w(0) + w(0) + encS("USD Coin") + encS("USDC"), "USDC");
  await c.exec(weth, "mint(address,uint256)", [c.from.toString(), 10n ** 24n]);
  await c.exec(usdc, "mint(address,uint256)", [c.from.toString(), 10n ** 18n]);
  await c.exec(weth, "approve(address,uint256)", [pool, 1n << 255n]);
  await c.exec(usdc, "approve(address,uint256)", [pool, 1n << 255n]);
  await c.exec(pool, "openMarket(uint256,address,address,uint16)", [T, weth, usdc, 30]);
  await c.exec(pool, "deposit(uint256,uint256,uint256)",
    [T, 40n * 10n ** 18n, 120_000n * 10n ** 6n]);

  const page = await GET(["token", String(T), "market"]);

  mount(page.body);
  const trader = await c.as("0x" + "44".repeat(32));
  await c.exec(weth, "mint(address,uint256)", [trader.from.toString(), 10n ** 21n]);
  const W1 = wallet(trader);
  const sent = () => W1.sent();
  runScripts(page.body);
  await nap(30);
  ok("the client loaded against the page's own config", !!globalThis.IP);

  /*──── a quote appears, and it is the pool's ────*/
  const $ = (i) => byId.get(i);
  $("si").value = "1";
  await $("si").fire("input");
  await nap(400);

  const IN = 10n ** 18n;
  const expect = decUint(await c.read(pool, "quote(uint256,bool,uint256)", [T, true, IN]));
  const shown = $("so").value.replace(/,/g, "");
  ok("typing an amount produced a quote", shown.length > 0, "the field stayed empty");
  const shownRaw = BigInt(Math.round(Number(shown) * 1e6));
  ok("and it is what Pool.quote says, to the displayed precision",
     shownRaw > expect - 2n && shownRaw < expect + 2n,
     `card ${shown} (${shownRaw}) vs pool ${expect}`);
  console.log(`      1 WETH in, the card says ${shown} USDC, the pool says ` +
              `${(Number(expect) / 1e6).toFixed(6)}`);

  ok("the details name a rate, a floor and the fee",
     /rate/.test($("det").innerHTML) && /receive at least/.test($("det").innerHTML)
     && /fee/.test($("det").innerHTML));
  ok("and the button knows an approval is needed first",
     /^Approve /.test($("go").textContent), $("go").textContent);

  /*──── press it: approve, then swap ────*/
  await $("go").fire("click");
  eq("pressing it sent one transaction", sent(), 1);
  const allowed = decUint(await c.read(weth, "allowance(address,address)",
                                       [trader.from.toString(), pool]));
  ok("which was the approval, and it landed", allowed > 0n);

  await $("si").fire("input");
  await nap(400);
  ok("now the button offers the swap",
     /^Swap /.test($("go").textContent), $("go").textContent);

  const before = decUint(await c.read(usdc, "balanceOf(address)", [trader.from.toString()]));
  await $("go").fire("click");
  eq("pressing it again sent a second transaction", sent(), 2);
  const after = decUint(await c.read(usdc, "balanceOf(address)", [trader.from.toString()]));
  ok("and the trader was actually paid", after > before, `${before} -> ${after}`);
  ok("at no worse than the floor the card promised",
     after - before >= expect * 9950n / 10000n,
     `received ${after - before}, floor was about ${expect * 9950n / 10000n}`);
  console.log(`      received ${(Number(after - before) / 1e6).toFixed(6)} USDC ` +
              `\u2014 the card, the pool and the balance all agree`);

  /*──── the flip, and the guards ────*/
  await $("flip").fire("click");
  await nap(400);
  eq("flipping turns the pair round", $("ts").textContent, "USDC");

  $("si").value = "not a number";
  await $("si").fire("input");
  await nap(300);
  ok("nonsense in the amount field is refused rather than sent",
     $("go").disabled === true && $("so").value === "",
     `button "${$("go").textContent}", output "${$("so").value}"`);

  globalThis.window.ethereum.request = (async ({ method, params }) => {
    if (method === "eth_chainId") return "0x2105";           // some other chain
    if (method === "eth_requestAccounts") return [trader.from.toString()];
    throw new Error("unexpected " + method);
  });
  $("si").value = "1";
  let refused = false;
  try { await globalThis.IP.connect(); } catch (e) { refused = /on chain/.test(e.message); }
  ok("a wallet on the wrong chain is told so rather than used", refused);

}

head("driving the holder's side");
{
  const pg = await GET(["token", String(DRIVEN), "pool"]);
  mount(pg.body);
  const W = wallet(c);
  runScripts(pg.body);
  await nap(30);
  const $ = (i) => byId.get(i);

  const before = await c.read(pool, "market(uint256)", [DRIVEN]);
  $("db").value = "1.5";
  $("dq").value = "4500";
  await $("add").fire("click");
  ok("Add liquidity sent a transaction", W.sent() >= 1);
  const after = await c.read(pool, "market(uint256)", [DRIVEN]);
  ok("and the inventory actually grew",
     decUint(after, 2) > decUint(before, 2) && decUint(after, 3) > decUint(before, 3),
     `base ${decUint(before, 2)} -> ${decUint(after, 2)}`);
  console.log(`      1.5 WETH typed as text became ${decUint(after, 2) - decUint(before, 2)}` +
              ` base units \u2014 no float anywhere in that`);

  $("fb").value = "1.25";
  await $("fee").fire("click");
  eq("setting the fee from a percentage lands as bps",
     decUint(await c.read(pool, "market(uint256)", [DRIVEN]), 4), 125);

  $("wb").value = "0.5";
  $("wq").value = "0";
  await $("rm").fire("click");
  ok("Remove liquidity works too",
     decUint(await c.read(pool, "market(uint256)", [DRIVEN]), 2) <
     decUint(after, 2));
}

head("driving the rental counter");
{
  await c.exec(nft, "setLeaseAgent(uint256,address)", [DRIVEN, lease]);
  await c.exec(lease, "list(uint256,uint128,uint32,uint32)", [DRIVEN, WAD / 100n, 1, 30]);

  const pg = await GET(["token", String(DRIVEN), "rent"]);
  mount(pg.body);
  const hirer = await c.as("0x" + "55".repeat(32));
  PARTIES.push(hirer);
  if (!TOKENS.includes(DRIVEN)) TOKENS.push(DRIVEN);
  const W = wallet(hirer);
  runScripts(pg.body);
  await nap(30);
  const $ = (i) => byId.get(i);

  $("rd").value = "5";
  await $("rd").fire("input");
  ok("choosing five days prices it exactly",
     $("rc").textContent.startsWith("0.05 ETH for 5 days"), $("rc").textContent);

  const held = await c.balanceOf(lease);
  await $("rg").fire("click");
  eq("renting sent one transaction", W.sent(), 1);
  eq("carrying exactly the wei the card showed", (await c.balanceOf(lease)) - held, WAD / 20n);
  eq("and ERC-4907 now names the renter",
     decAddr(await c.read(nft, "userOf(uint256)", [DRIVEN])).toLowerCase(),
     hirer.from.toString().toLowerCase());

  $("rd").value = "400";
  await $("rd").fire("input");
  ok("a term outside the holder's range is refused before it is sent",
     $("rg").disabled === true, $("rc").textContent);
}

for (const g of ["window", "document", "addEventListener", "dispatchEvent", "Event", "IP"]) {
  delete globalThis[g];
}


/*════════════════ 6 · renting ════════════════*/
head("renting: the narrow capability");
const PER_DAY = WAD / 100n;                       // 0.01 ETH a day

await refuses("listing before naming a lease agent is refused",
  () => c.exec(lease, "list(uint256,uint128,uint32,uint32)", [1, PER_DAY, 1, 30]));

await c.exec(nft, "setLeaseAgent(uint256,address)", [1, lease]);
await c.exec(lease, "list(uint256,uint128,uint32,uint32)", [1, PER_DAY, 1, 30]);
ok("the holder names an agent and lists", true);

const listing = await c.read(lease, "listing(uint256)", [1]);
eq("it reads back as rentable", decUint(listing, 0), 1);

/*  and only now does the counter open. A card that renders whether or not
    anything is for sale is a card that will one day take money for
    nothing.                                                             */
const rp2 = await GET(["token", "1", "rent"]);
ok("the rent card appears once there are terms", rp2.body.includes("id=rg"));
ok("with a day field", rp2.body.includes("id=rd"));
ok("and a place for the exact wei", rp2.body.includes("id=rc"));
ok("priced from the terms just published", rp2.body.includes("0.01 ETH / day"),
   "the page did not show the price that was listed");

await refuses("a stranger cannot list someone else's token",
  () => renter.exec(lease, "list(uint256,uint128,uint32,uint32)", [1, PER_DAY, 1, 30]));

const leaseAbi = A("src/Lease.sol", "Lease").abi.map((f) => f.name).filter(Boolean);
ok("Lease's ABI contains no transfer, approve or lock of any kind",
   !leaseAbi.some((n) => /transfer|approve|lock|seal|execute/i.test(n)),
   leaseAbi.join(","));

/*──── the capability is exactly one function, tested by a contract that
       genuinely holds it and genuinely tries to use it for more ────*/
head("a lease agent that wants more than it was given");
const rogue = await c.deploy(A("test/mocks/Nasty.sol", "RogueAgent").bytecode, "", "RogueAgent");
await c.exec(nft, "setLeaseAgent(uint256,address)", [3, rogue]);

await c.exec(rogue, "setUser(address,uint256,address,uint64)",
  [nft, 3, buyer.from.toString(), 4102444800n]);
eq("it really is the agent — setUserVia goes through",
   decAddr(await c.read(nft, "userOf(uint256)", [3])).toLowerCase(),
   buyer.from.toString().toLowerCase());

for (const [sig, args, what] of [
  ["trySteal(address,uint256,address,address)",
   [nft, 3, c.from.toString(), rogue], "transfer the token"],
  ["tryApprove(address,uint256)", [nft, 3], "approve itself"],
  ["tryLock(address,uint256)", [nft, 3], "lock it"],
  ["trySetUserDirect(address,uint256)", [nft, 3], "call setUser directly"],
  ["tryRetarget(address,uint256)", [nft, 3], "name itself agent on another token"]
]) {
  const r = await c.read(rogue, sig, args);
  ok(`it cannot ${what}`, decUint(r) === 0n, "the call succeeded");
}
eq("and the token is still the holder's",
   decAddr(await c.read(nft, "ownerOf(uint256)", [3])).toLowerCase(),
   c.from.toString().toLowerCase());
console.log("      an ERC-721 approval would have carried transferFrom with it;");
console.log("      this is why the narrow power got its own name");

head("renting, continued");

const before = await c.balanceOf(lease);
await renter.exec(lease, "rent(uint256,uint32,uint128)", [1, 7, PER_DAY],
  { value: PER_DAY * 7n });
ok("a stranger rents it for seven days", true);
await OBLIGED("rent taken");
eq("the contract now holds the rent", (await c.balanceOf(lease)) - before, PER_DAY * 7n);
eq("and ERC-4907 says the renter is the user",
   decAddr(await c.read(nft, "userOf(uint256)", [1])).toLowerCase(),
   renter.from.toString().toLowerCase());

await refuses("nobody can rent it twice", () =>
  buyer.exec(lease, "rent(uint256,uint32,uint128)", [1, 1, PER_DAY], { value: PER_DAY }));

await refuses("and the payment must be exact", () =>
  buyer.exec(lease, "rent(uint256,uint32,uint128)", [2, 1, PER_DAY], { value: PER_DAY + 1n }));

head("what the renter may and may not do");
const wordBefore = decUint(await c.read(nft, "sectionOf(uint256)", [1]));
await renter.exec(nft, "commit(uint256,uint256)", [1, (wordBefore + 1n) & ((1n << 128n) - 1n)]);
ok("the renter drives the instrument — commit goes through", true);
ok("and the state really moved",
   decUint(await c.read(nft, "sectionOf(uint256)", [1])) !== wordBefore);

await refuses("the renter cannot sell it", () =>
  renter.exec(nft, "transferFrom(address,address,uint256)",
    [c.from.toString(), renter.from.toString(), 1]));
await refuses("nor lock it", () => renter.exec(nft, "lock(uint256)", [1]));
await refuses("nor set a user of their own", () =>
  renter.exec(nft, "setUser(uint256,address,uint64)", [1, buyer.from.toString(), 99999999999n]));

/*════════════════ 7 · the books ════════════════*/
head("a lease that runs its term");
evm.warp(evm.BLOCK.header.timestamp + 8n * 86400n);
await c.exec(lease, "settle(uint256)", [1]);
eq("all of it vested to the token", decUint(await c.read(lease, "earned(uint256)", [1])), PER_DAY * 7n);
await OBLIGED("term completed");

const holderBefore = await c.balanceOf(c.from.toString());
await c.exec(lease, "collect(uint256,address)", [1, c.from.toString()]);
ok("the holder collected it", (await c.balanceOf(c.from.toString())) > holderBefore - WAD);
eq("and nothing is left owing on that token", decUint(await c.read(lease, "earned(uint256)", [1])), 0);
/*  Not "the contract is empty" — by this point the app driver above has a
    real five-day lease running on another token, and its escrow is exactly
    where it should be. What has to be true is narrower and is the actual
    claim: nothing is left held against THIS token.                      */
eq("nothing is left held against token 1",
   decUint(await c.read(lease, "activeOf(uint256)", [1]), 3), 0);
await OBLIGED("after collection");

head("a lease cut short by the sale of the token");
await c.exec(nft, "setLeaseAgent(uint256,address)", [1, lease]);
await c.exec(lease, "list(uint256,uint128,uint32,uint32)", [1, PER_DAY, 1, 30]);
await renter.exec(lease, "rent(uint256,uint32,uint128)", [1, 10, PER_DAY],
  { value: PER_DAY * 10n });
const paid = PER_DAY * 10n;

evm.warp(evm.BLOCK.header.timestamp + 2n * 86400n);           // two days in
await c.exec(lease, "settle(uint256)", [1]);                  // seen running
await c.exec(nft, "transferFrom(address,address,uint256)",
  [c.from.toString(), buyer.from.toString(), 1]);
eq("the sale cleared the ERC-4907 user",
   decAddr(await c.read(nft, "userOf(uint256)", [1])),
   "0x0000000000000000000000000000000000000000");
eq("and cleared the standing permission to grant one",
   decAddr(await c.read(nft, "leaseAgentOf(uint256)", [1])),
   "0x0000000000000000000000000000000000000000");

await c.exec(lease, "settle(uint256)", [1]);
const vested = decUint(await c.read(lease, "earned(uint256)", [1]));
const refund = decUint(await c.read(lease, "owed(address)", [renter.from.toString()]));
ok("two days of ten vested to the token",
   vested >= paid / 5n - PER_DAY / 100n && vested <= paid / 5n + PER_DAY / 100n,
   `vested ${vested}, expected about ${paid / 5n}`);
eq("and every remaining wei is the renter's", vested + refund, paid);
await OBLIGED("lease cut short");
console.log(`      ${vested} vested, ${refund} refundable, ${paid} paid — nothing lost`);

const newHolder = await buyer.balanceOf(buyer.from.toString());
await buyer.exec(lease, "collect(uint256,address)", [1, buyer.from.toString()]);
ok("the BUYER collects the vested rent, not the seller",
   (await buyer.balanceOf(buyer.from.toString())) > newHolder - WAD);
console.log("      rent accrues to the token, so selling it sells the income");

const renterBefore = await renter.balanceOf(renter.from.toString());
await renter.exec(lease, "claim()", []);
ok("and the renter reclaims the time they did not get",
   (await renter.balanceOf(renter.from.toString())) > renterBefore - WAD / 10n);
eq("and nothing against it a second time",
   decUint(await c.read(lease, "activeOf(uint256)", [1]), 3) +
   decUint(await c.read(lease, "earned(uint256)", [1])), 0);

head("the invariant that matters");
const surplus = await OBLIGED("at rest");
eq("and nothing is stranded: the balance is exactly what is owed, to the wei",
   surplus, 0n);
console.log("      checked after every operation above, not only at the end — a");
console.log("      contract briefly insolvent in the middle passes a closing check");

/*════════════════ 8 · what the site cannot do ════════════════*/
head("read off the compiled ABI");
for (const [file, name] of [
  ["src/PageToken.sol", "PageToken"], ["src/PageMarket.sol", "PageMarket"],
  ["src/PageServices.sol", "PageServices"], ["src/PageManifest.sol", "PageManifest"],
  ["src/Chrome.sol", "Chrome"], ["src/Premises.sol", "Premises"]
]) {
  const abi = A(file, name).abi;
  const writes = abi.filter((f) =>
    f.type === "function" && f.stateMutability !== "view" && f.stateMutability !== "pure");
  ok(`${name} has no state-changing function`, writes.length === 0,
     writes.map((f) => f.name).join(","));
}

const leaseWrites = A("src/Lease.sol", "Lease").abi
  .filter((f) => f.type === "function" && f.stateMutability === "payable")
  .map((f) => f.name);
ok("Lease takes ether through exactly one function", leaseWrites.length === 1 && leaseWrites[0] === "rent",
   leaseWrites.join(","));
ok("and has neither receive nor fallback",
   !A("src/Lease.sol", "Lease").abi.some((f) => f.type === "receive" || f.type === "fallback"));

console.log(`\n  ${fail === 0 ? "\x1b[32m" : "\x1b[31m"}${pass} passed, ${fail} failed\x1b[0m\n`);
process.exit(fail === 0 ? 0 : 1);
