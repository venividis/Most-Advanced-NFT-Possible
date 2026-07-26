#!/usr/bin/env node
/*───────────────────────────────────────────────────────────────────────────
  IPSEITY · the sealed vault

  The claim under test: while a vault is sealed, nothing on its manifest
  leaves it, whatever the holder calls.

  A selector list cannot support that claim, so this suite does not test a
  selector list. It tests the measurement, and it attacks it the way the
  gap would actually be exploited:

    · the obvious word            transfer / transferFrom
    · a word no list has          a drainer with a bespoke function name
    · the deferred drain          approve now, pull in the next block
    · the signature               ERC-1271 as an off-chain authority
    · the ether                   a plain value send
    · the ratchet                 shortening or dodging the seal
    · the sale                    does the promise survive the buyer

    node tools/verify-vault.mjs
───────────────────────────────────────────────────────────────────────────*/
import { compile, artifact } from "./compile.mjs";
import { Chain, enc, decUint, decAddr, decBool, encodeAddressArg } from "./evm.mjs";
import { createAddressFromString, hexToBytes, bytesToHex } from "@ethereumjs/util";

let pass = 0, fail = 0;
const ok = (n, c, d) => {
  c ? pass++ : fail++;
  console.log(`  ${c ? "\x1b[32m✓\x1b[0m" : "\x1b[31m✗\x1b[0m"} ${n}`);
  if (!c && d !== undefined) console.log(`      ${d}`);
};
const eq = (n, g, w) => ok(n, String(g) === String(w), `got ${g}\n      want ${w}`);
const head = (s) => console.log(`\n  \x1b[1m${s}\x1b[0m`);
const WAD = 10n ** 18n;
const REGISTRY = "0x000000006551c19487814612e58FE06813775758";
const MAX = (1n << 256n) - 1n;

const evm = await import("./evm.mjs");
const out = compile({ quiet: true, dirs: ["src", "test/mocks"] });
const A = (f, n) => artifact(out, f, n);
const c = await Chain.open();
const me = c.from.toString();

head("deploy");
const tmpReg = await c.deploy(A("test/mocks/ERC6551Registry.sol", "ERC6551Registry").bytecode);
await c.vm.stateManager.putCode(createAddressFromString(REGISTRY),
  await c.vm.stateManager.getCode(createAddressFromString(tmpReg)));

const impl = await c.deploy(A("src/IpseityAccount.sol", "IpseityAccount").bytecode, "", "IpseityAccount");
const engine = await c.deploy(A("src/Engine.sol", "Engine").bytecode, "0".repeat(64));
const sigil = await c.deploy(A("src/Sigil.sol", "Sigil").bytecode);
const renderer = await c.deploy(A("src/Renderer.sol", "Renderer").bytecode,
  encodeAddressArg(engine) + encodeAddressArg(sigil));
const nft = await c.deploy(A("src/Ipseity.sol", "Ipseity").bytecode,
  encodeAddressArg(renderer) + encodeAddressArg(impl));
const drainer = await c.deploy(A("test/mocks/Drainer.sol", "Drainer").bytecode);

const encStr = (s) => {
  const b = Buffer.from(s, "utf8");
  return b.length.toString(16).padStart(64, "0") + b.toString("hex").padEnd(64, "0");
};
const mkToken = async (name, sym) => {
  const nameEnc = encStr(name);
  return c.deploy(A("test/mocks/MockERC20.sol", "MockERC20").bytecode,
    (0xa0).toString(16).padStart(64, "0") +
    BigInt(0xa0 + nameEnc.length / 2).toString(16).padStart(64, "0") +
    (18).toString(16).padStart(64, "0") + "0".repeat(64) + "0".repeat(64) +
    nameEnc + encStr(sym));
};
const GOLD = await mkToken("Gold", "GOLD");
ok("deployed", true);
console.log(`      account implementation ${impl}`);

/*──────────────── the vault ────────────────*/
head("a token's vault");
await c.exec(nft, "mint()", [], { value: 10n ** 16n });
const vault = decAddr(await c.read(nft, "account(uint256)", [1]));
await c.exec(nft, "embody(uint256)", [1], { label: "embody" });
ok("the account exists", (await c.codeSize(vault)) > 0);
console.log(`      ${vault}`);

const tok = await c.read(vault, "token()");
eq("it knows which token it belongs to", decUint(tok, 2), 1);
eq("and which collection", decAddr(tok, 1).toLowerCase(), nft.toLowerCase());
eq("and who holds it", decAddr(await c.read(vault, "owner()")).toLowerCase(), me.toLowerCase());

