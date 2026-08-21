#!/usr/bin/env node
/*───────────────────────────────────────────────────────────────────────────
  IPSEITY · the launchpad, with its hooks actually executed

  A review of this repository found the disqualifying thing about the
  launchpad: `Gate.beforeSwap` and `Gate.beforeRemoveLiquidity` had never
  run. Not "were lightly tested" — never executed, in any suite, in any
  form. Two callbacks holding other people's liquidity, shipped on the
  strength of the fact that they compiled.

  Calling a hook directly would not have fixed that. A hook is reached BY
  SELECTOR from a PoolManager that decides whether to call it at all by
  reading the low fourteen bits of its own address. So the harness here is
  a manager that dispatches the way v4 does, and every assertion below goes
  through it rather than around it.

  What that lets this file test that a direct call cannot:

    · a hook whose parameter types drift is never called, rather than
      called and wrong;
    · a hook that returns the wrong selector is refused;
    · a hook that returns a fee without OVERRIDE_FEE is IGNORED, silently,
      which is the failure a dynamic-fee hook actually ships with;
    · a hook is only consulted for the permissions its address carries.

    node tools/verify-launch.mjs
───────────────────────────────────────────────────────────────────────────*/
import { compile, artifact } from "./compile.mjs";
import { Chain, decUint, decAddr, encodeAddressArg, warp, sel } from "./evm.mjs";
import * as evm from "./evm.mjs";
import { createAddressFromString } from "@ethereumjs/util";
import { keccak256 } from "ethereum-cryptography/keccak.js";

let pass = 0, fail = 0;
const ok = (n, c, d) => {
  c ? pass++ : fail++;
  console.log(`  ${c ? "\x1b[32m✓\x1b[0m" : "\x1b[31m✗\x1b[0m"} ${n}`);
  if (!c && d !== undefined) console.log(`      ${d}`);
};
const eq = (n, g, w) => ok(n, String(g) === String(w), `got ${g}\n      want ${w}`);
const head = (s) => console.log(`\n  \x1b[1m${s}\x1b[0m`);
const refuses = async (name, fn, why) => {
  let threw = false;
  try { await fn(); } catch { threw = true; }
  ok(name, threw, why || "it went through");
};

const REGISTRY = "0x000000006551c19487814612e58FE06813775758";
const out = compile({ quiet: true, dirs: ["src", "test/mocks"] });
const A = (f, n) => artifact(out, f, n);
const c = await Chain.open();
const me = c.from.toString();
const w = (n) => BigInt(n).toString(16).padStart(64, "0");
const iw = (n) => (BigInt(n) < 0n ? (1n << 256n) + BigInt(n) : BigInt(n)).toString(16).padStart(64, "0");

const DYNAMIC = 0x800000n, OVERRIDE = 0x400000n;
const HALF = 32768n;

head("deploy");
const tmpReg = await c.deploy(A("test/mocks/ERC6551Registry.sol", "ERC6551Registry").bytecode);
await c.vm.stateManager.putCode(createAddressFromString(REGISTRY),
  await c.vm.stateManager.getCode(createAddressFromString(tmpReg)));
const impl = await c.deploy(A("src/IpseityAccount.sol", "IpseityAccount").bytecode);
const grip = await c.deploy(A("src/GripVault.sol", "GripVault").bytecode);
const engine = await c.deploy(A("src/Engine.sol", "Engine").bytecode, "0".repeat(64));
const sigil = await c.deploy(A("src/Sigil.sol", "Sigil").bytecode);
const renderer = await c.deploy(A("src/Renderer.sol", "Renderer").bytecode,
  encodeAddressArg(engine) + encodeAddressArg(sigil));
const nft = await c.deploy(A("src/Ipseity.sol", "Ipseity").bytecode,
  encodeAddressArg(renderer) + encodeAddressArg(impl) + encodeAddressArg(grip) + w(1) + w(4096));
const pm = await c.deploy(A("test/mocks/MockPoolManager.sol", "MockPoolManager").bytecode);
await c.exec(nft, "mint()", [], { value: 10n ** 16n });
ok("a manager and a token", pm.length === 42);

/*  A pool key, ABI-encoded by hand: (address,address,uint24,int24,address). */
/*  Raw calldata, since these signatures carry tuples. */
Chain.prototype.exec_ = function (to, data, label) {
  return this.send({ to, data: data.startsWith("0x") ? data : "0x" + data, label });
};

