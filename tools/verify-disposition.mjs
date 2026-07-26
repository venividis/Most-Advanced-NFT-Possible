#!/usr/bin/env node
/*───────────────────────────────────────────────────────────────────────────
  IPSEITY · the disposition

  The claim under test: a token can carry a private kernel — the strategy
  an agent runs under — without anyone being able to lie to a buyer about
  it.

  Three separate things are checked, because conflating them is exactly the
  failure mode:

    · the binding      the ciphertext is committed to by hash and bound to
                       an owner read from the chain, not from the caller
    · the staleness    a sale invalidates the kernel with no gas, no hook
                       and no cooperation from the seller
    · the attestation  "somebody with a proof system checked this" is a
                       different question from "this is addressed to you",
                       and this deployment answers the first one NO

    node tools/verify-disposition.mjs
───────────────────────────────────────────────────────────────────────────*/
import { compile, artifact } from "./compile.mjs";
import { Chain, enc, decUint, decAddr, decBool, encodeAddressArg } from "./evm.mjs";
import { createAddressFromString, hexToBytes, bytesToHex } from "@ethereumjs/util";
import { keccak256 } from "ethereum-cryptography/keccak.js";

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
const me = c.from.toString();

const refuses = async (name, fn, why) => {
  let threw = false;
  try { await fn(); } catch { threw = true; }
  ok(name, threw, "IT WENT THROUGH — " + why);
};

/* the tuple kernel() returns: five statics and a string, so the string's
   offset lives in head word 4 and is measured from the start of the tuple */
const decTupleString = (hex, at) => {
  const h = hex.replace(/^0x/, "");
  const off = Number(BigInt("0x" + h.substr(at * 64, 64))) * 2;
  const len = Number(BigInt("0x" + h.substr(off, 64)));
  return Buffer.from(h.substr(off + 64, len * 2), "hex").toString("utf8");
};

/*──────────────── deploy ────────────────*/
head("deploy");
const tmpReg = await c.deploy(A("test/mocks/ERC6551Registry.sol", "ERC6551Registry").bytecode);
await c.vm.stateManager.putCode(createAddressFromString(REGISTRY),
  await c.vm.stateManager.getCode(createAddressFromString(tmpReg)));

const impl = await c.deploy(A("src/IpseityAccount.sol", "IpseityAccount").bytecode);
const gripImpl = await c.deploy(A("src/GripVault.sol", "GripVault").bytecode);
const engine = await c.deploy(A("src/Engine.sol", "Engine").bytecode, "0".repeat(64));
const sigil = await c.deploy(A("src/Sigil.sol", "Sigil").bytecode);
const renderer = await c.deploy(A("src/Renderer.sol", "Renderer").bytecode,
  encodeAddressArg(engine) + encodeAddressArg(sigil));
const nft = await c.deploy(A("src/Ipseity.sol", "Ipseity").bytecode,
  encodeAddressArg(renderer) + encodeAddressArg(impl) + encodeAddressArg(gripImpl));

/* the shipping deployment: no oracle, and it says so */
const disp = await c.deploy(A("src/Disposition.sol", "Disposition").bytecode,
  encodeAddressArg(nft) + encodeAddressArg("0x" + "0".repeat(40)), "Disposition");
/* a second one, wired to an oracle, so the attestation path is exercised
   rather than merely described */
const oracled = await c.deploy(A("src/Disposition.sol", "Disposition").bytecode,
  encodeAddressArg(nft) + encodeAddressArg(me));

ok("deployed", (await c.codeSize(disp)) > 0);
console.log(`      disposition ${disp}`);

await c.exec(nft, "mint()", [], { value: 10n ** 16n });
eq("a token exists", decAddr(await c.read(nft, "ownerOf(uint256)", [1])).toLowerCase(), me.toLowerCase());

/*──────────────── the honest null ────────────────*/
head("this deployment has no oracle, and does not imply one");
ok("hasVerifier() is false", !decBool(await c.read(disp, "hasVerifier()")));
eq("VERIFIER reads back as zero", decAddr(await c.read(disp, "VERIFIER()")),
   "0x" + "0".repeat(40));
eq("a token with no kernel is ABSENT, not CURRENT", decUint(await c.read(disp, "status(uint256)", [1])), 0);