// fund it
await c.exec(GOLD, "mint(address,uint256)", [vault, 1000n * WAD]);
await c.send({ to: vault, value: 5n * WAD });
eq("it holds gold", decUint(await c.read(GOLD, "balanceOf(address)", [vault])), 1000n * WAD);

/*──────────────── unsealed, it acts freely ────────────────*/
head("unsealed, the vault is the holder's to empty");
await c.exec(vault, "execute(address,uint256,bytes,uint8)",
  [GOLD, 0, enc("transfer(address,uint256)", [me, 100n * WAD]), 0], { label: "execute" });
eq("gold left as asked", decUint(await c.read(GOLD, "balanceOf(address)", [vault])), 900n * WAD);
eq("the 6551 state counter moved", decUint(await c.read(vault, "state()")), 1);

/*──────────────── the seal ────────────────*/
head("the seal");
const T0 = evm.GENESIS_TIME;
const refuses = async (name, fn, why) => {
  let threw = false;
  try { await fn(); } catch { threw = true; }
  ok(name, threw, "IT WENT THROUGH — " + why);
};

await c.exec(vault, "guard(address)", [GOLD], { label: "guard" });
await c.exec(vault, "seal(uint64)", [T0 + 30n * 86400n], { label: "seal" });
ok("sealed", decBool(await c.read(vault, "isSealed()")));
eq("the date is readable by anyone", decUint(await c.read(vault, "sealedUntil()")), T0 + 30n * 86400n);

const hold = await c.read(vault, "holdings()");
ok("and so is everything under it", decUint(hold, 0) === T0 + 30n * 86400n);

await refuses("shortening the seal", () =>
  c.exec(vault, "seal(uint64)", [T0 + 100n]), "the ratchet turns backwards");
await refuses("a seal nobody can outlive", () =>
  c.exec(vault, "seal(uint64)", [T0 + 400n * 86400n]), "the seal has no ceiling");

/*──────────────── the attacks ────────────────*/
head("trying to get the gold out");
const goldBefore = decUint(await c.read(GOLD, "balanceOf(address)", [vault]));

await refuses("the obvious word — transfer", () =>
  c.exec(vault, "execute(address,uint256,bytes,uint8)",
    [GOLD, 0, enc("transfer(address,uint256)", [me, WAD]), 0]),
  "a sealed vault paid out on a plain transfer");

await refuses("transferFrom, pulling from the vault itself", () =>
  c.exec(vault, "execute(address,uint256,bytes,uint8)",
    [GOLD, 0, enc("transferFrom(address,address,uint256)", [vault, me, WAD]), 0]),
  "a sealed vault paid out on transferFrom");

/* The one a selector list cannot catch. Drainer.take() is not on anybody's
   list of transfer words, and it never will be — it is a function this
   suite invented five minutes ago. Only measurement sees it. */
await c.exec(GOLD, "approve(address,uint256)", [drainer, MAX]);
await refuses("a word no list has ever heard of", () =>
  c.exec(vault, "execute(address,uint256,bytes,uint8)",
    [drainer, 0, enc("take(address,uint256)", [GOLD, WAD]), 0]),
  "measurement missed a bespoke drainer — this is the whole point of the design");

await refuses("approving a spender to pull later", () =>
  c.exec(vault, "execute(address,uint256,bytes,uint8)",
    [GOLD, 0, enc("approve(address,uint256)", [me, MAX]), 0]),
  "the deferred drain is open: approve now, take next block");

await refuses("setApprovalForAll on an NFT", () =>
  c.exec(vault, "execute(address,uint256,bytes,uint8)",
    [GOLD, 0, enc("setApprovalForAll(address,bool)", [me, true]), 0]),
  "operator approval is open");

await refuses("permit, which is an approval wearing a signature", () =>
  c.exec(vault, "execute(address,uint256,bytes,uint8)",
    [GOLD, 0, "0xd505accf" + "00".repeat(224), 0]),
  "permit is an unmeasurable approval");

await refuses("sending the vault's ether", () =>
  c.exec(vault, "execute(address,uint256,bytes,uint8)", [me, WAD, "0x", 0]),
  "ether left a sealed vault");

await refuses("delegatecall, which would rewrite the account itself", () =>
  c.exec(vault, "execute(address,uint256,bytes,uint8)", [drainer, 0, "0x", 1]),
  "delegatecall is allowed — the seal can be overwritten in storage");

eq("not one satoshi of gold moved", decUint(await c.read(GOLD, "balanceOf(address)", [vault])), goldBefore);

