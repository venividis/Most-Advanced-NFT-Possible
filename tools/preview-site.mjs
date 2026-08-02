#!/usr/bin/env node
/*───────────────────────────────────────────────────────────────────────────
  IPSEITY · look at the site

  Deploys the whole collection into an in-process EVM, opens a market with
  real inventory, lists the token for rent, then fetches each route over
  ERC-5219 and writes the bytes to dist/site/. Open them in a browser.

  What you get is exactly what a `web3://` client would be handed — these
  are not mock-ups, they are the contract's own output. The one thing that
  will not work from a file:// URL is the wallet, because a wallet needs an
  origin; served over web3:// or a gateway it connects.

    node tools/preview-site.mjs
    node tools/preview-site.mjs --serve 8080     and read them over http
───────────────────────────────────────────────────────────────────────────*/
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { compile, artifact } from "./compile.mjs";
import * as evm from "./evm.mjs";
import { Chain, encodeAddressArg, decUint, decAddr } from "./evm.mjs";
import { deploySite, getter } from "./site.mjs";
import { createAddressFromString } from "@ethereumjs/util";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const OUT = path.join(ROOT, "dist", "site");
const REGISTRY = "0x000000006551c19487814612e58FE06813775758";
const w = (n) => BigInt(n).toString(16).padStart(64, "0");
const encS = (t) => w(t.length) + Buffer.from(t).toString("hex").padEnd(64, "0");

console.log("\n  \x1b[1mIPSEITY · the site, rendered\x1b[0m");

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

/* the real document, so /live is the real instrument */
const plan = JSON.parse(fs.readFileSync(path.join(ROOT, "dist/shards.json"), "utf8"));
for (const sh of plan.head) await c.exec(engine, "loadHead(bytes)", [sh.data]);
for (const sh of plan.body) await c.exec(engine, "loadBody(bytes)", [sh.data]);
await c.exec(engine, "setInflatedSize(uint32)", [plan.inflatedSize]);
await c.exec(engine, "freeze()", []);

const pool = await c.deploy(A("src/Pool.sol", "Pool").bytecode,
  encodeAddressArg(nft) + w(10n ** 30n) + encodeAddressArg(c.from.toString()) + w(0), "Pool");
await c.exec(nft, "setPool(address)", [pool]);
const lease = await c.deploy(A("src/Lease.sol", "Lease").bytecode, encodeAddressArg(nft));

/*  A Uniswap deployment to preview against. The pages that read Uniswap are
    not interesting with nothing to read: they render the "no venue" notice,
    which is correct and is not what anybody opens a preview to look at.  */
const M = (n) => A("test/mocks/UniV3.sol", n).bytecode;
const uniF = await c.deploy(M("MockV3Factory"), "", "v3Factory");
const book = await c.deploy(M("MockBook"), "", "book");
const quoter = await c.deploy(M("MockQuoter"), encodeAddressArg(book), "QuoterV2");
const router = await c.deploy(M("MockRouterV3"), encodeAddressArg(book), "SwapRouter");
const npm_ = await c.deploy(M("MockPositions"), "", "Positions");
const gov = await c.deploy(M("MockGovernor"), "", "Governor");
const govTok = await c.deploy(M("MockVotes"), "", "UNI");

/*──── a market with something in it, and a token for rent ────*/
for (let i = 0; i < 3; i++) await c.exec(nft, "mint()", [], { value: 10n ** 16n });

const mk20 = async (name, sym, dec) => c.deploy(
  A("test/mocks/MockERC20.sol", "MockERC20").bytecode,
  w(0xa0) + w(0xe0) + w(dec) + w(0) + w(0) + encS(name) + encS(sym), sym);
const weth = await mk20("Wrapped Ether", "WETH", 18);
const usdc = await mk20("USD Coin", "USDC", 6);