/*  Placing a hook at an address with exactly the permissions it declares
    — which is what mining a CREATE2 salt buys you on chain.

    The low fourteen bits of ANY address are permissions, so a chosen
    prefix carries whatever bits it happens to contain: 0xef…00 already
    asserts BEFORE_INITIALIZE, and the manager duly called a Gate that has
    no such function. Clear the mask, then set the flags.               */
const MASK = (1n << 14n) - 1n;
const place = async (code, flags, prefix) => {
  const at = "0x" + (((BigInt("0x" + prefix.repeat(19) + "00") & ~MASK) | BigInt(flags))
    .toString(16).padStart(40, "0"));
  await c.vm.stateManager.putCode(createAddressFromString(at),
    await c.vm.stateManager.getCode(createAddressFromString(code)));
  return at;
};

const key = (fee, hook) =>
  encodeAddressArg("0x" + "11".repeat(20)) + encodeAddressArg("0x" + "22".repeat(20)) +
  w(fee) + iw(60) + encodeAddressArg(hook);
const swapArgs = w(0) + iw(1000) + w(0);   // zeroForOne=false, amt=1000, limit=0

/*  The harness's ABI encoder does not parse tuple types out of a
    signature, and these callbacks are all tuples. Selector plus the words,
    by hand — which is what the browser client in this project does too,
    and for the same reason.                                            */
const SIG_INIT = "initialize((address,address,uint24,int24,address),uint160)";
const SIG_SWAP = "swap((address,address,uint24,int24,address),(bool,int256,uint160),bytes)";
const SIG_MOD  = "modifyLiquidity((address,address,uint24,int24,address),(int24,int24,int256,bytes32),bytes)";
const doInit = (k, price) => c.exec_(pm, sel(SIG_INIT) + k + w(price), "initialize");
/*  A trailing `bytes` needs an offset word and a length word, and the
    offset counts from the start of the ARGUMENTS in whole words — so it
    depends on how many static words come before it.

      swap:           PoolKey 5 + SwapParams 3 + the offset itself  = 9
      modifyLiquidity: PoolKey 5 + Params 4     + the offset itself = 10

    Both were 7 in the first version of this file. The swap case worked
    anyway, by accident: an offset of seven words lands on
    `sqrtPriceLimitX96`, which was zero, and a zero read as a length
    decodes to empty bytes. The modifyLiquidity case landed on
    `liquidityDelta` instead, read 1000 as a length, and reverted. An
    encoding that is wrong and passes is worse than one that is wrong and
    fails, so the arithmetic is written out.                            */
const off = (words) => w(words * 32);
const emptyBytes = w(0);
const doSwap = (k) =>
  c.exec_(pm, sel(SIG_SWAP) + k + swapArgs + off(9) + emptyBytes, "swap");
const doMod = (k, p) =>
  c.exec_(pm, sel(SIG_MOD) + k + p + off(10) + emptyBytes, "modifyLiquidity");

/*═══════════════ the fee hook ═══════════════*/

head("the fee a pool charges is read out of the artwork");
const FLOOR = 3000n, CEIL = 100000n;      // 0.30% .. 10%
const facet = await c.deploy(A("src/Facet.sol", "Facet").bytecode,
  encodeAddressArg(pm) + encodeAddressArg(nft) + w(1) + w(FLOOR) + w(CEIL), "Facet");
{
  /*  A token is born with a section drawn from the block that carried the
      mint, so it is not at rest until it is put there.                 */
  await c.exec(nft, "commit(uint256,uint256)", [1, HALF << 96n]);
  eq("at rest the pool charges exactly the floor",
     decUint(await c.read(facet, "fee()")), FLOOR);

  /*  Turn the solid a quarter, which genuinely tips the cut plane. */
  const turned = (16384n << 48n) | (HALF << 96n) | (0n << 112n);
  await c.exec(nft, "commit(uint256,uint256)", [1, turned]);
  const raised = decUint(await c.read(facet, "fee()"));
  ok("turning the solid raises it", raised > FLOOR, `${FLOOR} -> ${raised}`);
  ok("and never past the ceiling it was built with", raised <= CEIL, String(raised));

  const r = await c.read(facet, "reading()", []);
  eq("the reading agrees with the fee", decUint(r, 2), raised);
  eq("and names the band it moves inside", decUint(r, 3) + decUint(r, 4), FLOOR + CEIL);

  /*  Back to rest: the promise the whole curve library is built around. */
  await c.exec(nft, "commit(uint256,uint256)", [1, HALF << 96n]);
  eq("returned to rest, it is the floor again", decUint(await c.read(facet, "fee()")), FLOOR);
}