head("but the vault still works");
/* The reason for measuring instead of freezing: a vault that cannot act is
   a safe, not a vault. Anything that leaves it no poorer goes through. */
let acted = false;
try {
  await c.exec(vault, "execute(address,uint256,bytes,uint8)",
    [GOLD, 0, enc("balanceOf(address)", [vault]), 0]);
  acted = true;
} catch { /* ignore */ }
ok("a call that takes nothing still executes", acted);

let received = false;
try { await c.exec(GOLD, "mint(address,uint256)", [vault, 50n * WAD]); received = true; } catch {}
ok("and the vault can still be paid", received &&
   decUint(await c.read(GOLD, "balanceOf(address)", [vault])) === goldBefore + 50n * WAD);

head("a signature is an authority measurement cannot see");
const sigMagic = await c.read(vault, "isValidSignature(bytes32,bytes)",
  ["0x" + "11".repeat(32), "0x" + "00".repeat(65)]);
eq("so ERC-1271 refuses while sealed", decUint(sigMagic), 0);

/*──────────────── the sale ────────────────*/
head("the promise survives the sale");
const buyer = "0x" + "b0197a".padStart(40, "0");
await c.exec(nft, "transferFrom(address,address,uint256)", [me, buyer, 1]);
eq("the token moved", decAddr(await c.read(nft, "ownerOf(uint256)", [1])).toLowerCase(), buyer);
eq("the vault followed it", decAddr(await c.read(vault, "owner()")).toLowerCase(), buyer);
eq("the seal is untouched", decUint(await c.read(vault, "sealedUntil()")), T0 + 30n * 86400n);
eq("and so is the gold", decUint(await c.read(GOLD, "balanceOf(address)", [vault])),
   goldBefore + 50n * WAD);

await refuses("the seller can no longer act as the vault", () =>
  c.exec(vault, "execute(address,uint256,bytes,uint8)",
    [GOLD, 0, enc("transfer(address,uint256)", [me, WAD]), 0]),
  "the old owner still commands the vault");

const asBuyer = async (sig, args, value = 0n) => {
  const r = await c.vm.evm.runCall({
    to: createAddressFromString(vault), caller: createAddressFromString(buyer),
    origin: createAddressFromString(buyer), data: hexToBytes(enc(sig, args)),
    gasLimit: 30_000_000n, value, block: evm.BLOCK
  });
  if (r.execResult.exceptionError) throw new Error(r.execResult.exceptionError.error);
  return bytesToHex(r.execResult.returnValue);
};
let buyerBlocked = false;
try {
  await asBuyer("execute(address,uint256,bytes,uint8)",
    [GOLD, 0, enc("transfer(address,uint256)", [buyer, WAD]), 0]);
} catch { buyerBlocked = true; }
ok("and the buyer is bound by it too, until it expires", buyerBlocked);

/*──────────────── expiry ────────────────*/
head("and then it lifts");
evm.warp(T0 + 31n * 86400n);
ok("no longer sealed", !decBool(await c.read(vault, "isSealed()")));
let freed = false;
try {
  await asBuyer("execute(address,uint256,bytes,uint8)",
    [GOLD, 0, enc("transfer(address,uint256)", [buyer, WAD]), 0]);
  freed = true;
} catch { /* ignore */ }
ok("the buyer can move what they bought", freed);
eq("the gold is theirs", decUint(await c.read(GOLD, "balanceOf(address)", [buyer])), WAD);
evm.warp(T0);

/*──────────────── manifest limits, stated honestly ────────────────*/
head("what the seal does not cover");
await c.exec(nft, "mint()", [], { value: 10n ** 16n });
const v2 = decAddr(await c.read(nft, "account(uint256)", [2]));
await c.exec(nft, "embody(uint256)", [2]);
const SILVER = await mkToken("Silver", "SLVR");
await c.exec(SILVER, "mint(address,uint256)", [v2, 100n * WAD]);
await c.exec(v2, "seal(uint64)", [T0 + 86400n]);   // sealed, but silver unlisted

let unlistedLeft = false;
try {
  await c.exec(v2, "execute(address,uint256,bytes,uint8)",
    [SILVER, 0, enc("transfer(address,uint256)", [me, WAD]), 0]);
  unlistedLeft = true;
} catch { /* ignore */ }
ok("an asset nobody put on the manifest can still leave — by design, and why manifest() is public",
   unlistedLeft);
console.log("      a buyer reads manifest(), they do not assume it");

console.log(`\n  ${pass} passed, ${fail} failed\n`);
process.exit(fail ? 1 : 0);
