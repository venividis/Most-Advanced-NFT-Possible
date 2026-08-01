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
ok("and the page carries no unexpected opening script tag",
   (mk.body.match(/<script>/g) || []).length === 1,
   `found ${(mk.body.match(/<script>/g) || []).length} <script> tags; only Chrome's client is expected`);

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
ok("it says what window it looked at", /Looked at tokens \d+ to \d+/.test(dir.body));
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

/*════════════════ 5 · the calldata a page hands the browser ════════════════*/
head("the buttons carry calldata a contract built");
const rentPage = await GET(["token", "1", "rent"]);
const calls = [...rentPage.body.matchAll(/data-call="(0x[0-9a-f]+)"/g)].map((x) => x[1]);
ok("the rent page emits calldata", calls.length > 0);
const wantSettle = sel4("settle(uint256)");
ok("settle(uint256) is there with its argument already packed",
   calls.some((d) => d.startsWith(wantSettle) && d.length === 10 + 64),
   calls.join(" "));
const marketCalls = [...mk.body.matchAll(/data-call="(0x[0-9a-f]+)"/g)].map((x) => x[1]);
ok("the market page pre-packs quote(uint256,bool,uint256)",
   marketCalls.some((d) => d.startsWith(sel4("quote(uint256,bool,uint256)"))));
ok("and swap(...), with id and direction already fixed",
   marketCalls.some((d) => d.startsWith(sel4("swap(uint256,bool,uint256,uint256,address,uint256)"))
                           && d.length === 10 + 128));
ok("every emitted prefix is a whole number of words after the selector",
   marketCalls.concat(calls).every((d) => d === "0x" || (d.length - 10) % 64 === 0),
   marketCalls.concat(calls).filter((d) => d !== "0x" && (d.length - 10) % 64 !== 0).join(" "));


/*  The invariant Lease exists to keep. Every wei it holds is spoken for by
    exactly one of three ledgers, and the balance has to cover all of them
    at once — not at the end, at every step. Asserting it once at the close
    would pass for a contract that was briefly insolvent in the middle.   */
const OBLIGED = async (label) => {
  let owedTotal = 0n;
  for (const a of [c, renter, buyer])
    owedTotal += decUint(await c.read(lease, "owed(address)", [a.from.toString()]));
  let held = 0n;
  for (const t of [1, 2, 3]) {
    held += decUint(await c.read(lease, "earned(uint256)", [t]));
    const act = await c.read(lease, "activeOf(uint256)", [t]);
    held += decUint(act, 3);              // renter, start, until, paid, seen
  }
  const bal = await c.balanceOf(lease);
  ok(`solvent: ${label}`, bal >= owedTotal + held,
     `balance ${bal} < obligations ${owedTotal + held}`);
  return bal - (owedTotal + held);
};

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
eq("the contract holds nothing further", await c.balanceOf(lease), 0n);
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
eq("the contract is empty again", await c.balanceOf(lease), 0n);

head("the invariant that matters");
const surplus = await OBLIGED("at rest");
eq("and nothing is stranded: the balance is exactly what is owed", surplus, 0n);
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