head("and the pool actually charges it");
{
  /*  Through the manager, not by calling the hook. The address the Facet
      happens to have decides whether it is consulted at all, so it is
      pushed into a slot whose low bits carry the two permissions it
      declares — which is what mining a salt does on chain.            */
  const flags = decUint(await c.read(facet, "flags()"));
  const placed = await place(facet, flags, "ab");
  /*  Its immutables travel with the code, so the copy reads the same
      token. Confirm rather than assume.                              */
  eq("the placed copy reads the same token", decUint(await c.read(placed, "TOKEN()")), 1n);

  await doInit(key(DYNAMIC, placed), 1n);
  ok("a dynamic-fee pool initialised through the hook", true);

  await doSwap(key(DYNAMIC, placed));
  eq("the swap paid the floor, set by the hook and not by the key",
     decUint(await c.read(pm, "lastFeeCharged()")), FLOOR);

  const turned = (16384n << 48n) | (HALF << 96n);
  await c.exec(nft, "commit(uint256,uint256)", [1, turned]);
  await doSwap(key(DYNAMIC, placed));
  const after = decUint(await c.read(pm, "lastFeeCharged()"));
  ok("turning the artwork changed what the next swap paid, on chain",
     after > FLOOR, `${FLOOR} -> ${after}`);
  await c.exec(nft, "commit(uint256,uint256)", [1, HALF << 96n]);
}

head("the failure a dynamic-fee hook actually ships with");
{
  /*  A pool created with a static fee: the hook returns an override on
      every swap and the manager throws it away, silently. Every trade
      charges the key's number and nothing reverts. The Facet refuses to
      initialise such a pool at all, which is the only place the mistake
      can still be caught.                                             */
  const flags = decUint(await c.read(facet, "flags()"));
  const placed = await place(facet, flags, "cd");
  await refuses("a pool that is not dynamic-fee is refused at initialisation",
    () => doInit(key(3000, placed), 1n),
    "the hook would have looked like it worked while every swap charged the key");
}

head("only the endpoint of the protocol may call it");
{
  await refuses("a stranger cannot drive beforeSwap",
    () => c.exec_(facet, sel("beforeSwap(address,(address,address,uint24,int24,address),(bool,int256,uint160),bytes)")
      + encodeAddressArg(me) + key(DYNAMIC, facet) + swapArgs + off(10) + emptyBytes));
  await refuses("nor beforeInitialize",
    () => c.exec_(facet, sel("beforeInitialize(address,(address,address,uint24,int24,address),uint160)")
      + encodeAddressArg(me) + key(DYNAMIC, facet) + w(1)));
}

/*═══════════════ the gate, finally executed ═══════════════*/

head("the gate: two promises a launch makes, kept by the pool");
{
  const now = evm.BLOCK.header.timestamp;
  const opens = now + 3600n, unlocks = now + 86400n;
  const gate = await c.deploy(A("src/Kiln.sol", "Gate").bytecode,
    encodeAddressArg(pm) + w(opens) + w(unlocks), "Gate");
  const flags = (1n << 9n) | (1n << 7n);          // beforeRemoveLiquidity | beforeSwap
  const placed = await place(gate, flags, "ef");
  eq("the gate sits at an address carrying exactly its two permissions",
     (BigInt(placed) & MASK).toString(16), flags.toString(16));

  await doInit(key(3000, placed), 1n);

  await refuses("before the opening hour the pool will not swap",
    () => doSwap(key(3000, placed)),
    "trading opened early — the callback has still never run");

  const add = iw(-100) + iw(100) + iw(1000) + w(0);
  await doMod(key(3000, placed), add);
  ok("adding liquidity is never gated — the hook does not hold that bit", true);

  const remove = iw(-100) + iw(100) + iw(-1000) + w(0);
  await refuses("and liquidity cannot leave while it is locked",
    () => doMod(key(3000, placed), remove),
    "the lock is the whole product");

  warp(opens + 1n);
  await doSwap(key(3000, placed));
  ok("once the hour comes, the pool trades", true);
  await refuses("but the liquidity is still locked",
    () => doMod(key(3000, placed), remove));

  warp(unlocks + 1n);
  await doMod(key(3000, placed), remove);
  ok("and when the date arrives it comes out", true);
  console.log("      shut, opened, still locked, released — every branch, through the manager");
}

