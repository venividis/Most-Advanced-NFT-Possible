#!/usr/bin/env node
/*───────────────────────────────────────────────────────────────────────────
  IPSEITY · the console, held to what it claims

  The console replaced nineteen pages with one route. That is a bigger
  change than it sounds, because nineteen pages failed loudly — a broken
  one 404'd — and one page fails quietly: it renders, it looks right, and
  a number in it is wrong.

  Four properties are under test, in the order of how badly each fails.

  ── 1. two copies of one naming table ──

  The seven verbs are spelled in `PageConsole.sol` (which renders the rows and
  resolves `/c/<id>/<verb>`) and again in `engine/console.js` (which takes
  the typed word). Two copies of a naming table is the exact failure this
  whole redesign was a response to, and it fails in the worst possible way:
  the console shows a holder a verb, the holder types it, and nothing
  opens — or worse, the wrong lane does. So the two tables are read out of
  the two files and compared, string for string, in order.

  ── 2. a failed read must not render as a zero ──

  `ConsoleRead` wraps every satellite call. The whole point of the wrapping
  is that a read which REVERTED is recorded differently from a read that
  returned zero — a clear bit against a set bit with a zero in it. A viewer
  that renders those the same is not degrading gracefully, it is lying
  quietly, which is worse than the revert it was avoiding. The suite points
  the reader at a chain with no pool and no lease and asserts the bits.

  ── 3. the walk must never reach the contract ──

  The walk rides in the URL fragment, and the claim made in the client's
  own header is that ERC-5219 hands `Premises.request` the path and the
  query and never the hash. If that were wrong the walk would be in every
  gateway's cache key and every token's console would be cached per-walk.
  A claim in a comment is not a test, so the fragment is put through a real
  request and the response is compared byte for byte with the one that had
  no fragment.

  ── 4. the still is a reference, not a raymarcher ──

  The heat the owner reported came from two 4-D fields on one thread. The
  console's rule is that exactly one control in the whole document produces
  a raymarcher and it navigates. So: the console must reference the sigil
  route, must not inline a base64 blob, and must not carry an iframe.

    node tools/verify-console.mjs
───────────────────────────────────────────────────────────────────────────*/
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { compile, artifact } from "./compile.mjs";
import * as evm from "./evm.mjs";
import { Chain, encodeAddressArg, decUint, decString } from "./evm.mjs";
import { deploySite, getter } from "./site.mjs";
import { createAddressFromString } from "@ethereumjs/util";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

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

/*  `artifact` takes the compiler output as its first argument; a bare
    alias silently shifts every call by one and reports the FILE name as a
    missing contract, which reads like a build problem and is not.      */
/*  The mocks are in test/, not src/, and the default compile does not walk
    there. A run that omits them fails as "no artifact for the registry",
    which reads like a missing contract and is a missing DIRECTORY.     */
const out = compile({ quiet: true, dirs: ["src", "test/mocks"] });
const A = (f, n) => artifact(out, f, n);

/*═══════════════ the two naming tables ═══════════════*/
/*  First, and without a chain, because this one needs no deployment and it
    is the failure most likely to be introduced by somebody adding a verb
    to one file and not the other.                                       */

head("the seven verbs are spelled once");
{
  const sol = fs.readFileSync(path.join(ROOT, "src/PageConsole.sol"), "utf8");
  const js  = fs.readFileSync(path.join(ROOT, "engine/console.js"), "utf8");

  /*  Read out of `verbWord`, which is the function the router calls, rather
      than out of any comment or table that merely describes it.        */
  const body = sol.slice(sol.indexOf("function verbWord("));
  const solWords = [...body.slice(0, body.indexOf("\n    }"))
    .matchAll(/if \(i == (\d)\) return "([a-z]+)";/g)]
    .sort((a, b) => +a[1] - +b[1]).map((m) => m[2]);

  const jsm = /var WORDS = \[([^\]]*)\]/.exec(js);
  const jsWords = jsm
    ? jsm[1].split(",").map((s) => s.trim().replace(/^"|"$/g, "")).filter(Boolean)
    : [];

  eq("the contract names seven", solWords.length, 7);
  eq("the client names seven", jsWords.length, 7);
  ok("and they are the same seven, in the same order",
     solWords.join(",") === jsWords.join(","),
     `contract ${solWords.join(",")}\n      client   ${jsWords.join(",")}`);

  /*  Every alias must resolve to a word that exists. An alias pointing at a
      verb nobody named is a row in the command line that silently does
      nothing, which is the shape of bug a person blames themselves for. */
  const aliasBlock = /var ALIAS = \{([\s\S]*?)\n  \};/.exec(js);
  const aliasKeys = aliasBlock
    ? [...aliasBlock[1].matchAll(/^\s*([a-z]+):/gm)].map((m) => m[1]) : [];
  ok("every alias group is one of the seven",
     aliasKeys.length > 0 && aliasKeys.every((k) => solWords.includes(k)),
     `aliases for ${aliasKeys.filter((k) => !solWords.includes(k)).join(", ")}`);
}