await c.exec(weth, "mint(address,uint256)", [c.from.toString(), 10n ** 24n]);
await c.exec(usdc, "mint(address,uint256)", [c.from.toString(), 10n ** 18n]);
await c.exec(weth, "approve(address,uint256)", [pool, (1n << 255n)]);
await c.exec(usdc, "approve(address,uint256)", [pool, (1n << 255n)]);
await c.exec(pool, "openMarket(uint256,address,address,uint16)", [1, weth, usdc, 30]);
await c.exec(pool, "deposit(uint256,uint256,uint256)",
  [1, 40n * 10n ** 18n, 120_000n * 10n ** 6n]);

/*  Two v3 pools for the same pair at different depths, and a memory on the
    deeper one, so the preview shows a chart rather than the notice that
    says why there is not one.                                            */
const tk = weth.toLowerCase() < usdc.toLowerCase() ? -196256n : 196256n;
await c.exec(uniF, "make(address,address,uint24,uint160,int24,uint128)",
  [weth, usdc, 500n, 1n << 96n, tk, 10n ** 6n]);
await c.exec(uniF, "make(address,address,uint24,uint160,int24,uint128)",
  [weth, usdc, 3000n, 1n << 96n, tk, 9n * 10n ** 18n]);
await c.exec(book, "set(address,address,uint24,uint256)", [weth, usdc, 500n, 2900n * 10n ** 6n]);
await c.exec(book, "set(address,address,uint24,uint256)", [weth, usdc, 3000n, 2995n * 10n ** 6n]);
const deepPool = decAddr(await c.read(uniF, "getPool(address,address,uint24)",
  [weth, usdc, 3000n]));
await c.exec(deepPool, "setHistory(uint32,uint16)", [200000n, 300n]);
const vault = await c.deploy(A("test/mocks/UniV3.sol", "MockVault").bytecode,
  encodeAddressArg(usdc), "MockVault");

/*  A second and third market, so the picker has something to pick. They
    are on later tokens on purpose: the directory walks the pool's own list
    now, and a reader should be able to see that it finds them.          */
const dai = await mk20("Dai Stablecoin", "DAI", 18);
const wbtc = await mk20("Wrapped Bitcoin", "WBTC", 8);
for (const t of [2, 3]) {
  await c.exec(weth, "mint(address,uint256)", [c.from.toString(), 10n ** 22n]);
}
await c.exec(dai, "mint(address,uint256)", [c.from.toString(), 10n ** 24n]);
await c.exec(wbtc, "mint(address,uint256)", [c.from.toString(), 10n ** 12n]);
await c.exec(dai, "approve(address,uint256)", [pool, 1n << 255n]);
await c.exec(wbtc, "approve(address,uint256)", [pool, 1n << 255n]);
await c.exec(pool, "openMarket(uint256,address,address,uint16)", [2, weth, dai, 5]);
await c.exec(pool, "deposit(uint256,uint256,uint256)",
  [2, 12n * 10n ** 18n, 36_000n * 10n ** 18n]);
await c.exec(pool, "openMarket(uint256,address,address,uint16)", [3, wbtc, usdc, 100]);
await c.exec(pool, "deposit(uint256,uint256,uint256)",
  [3, 3n * 10n ** 8n, 200_000n * 10n ** 6n]);

await c.exec(nft, "setLeaseAgent(uint256,address)", [1, lease]);
await c.exec(lease, "list(uint256,uint128,uint32,uint32)", [1, 10n ** 16n, 1, 30]);

const site = await deploySite(c, A, {
  hub: nft, pool, lease,
  uniswap: { name: "preview", factory: uniF, quoter, router, routerKind: 0,
             positions: npm_, wrapped: weth, governor: gov, govToken: govTok }
});
const GET = getter(c, site.premises);