/*──────────────── publishing ────────────────*/
head("publishing a kernel");
const CIPHER = Buffer.from("the strategy nobody else gets to read", "utf8");
const COMMIT = "0x" + Buffer.from(keccak256(CIPHER)).toString("hex");
const URI = "ipfs://bafkreikernelv1";

await refuses("a stranger cannot publish onto someone else's token", async () => {
  const stranger = "0x" + "5747".padStart(40, "0");
  const r = await c.vm.evm.runCall({
    to: createAddressFromString(disp), caller: createAddressFromString(stranger),
    origin: createAddressFromString(stranger),
    data: hexToBytes(enc("publish(uint256,bytes32,string)", [1, COMMIT, URI])),
    gasLimit: 20_000_000n, value: 0n, block: evm.BLOCK
  });
  if (r.execResult.exceptionError) throw new Error(r.execResult.exceptionError.error);
}, "anyone could overwrite the disposition of any token");

await refuses("an empty commitment is refused",
  () => c.exec(disp, "publish(uint256,bytes32,string)", [1, 0, URI]),
  "a kernel that commits to nothing reads as ABSENT and is a footgun");

await c.exec(disp, "publish(uint256,bytes32,string)", [1, COMMIT, URI], { label: "publish" });

let k = await c.read(disp, "kernel(uint256)", [1]);
eq("the commitment is the hash of the ciphertext",
   "0x" + k.replace(/^0x/, "").substr(0, 64), COMMIT);
eq("it is sealed to the holder", decAddr(k, 1).toLowerCase(), me.toLowerCase());
eq("the uri round-trips", decTupleString(k, 4), URI);
eq("status is CURRENT", decUint(k, 5), 1);
ok("isCurrent agrees", decBool(await c.read(disp, "isCurrent(uint256)", [1])));

head("but current is not attested, and they are asked separately");
eq("attestedBy is zero", decAddr(k, 3), "0x" + "0".repeat(40));
ok("isAttested is false", !decBool(await c.read(disp, "isAttested(uint256)", [1])),
   "an unverified kernel is being presented as verified");
await refuses("and there is nobody who can attest it here",
  () => c.exec(disp, "attest(uint256,bytes32)", [1, COMMIT]),
  "a contract with no verifier accepted an attestation");

/*──────────────── the sale ────────────────*/
head("the sale, which nobody has to cooperate with");
const buyer = "0x" + "b0197a".padStart(40, "0");
await c.exec(nft, "transferFrom(address,address,uint256)", [me, buyer, 1]);

eq("the token moved", decAddr(await c.read(nft, "ownerOf(uint256)", [1])).toLowerCase(), buyer);
eq("the kernel went STALE by itself", decUint(await c.read(disp, "status(uint256)", [1])), 2);
ok("isCurrent now says no", !decBool(await c.read(disp, "isCurrent(uint256)", [1])),
   "a buyer would be told a ciphertext addressed to the seller is theirs");

k = await c.read(disp, "kernel(uint256)", [1]);
eq("nothing was rewritten — sealedTo still names the seller",
   decAddr(k, 1).toLowerCase(), me.toLowerCase());
console.log("      no hook fired, no gas was spent, no transaction was needed");

await refuses("the seller can no longer publish",
  () => c.exec(disp, "publish(uint256,bytes32,string)", [1, COMMIT, URI]),
  "the old owner still controls the disposition");

head("and the buyer re-seals it to themselves");
const CIPHER2 = Buffer.from("re-encrypted to the new holder's key", "utf8");
const COMMIT2 = "0x" + Buffer.from(keccak256(CIPHER2)).toString("hex");
const asBuyer = async (to, sig, args) => {
  const r = await c.vm.evm.runCall({
    to: createAddressFromString(to), caller: createAddressFromString(buyer),
    origin: createAddressFromString(buyer), data: hexToBytes(enc(sig, args)),
    gasLimit: 20_000_000n, value: 0n, block: evm.BLOCK
  });
  if (r.execResult.exceptionError) throw new Error(r.execResult.exceptionError.error);
  return bytesToHex(r.execResult.returnValue);
};
await asBuyer(disp, "publish(uint256,bytes32,string)", [1, COMMIT2, "ipfs://bafkreikernelv2"]);
eq("CURRENT again", decUint(await c.read(disp, "status(uint256)", [1])), 1);
eq("and sealed to the buyer", decAddr(await c.read(disp, "kernel(uint256)", [1]), 1).toLowerCase(), buyer);