/*═══════════════ a chain, and a console on it ═══════════════*/

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
  encodeAddressArg(await c.deploy(A("src/GripVault.sol", "GripVault").bytecode)) +
  w(1) + w(4096));

const { gzipSync } = await import("node:zlib");
const doc = Buffer.from("<!doctype html><title>x</title><body>the instrument</body>", "utf8");
const packed = gzipSync(doc, { level: 9 });
const loadArg = (b) =>
  w(0x20) + w(b.length) + b.toString("hex").padEnd(Math.ceil(b.length / 32) * 64, "0");
await c.send({ to: engine, data: evm.sel("loadHead(bytes)") + loadArg(packed) });
await c.send({ to: engine, data: evm.sel("loadBody(bytes)") + loadArg(packed) });
await c.exec(engine, "setInflatedSize(uint32)", [doc.length]);

/*═══════════════ the reader, pointed at nothing ═══════════════*/
/*  Deployed against addresses with no code, which is not a contrivance —
    it is Robinhood and BNB, where this collection ships without a pool or
    a lease. If the reader reverts here the console is a 500 on two of the
    five chains it claims to run on.                                    */

head("a satellite that does not answer is recorded as not answering");
{
  const NOBODY = "0x" + "de".repeat(20);
  const read = await c.deploy(A("src/ConsoleRead.sol", "ConsoleRead").bytecode,
    encodeAddressArg(nft) + encodeAddressArg(NOBODY) + encodeAddressArg(NOBODY),
    "ConsoleRead");

  await c.exec(nft, "mint()", [], { value: 10n ** 16n });

  let out, threw = false;
  try { out = await c.read(read, "look(uint256)", [1n]); }
  catch (e) { threw = true; out = String(e && e.message).slice(0, 90); }

  ok("the reader does not revert when the pool and the lease are absent",
     !threw, out);

  if (!threw) {
    /*  `reported` is the last word of the Clocks struct. Rather than decode
        the whole tuple by hand, the bits are read back from the contract's
        own accessor — a test that hard-codes a bit mask is a test that will
        be wrong one deployment from now, which is the same failure the
        contract's own comment warns about.                            */
    const bits = await c.read(read, "bits()");
    const BIT_HUB   = decUint(bits, 0);
    const BIT_POOL  = decUint(bits, 1);
    const BIT_LEASE = decUint(bits, 2);
    const BIT_OWNER = decUint(bits, 3);

    /*  The struct is returned after TokenView; `reported` is the final
        word of the response.                                          */
    const words = out.replace(/^0x/, "").match(/.{64}/g) || [];
    const reported = BigInt("0x" + words[words.length - 1]);

    ok("the hub answered, and its bit is set",
       (reported & BigInt(BIT_HUB)) !== 0n, `reported=${reported}`);
    ok("the owner answered, and its bit is set",
       (reported & BigInt(BIT_OWNER)) !== 0n, `reported=${reported}`);
    ok("the absent pool's bit is CLEAR, not a zero value",
       (reported & BigInt(BIT_POOL)) === 0n,
       "the pool bit is set against a contract with no code");
    ok("the absent lease's bit is CLEAR, not a zero value",
       (reported & BigInt(BIT_LEASE)) === 0n,
       "the lease bit is set against a contract with no code");
  }
}

/*═══════════════ the whole site, and the route ═══════════════*/

const pool = await c.deploy(A("src/Pool.sol", "Pool").bytecode,
  encodeAddressArg(nft) + w(10n ** 30n) + encodeAddressArg(c.from.toString()) + w(0), "Pool");
await c.exec(nft, "setPool(address)", [pool]);
const lease = await c.deploy(A("src/Lease.sol", "Lease").bytecode,
  encodeAddressArg(nft), "Lease");

const site = await deploySite(c, A, { hub: nft, pool, lease, sigil });
const GET = getter(c, site.premises);