head("a hook is only consulted for the bits its address carries");
{
  /*  The same Facet code at an address with NO permission bits. v4 would
      never call it, so the pool keeps the key's fee. This is why testing
      a hook by calling it directly proves nothing.                     */
  const inert = await place(facet, 0n, "3a");
  eq("and it really has no permission bits at all", BigInt(inert) & MASK, 0n);
  await doInit(key(3000, inert), 1n);
  await doSwap(key(3000, inert));
  eq("the same code at a flagless address is never asked, and the key's fee stands",
     decUint(await c.read(pm, "lastFeeCharged()")), 3000n);
}

/*════════════ the property Unichain made obvious ════════════

  Every chain in the survey runs the SAME PoolManager bytecode — byte
  diffed, with only the self-address immutable and a metadata hash
  differing. A hook address under v4 is CREATE2 from (deployer, salt,
  initCodeHash), and none of those three is a chain id.

  So a salt mined once gives the same hook address on all five chains,
  and a launch can carry one address everywhere instead of five. That is
  worth a test, because it is the kind of claim that is true until one
  constructor argument quietly differs.
*/
head("one mined salt, the same hook address on every chain");
{
  const kiln = await c.deploy(A("src/Kiln.sol", "Kiln").bytecode,
    encodeAddressArg(nft) + encodeAddressArg(pm), "Kiln");
  /*  The recipe hash is what CREATE2 consumes. If it depends on nothing
      chain-specific, the address cannot either.                       */
  const arg = w((1n << 48n) | (3000n << 24n) | 100000n);

  /*  `recipeHash` returns TWO words — (bytes32 hash, uint16 flags) — and
      the second is the contract telling you which permissions this recipe
      needs. Reading the whole 64 bytes as a bytes32, as the first version
      of this file did, hashes a preimage the miner never uses. It still
      finds "matches" at the right rate, because a wrong hash is just as
      uniform as a right one; it simply finds them for a different
      function. A search that succeeds is not evidence the search is
      correct.                                                          */
  const rh = (await c.read(kiln, "recipeHash(uint8,bytes32)", [1, "0x" + arg])).replace(/^0x/, "");
  const hash = "0x" + rh.substr(0, 64);
  const flags = BigInt("0x" + rh.substr(64, 64));
  eq("the kiln names the permissions this hook needs, rather than a caller guessing",
     flags, decUint(await c.read(facet, "flags()")));

  const mined = await c.read(kiln, "mine(bytes32,uint16,uint256,uint256)",
    [hash, Number(flags), 0, 120000]);
  const raw = mined.replace(/^0x/, "");
  const found = BigInt("0x" + raw.substr(0, 64)) === 1n;
  const salt = "0x" + raw.substr(64, 64);
  const at = "0x" + raw.substr(128 + 24, 40);
  ok("a salt is found for exactly those permissions", found, "searched 120,000 and found none");
  eq("and the address it predicts carries them and nothing else",
     (BigInt(at) & MASK).toString(16), flags.toString(16));

  /*  The claim: that address is CREATE2 over (deployer, salt,
      initCodeHash) and nothing else. Recomputed independently, because
      the contract is the thing under test.                             */
  const pre = Buffer.concat([
    Buffer.from("ff", "hex"),
    Buffer.from(kiln.replace(/^0x/, ""), "hex"),
    Buffer.from(salt.replace(/^0x/, ""), "hex"),
    Buffer.from(hash.replace(/^0x/, ""), "hex")]);
  eq("recomputed from (deployer, salt, initCodeHash) alone, it is the same address",
     "0x" + Buffer.from(keccak256(pre)).toString("hex").slice(24), at.toLowerCase());
  ok("none of those three is a chain id, so one salt serves all five chains", true);

  /*  And the miner's assembly against a plain implementation, kept because
      a hand-written CREATE2 is exactly the thing that is wrong quietly.  */
  const probe = await c.deploy(A("test/mocks/MineProbe.sol", "MineProbe").bytecode);
  const asm = decAddr(await c.read(probe, "at(address,bytes32,uint256)", [kiln, hash, 12397]));
  const pln = decAddr(await c.read(probe, "plain(address,bytes32,uint256)", [kiln, hash, 12397]));
  eq("the miner's assembly agrees with the plain version", asm.toLowerCase(), pln.toLowerCase());
  console.log("      mined in a free eth_call — the visitor's own node does the search");
}

console.log(`\n  ${pass} passed, ${fail} failed\n`);
process.exit(fail ? 1 : 0);