/*──────────────── the attestation path ────────────────*/
head("with an oracle wired in");
await c.exec(nft, "mint()", [], { value: 10n ** 16n });
await c.exec(oracled, "publish(uint256,bytes32,string)", [2, COMMIT, URI]);
ok("hasVerifier() is true there", decBool(await c.read(oracled, "hasVerifier()")));

await refuses("a stranger cannot attest", async () => {
  const stranger = "0x" + "5747".padStart(40, "0");
  const r = await c.vm.evm.runCall({
    to: createAddressFromString(oracled), caller: createAddressFromString(stranger),
    origin: createAddressFromString(stranger),
    data: hexToBytes(enc("attest(uint256,bytes32)", [2, COMMIT])),
    gasLimit: 20_000_000n, value: 0n, block: evm.BLOCK
  });
  if (r.execResult.exceptionError) throw new Error(r.execResult.exceptionError.error);
}, "anybody could vouch for anything");

await refuses("and the oracle cannot attest a commitment that is not there",
  () => c.exec(oracled, "attest(uint256,bytes32)", [2, COMMIT2]),
  "an attestation could be aimed at a blob the token does not carry");

await c.exec(oracled, "attest(uint256,bytes32)", [2, COMMIT], { label: "attest" });
ok("the oracle's attestation lands", decBool(await c.read(oracled, "isAttested(uint256)", [2])));

await c.exec(oracled, "publish(uint256,bytes32,string)", [2, COMMIT2, "ipfs://swapped"]);
ok("swapping the ciphertext clears the attestation",
   !decBool(await c.read(oracled, "isAttested(uint256)", [2])),
   "a stale attestation now vouches for a document nobody checked");
eq("though the kernel is still CURRENT", decUint(await c.read(oracled, "status(uint256)", [2])), 1);

head("the oracle attests, and that is all it can do");
await refuses("it cannot publish onto a token it does not hold", async () => {
  /* `me` is the VERIFIER of `oracled` and does not hold token 1 */
  await c.exec(oracled, "publish(uint256,bytes32,string)", [1, COMMIT, URI]);
}, "the verifier can write the very kernel it is supposed to be checking");

/*──────────────── clearing ────────────────*/
head("withdrawing the claim");
await refuses("a stranger cannot clear", async () => {
  await c.exec(disp, "clear(uint256)", [1]);   // `me` no longer holds token 1
}, "anyone could erase a token's disposition");
await asBuyer(disp, "clear(uint256)", [1]);
eq("the holder can, and it goes back to ABSENT",
   decUint(await c.read(disp, "status(uint256)", [1])), 0);

/*──────────────── the shape ────────────────*/
head("what it cannot do, read off the compiled ABI");
const abi = A("src/Disposition.sol", "Disposition").abi;
const writes = abi.filter(f => f.type === "function" &&
  f.stateMutability !== "view" && f.stateMutability !== "pure");
eq("there are exactly three state-changing functions", writes.length, 3);
console.log("      " + writes.map(f => f.name).join(", "));
ok("none of them is payable", !writes.some(f => f.stateMutability === "payable"));
ok("not one moves an asset",
   !abi.some(f => /transfer|withdraw|sweep|rescue|approve|execute|call|drain/i.test(f.name || "")),
   "the disposition is supposed to be a pointer, not a purse");
ok("there is no admin, owner or upgrade path",
   !abi.some(f => /admin|owner\b|upgrade|initialize|setVerifier/i.test(f.name || "")),
   "the verifier is immutable on purpose");

/*──────────────── gas ────────────────*/
head("gas");
for (const [k2, v] of Object.entries(c.gas)) {
  console.log(`      ${k2.padEnd(28)} ${v.toLocaleString()}`);
}

console.log(`\n  ${fail === 0 ? "\x1b[32m" : "\x1b[31m"}${pass} passed, ${fail} failed\x1b[0m\n`);
process.exit(fail === 0 ? 0 : 1);