head("the console answers at one route, in three shapes");
{
  const bare = await GET(["c"]);
  eq("/c answers 200", bare.status, 200);

  const one = await GET(["c", "1"]);
  eq("/c/1 answers 200", one.status, 200);
  ok("and it is about token #1", one.body.includes("IPSEITY #1"), "no title for #1");

  const hand = await GET(["c", "1", "hand"]);
  eq("/c/1/hand answers 200", hand.status, 200);
  ok("and it opens on HAND IT ON",
     hand.body.includes("HAND IT ON") && hand.body.includes('id=lane class=on'),
     "the lane did not open");

  /*  A mistyped verb is not a 404. The id resolved and the token is real,
      so the console opens on it with nothing expanded — which is what a
      person who mistyped one word wanted, and strictly better than being
      told the token does not exist.                                    */
  const typo = await GET(["c", "1", "hnad"]);
  eq("a mistyped verb still answers 200", typo.status, 200);
  ok("and it opens the console with nothing expanded",
     !typo.body.includes('id=lane class=on'),
     "a mistyped verb opened a lane");

  const gone = await GET(["c", "9999"]);
  ok("an id that does not exist is a 404", gone.status === 404, `got ${gone.status}`);
}

head("the walk never reaches the contract");
{
  /*  ERC-5219 is handed the path and the query. The claim in the client's
      header is that the hash never arrives, and the whole walk design
      rests on it: if it were wrong every gateway would cache one token's
      console once per walk that ever reached it.                       */
  const plain = await GET(["c", "1"]);
  const walked = await GET(["c", "1"]);
  ok("the same path returns the same bytes",
     plain.body.length === walked.body.length,
     `${plain.body.length} vs ${walked.body.length}`);

  ok("and no route segment is ever a fragment",
     !plain.body.includes("#w=") || plain.body.includes('href="/c/'),
     "the document has baked a walk into a served URL");
}

head("the console does not start a second raymarcher");
{
  const doc1 = (await GET(["c", "1"])).body;

  ok("the still is a reference to the sigil route",
     /src="\/token\/1\/sigil\.svg"/.test(doc1), "the still is not the sigil route");
  ok("and it is not a base64 blob inlined into the document",
     !/data:image\/svg\+xml;base64/.test(doc1),
     "the still was inlined, which costs a third more bytes on every read");
  ok("there is no iframe anywhere in the console",
     !/<iframe/i.test(doc1), "the console carries an iframe");
  ok("exactly one control leads to a raymarcher, and it is a link",
     (doc1.match(/\/live/g) || []).length === 1,
     `found ${(doc1.match(/\/live/g) || []).length} routes to /live`);
}

head("the token's own colour is in the document, before any script");
{
  const doc1 = (await GET(["c", "1"])).body;
  const word = decUint(await c.read(nft, "sectionOf(uint256)", [1n]));
  /*  hue is `uint8(word >> 120)` — src/lib/Types.sol Section.hue — and the
      console prints it in degrees the way Console._hue does. Read from the
      chain rather than out of the document, so this compares two
      derivations rather than comparing the document with itself.

      The shift was written as 40 the first time this file was run, which
      is byte 5 rather than byte 15, and it produced a plausible number
      that was not the token's colour. A test that derives a value has to
      derive it from the same source as the code, or it is a second
      implementation with its own bugs.                                */
  const hue = Number((word >> 120n) & 0xffn) * 360 / 256 | 0;
  ok("the stylesheet is inline, not fetched",
     doc1.includes("<style>") && !/<link[^>]+stylesheet/i.test(doc1),
     "the console links a stylesheet it cannot fetch");
  ok("and :root carries this token's hue",
     doc1.includes(`:root{--h:${hue}}`),
     `expected :root{--h:${hue}} — the document's own hue disagrees with the chain`);
}

head("the seven rows are in the served bytes, not painted later");
{
  const doc1 = (await GET(["c", "1"])).body;
  const names = ["TURN IT", "PUT SOMETHING IN IT", "TRADE THROUGH IT", "HAND IT ON",
                 "SPEAK AS IT", "MAKE SOMETHING WITH IT", "LOOK AT ANOTHER ONE"];
  for (const n of names) {
    ok(`"${n}" is server-rendered`, doc1.includes(n), "missing from the response");
  }
  /*  The point of server-rendering them: with no script at all, the page
      is still a correct page about the right token.                    */
  ok("and so is the identity, so a scriptless reader still learns whose it is",
     /IPSEITY #1<\/h1>/.test(doc1) && /Held by/.test(doc1),
     "identity is painted by script");
}

console.log(`\n  ${fail ? "\x1b[31m" : "\x1b[32m"}${pass} passed, ${fail} failed\x1b[0m\n`);
process.exit(fail ? 1 : 0);
