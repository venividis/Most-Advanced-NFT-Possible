#!/usr/bin/env node
/*───────────────────────────────────────────────────────────────────────────
  IPSEITY · does ParleyPort speak the protocol's ABI, or the mock's?

  EndpointV2 calls ILayerZeroReceiver with `Origin calldata` — a STATIC
  struct (uint32,bytes32,uint64), three words inline. ParleyPort declares
  `bytes calldata origin`. Different canonical signature, different
  selector. And `verify()` calls `allowInitializePath(Origin)` on the
  receiver before the first packet on a lane can be marked verified.

  This drives the real encodings at the deployed bytecode and reports what
  the EVM says, rather than what either side claims.

      node tools/probe-port-abi.mjs
───────────────────────────────────────────────────────────────────────────*/
import { compile, artifact } from "./compile.mjs";
import { Chain, encodeAddressArg } from "./evm.mjs";

const out = compile({ quiet: true, dirs: ["src", "test/mocks"] });
const A = (f, n) => artifact(out, f, n);
const c = await Chain.open();
const w = (n) => BigInt(n).toString(16).padStart(64, "0");
const b32 = (a) => a.toLowerCase().replace(/^0x/, "").padStart(64, "0");
const pad = (h) => { h = h.replace(/^0x/, ""); return h + "0".repeat((64 - h.length % 64) % 64); };

const abi = A("src/ParleyPort.sol", "ParleyPort").abi;
console.log("\n  ParleyPort's declared external surface:");
for (const f of abi.filter(x => x.type === "function"))
  console.log("    " + f.name + "(" + f.inputs.map(i => i.type).join(",") + ")");

/*  A minimal stand-in for Parley (mayActAs) and an endpoint that only has
    to answer eid() and setDelegate() for the constructor to finish.     */
const stubSrc = `// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
contract LzStub {
  function eid() external pure returns (uint32) { return 30184; }
  function setDelegate(address) external {}
  function mayActAs(uint256, address) external pure returns (bool) { return true; }
  function MAX_BODY() external pure returns (uint256) { return 1024; }
}`;
const out2 = out;
const stub = await c.deploy(artifact(out2, "test/mocks/LzStub.sol", "LzStub").bytecode);
const port = await c.deploy(artifact(out2, "src/ParleyPort.sol", "ParleyPort").bytecode,
  encodeAddressArg(stub) + encodeAddressArg(stub) + w(0x80) + w(0xc0) +
  w(1) + w(30320) + w(1) + b32("0x" + "cd".repeat(20)));
console.log("\n  port deployed at " + port);

const shot = async (label, data) => {
  try {
    const r = await c.call(port, data);
    console.log(`    ${label.padEnd(52)} OK  -> ${String(r).slice(0, 34)}`);
  } catch (e) {
    console.log(`    ${label.padEnd(52)} REVERT  ${String(e.message).slice(0, 60)}`);
  }
};

const MSG = "0x" + w(30320) + w(1) + w(0) + w(0x80) + w(5) + pad("68656c6c6f");

console.log("\n  what the REAL EndpointV2 sends (Origin as a static 3-word tuple):");
/* lzReceive((uint32,bytes32,uint64),bytes32,bytes,address,bytes) = 0x13137d65
   head: srcEid, sender, nonce, guid, off(message), executor, off(extraData) */
await shot("0x13137d65 lzReceive(Origin,bytes32,bytes,address,bytes)",
  "0x13137d65" + w(30320) + b32("0x" + "cd".repeat(20)) + w(1) + w(0) +
  w(0xe0 + 64) + w(0) + w(0xe0 + 64 + 32 + pad(MSG.slice(2)).length / 2) +
  w(MSG.slice(2).length / 2) + pad(MSG.slice(2)) + w(0));

/* allowInitializePath((uint32,bytes32,uint64)) = 0xff7bd03d */
await shot("0xff7bd03d allowInitializePath(Origin)",
  "0xff7bd03d" + w(30320) + b32("0x" + "cd".repeat(20)) + w(1));

/* nextNonce(uint32,bytes32) = 0x7d25a05e */
await shot("0x7d25a05e nextNonce(uint32,bytes32)",
  "0x7d25a05e" + w(30320) + b32("0x" + "cd".repeat(20)));

console.log("\n  what the MOCK sends (Origin re-encoded as dynamic bytes):");
const ORIGIN = "0x" + w(30320) + b32("0x" + "cd".repeat(20)) + w(1);
await shot("0x42172c88 lzReceive(bytes,bytes32,bytes,address,bytes)",
  "0x42172c88" + w(0xa0) + w(0) + w(0xa0 + 32 + 96) + w(0) +
  w(0xa0 + 32 + 96 + 32 + pad(MSG.slice(2)).length / 2) +
  w(96) + ORIGIN.slice(2) + w(MSG.slice(2).length / 2) + pad(MSG.slice(2)) + w(0));

console.log("\n  (a `call` from a non-endpoint address is expected to hit NotTheEndpoint");
console.log("   0x1bea1cf2 — reaching that error at all is proof the selector dispatched.)");