/*──── fetch and write ────*/
fs.mkdirSync(OUT, { recursive: true });
const pages = [
  [[], "index.html", "the collection"],
  [["token", "1"], "token-1.html", "the counter"],
  [["token", "1", "market"], "token-1-market.html", "the swap card"],
  [["token", "1", "pool"], "token-1-pool.html", "the holder's side"],
  [["token", "1", "rent"], "token-1-rent.html", "renting"],
  [["token", "1", "vault"], "token-1-vault.html", "the two hands"],
  [["token", "1", "sigil.svg"], "token-1-sigil.svg", "the still"],
  [["open"], "open.html", "open markets"],
  [["assets"], "assets.html", "what is traded here"],
  [["swap"], "swap.html", "any pair, on Uniswap v3"],
  [["pools"], "pools.html", "liquidity at a range you choose"],
  [["limit"], "limit.html", "a range order"],
  [["explore"], "explore.html", "a few tokens to start from"],
  [["explore", weth.toLowerCase()], "explore-token.html", "one token, and its chart"],
  [["earn"], "earn.html", "bring a vault"],
  [["earn", vault.toLowerCase()], "earn-vault.html", "a vault, verified"],
  [["vote"], "vote.html", "governance"],
  [["token", "1", "services.json"], "token-1-services.json", "machine-readable"],
  [["services.json"], "services.json", "the directory, machine-readable"]
];

console.log("");
for (const [route, file, what] of pages) {
  const r = await GET(route);
  /*  Written with root-relative links rewritten to the flat filenames, so
      the pages can be opened straight off disk. Nothing else is touched —
      what is inside every one of these is the contract's own bytes.     */
  let body = r.body;
  if (file.endsWith(".html")) {
    body = body
      .replace(/href="\/"/g, 'href="index.html"')
      .replace(/href="\/open"/g, 'href="open.html"')
      .replace(/href="\/assets"/g, 'href="assets.html"')
      .replace(/href="\/swap"/g, 'href="swap.html"')
      .replace(/href="\/pools"/g, 'href="pools.html"')
      .replace(/href="\/limit"/g, 'href="limit.html"')
      .replace(/href="\/earn"/g, 'href="earn.html"')
      .replace(/href="\/vote"/g, 'href="vote.html"')
      .replace(/href="\/explore\/0x[0-9a-fA-F]+"/g, 'href="explore-token.html"')
      .replace(/href="\/explore"/g, 'href="explore.html"')
      .replace(/href="\/services\.json"/g, 'href="services.json"')
      .replace(/(href|src)="\/token\/(\d+)\/services\.json"/g, '$1="token-$2-services.json"')
      .replace(/(href|src)="\/token\/(\d+)\/sigil\.svg"/g, '$1="token-$2-sigil.svg"')
      .replace(/(href|src)="\/token\/(\d+)\/([a-z]+)"/g, '$1="token-$2-$3.html"')
      .replace(/(href|src)="\/token\/(\d+)"/g, '$1="token-$2.html"');
  }
  fs.writeFileSync(path.join(OUT, file), body);
  console.log(`  ${String(r.status)}  ${file.padEnd(28)} ${String(body.length).padStart(7)} B` +
              `  \x1b[2m${what}\x1b[0m`);
}

console.log(`\n  wrote ${pages.length} files to dist/site/`);
console.log("  \x1b[2mopen dist/site/token-1-market.html — the wallet needs a real");
console.log("  origin, so connecting works over web3:// or a gateway, not file://\x1b[0m\n");

const serveAt = process.argv.indexOf("--serve");
if (serveAt > 0) {
  const port = Number(process.argv[serveAt + 1] || 8080);
  const http = await import("node:http");
  const types = { ".html": "text/html", ".json": "application/json", ".svg": "image/svg+xml" };
  http.createServer((req, res) => {
    const name = (req.url === "/" ? "/index.html" : req.url).split("?")[0];
    const f = path.join(OUT, path.basename(name));
    if (!fs.existsSync(f)) { res.writeHead(404); return res.end("no such section"); }
    res.writeHead(200, { "Content-Type": types[path.extname(f)] || "text/plain" });
    res.end(fs.readFileSync(f));
  }).listen(port, () => console.log(`  serving dist/site on http://localhost:${port}\n`));
}
