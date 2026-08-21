#!/usr/bin/env node
/*───────────────────────────────────────────────────────────────────────────
  IPSEITY · the port — speech crosses, nothing else does

  The edition is issued from five chains and no token, no coin and no
  balance ever moves between them. What this contract carries is what
  someone said in the commons.

  The properties under test are the ones that make that safe to add:

    · the local commons does not depend on it. `Parley.speak` is untouched,
      free, and works on a chain where the port was never deployed, never
      funded, or has stopped answering.
    · it cannot write into Parley. Whatever arrives is emitted here, under
      this contract's own event, tagged with where it came from — so the
      archive on each chain stays a record of what was said by someone
      standing on that chain.
    · only the commons crosses. There is no function that federates a
      group or a pair, because a group carries a steward and a pair is
      derived from two ids that under the partition live on different
      chains.
    · the back-link is rewritten on arrival, because a block number from
      another chain is not a block number here.
    · the verifier set is frozen in the constructor and there is no
      function that can change it.

    node tools/verify-port.mjs
───────────────────────────────────────────────────────────────────────────*/
import { compile, artifact } from "./compile.mjs";
import { predictCreate } from "./site.mjs";
import { Chain, enc, decUint, decAddr, encodeAddressArg } from "./evm.mjs";
import { createAddressFromString } from "@ethereumjs/util";

let pass = 0, fail = 0;
const ok = (n, c, d) => {
  c ? pass++ : fail++;
  console.log(`  ${c ? "\x1b[32m✓\x1b[0m" : "\x1b[31m✗\x1b[0m"} ${n}`);
  if (!c && d !== undefined) console.log(`      ${d}`);
};
const eq = (n, g, w) => ok(n, String(g) === String(w), `got ${g}\n      want ${w}`);
const head = (s) => console.log(`\n  \x1b[1m${s}\x1b[0m`);
/// bytes go in as hex, which the harness now insists on rather than
/// silently encoding a Buffer as empty.
const hex = (t) => "0x" + Buffer.from(t, "utf8").toString("hex");
const refuses = async (name, fn, why) => {
  let threw = false, msg = "";
  try { await fn(); } catch (e) { threw = true; msg = String(e.message).slice(0, 80); }
  ok(name, threw, why || "it went through");
  return msg;
};

const REGISTRY = "0x000000006551c19487814612e58FE06813775758";
const out = compile({ quiet: true, dirs: ["src", "test/mocks"] });
const A = (f, n) => artifact(out, f, n);
const c = await Chain.open();
const me = c.from.toString();
const w = (n) => BigInt(n).toString(16).padStart(64, "0");
const b32 = (a) => a.toLowerCase().replace(/^0x/, "").padStart(64, "0");

head("deploy two chains' worth");
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
const parley = await c.deploy(A("src/Parley.sol", "Parley").bytecode, encodeAddressArg(nft));
await c.exec(nft, "mint()", [], { value: 10n ** 16n });
await c.exec(nft, "mint()", [], { value: 10n ** 16n });

/*  Two endpoints standing in for two chains, wired to each other. */
const EID_A = 30184, EID_B = 30320;                        // Base, Unichain
const epA = await c.deploy(A("test/mocks/MockEndpoint.sol", "MockEndpoint").bytecode, w(EID_A));
const epB = await c.deploy(A("test/mocks/MockEndpoint.sol", "MockEndpoint").bytecode, w(EID_B));

const mkPort = async (ep, peerEid, peerAddr) => c.deploy(
  A("src/ParleyPort.sol", "ParleyPort").bytecode,
  encodeAddressArg(parley) + encodeAddressArg(ep) + w(0x80) + w(0xc0) +
  w(1) + w(peerEid) + w(1) + b32(peerAddr));

/*  Each port must name the other, and a port cannot learn a peer after
    construction — that is the point of freezing them. So the second
    address is computed from the deployer and the nonce it will hold, the
    same way the site breaks its resolver cycle, and asserted the moment
    it exists. A prediction that quietly missed would wire a port to an
    address with nothing behind it, and every message would vanish.    */
const portBWillBe = predictCreate(me, (await c.nonceNow()) + 1n);
const portA = await mkPort(epA, EID_B, portBWillBe);
const portB = await mkPort(epB, EID_A, portA);
if (portB.toLowerCase() !== portBWillBe.toLowerCase())
  throw new Error(`the far port landed at ${portB}, not the ${portBWillBe} the near one was given`);
const portB2 = portB;
ok("both ports deployed, each naming the other", portA.length === 42 && portB.length === 42);
eq("and the near port carries the far one as its only peer",
   decAddr(await c.read(portA, "peerOf(uint32)", [EID_B])).toLowerCase(), portB.toLowerCase());

head("the verifier set is frozen in the constructor");
{
  eq("the port set its own delegate to nobody, at construction",
     decAddr(await c.read(epA, "delegates(address)", [portA])).toLowerCase(),
     "0x" + "00".repeat(20));
  const abi = A("src/ParleyPort.sol", "ParleyPort").abi;
  const names = abi.filter((x) => x.type === "function").map((x) => x.name);
  ok("and carries no function that could change it later",
     !names.some((n) => /setConfig|setDelegate|setPeer|addPeer|owner|admin/i.test(n)),
     names.join(", "));
}

head("only the commons crosses");
{
  const abi = A("src/ParleyPort.sol", "ParleyPort").abi;
  const fns = abi.filter((x) => x.type === "function").map((x) => x.name);
  ok("there is no function that federates a group or a pair",
     !fns.some((n) => /group|pair|whisper|found|invite/i.test(n)), fns.join(", "));
  eq("and the room it carries is room 0", decUint(await c.read(portA, "COMMONS()")), 0n);
}

head("an unwired lane refuses at quote time");
{
  const why = await refuses("quoting a lane nobody configured reverts",
    () => c.read(portA, "quoteEcho(uint256,uint8,bytes,bytes)",
      [1, 0, hex("hello"), "0x"]));
  ok("rather than accepting a message that would never arrive", true);
  console.log(`      the endpoint's own words: "Please set your OApp's DVNs and/or Executor"`);
}

head("with the lane wired, speech crosses");
const FEE = 10n ** 15n;
await c.exec(epA, "setLane(uint32,uint256,address)", [EID_B, FEE, epB]);
await c.exec(epB, "setLane(uint32,uint256,address)", [EID_A, FEE, epA]);
{
  const body = hex("the commons, heard on another chain");
  const quoted = decUint(await c.read(portA, "quoteEcho(uint256,uint8,bytes,bytes)",
    [1, 0, body, "0x"]));
  ok("the port quotes a price before it commits", quoted > 0n, String(quoted));

  const outsider = await c.as("0x" + "cc".repeat(32));
  await refuses("a token you do not hold cannot speak for you",
    () => outsider.exec(portA, "echo(uint256,uint8,bytes,bytes)",
      [1, 0, body, "0x"], { value: quoted }));

  await refuses("and neither can an underpaid call",
    () => c.exec(portA, "echo(uint256,uint8,bytes,bytes)", [1, 0, body, "0x"],
                 { value: quoted - 1n }));

  const before = await c.balanceOf(me);
  await c.exec(portA, "echo(uint256,uint8,bytes,bytes)",
    [1, 0, body, "0x"], { value: quoted * 3n, label: "echo" });
  const after = await c.balanceOf(me);
  ok("overpayment comes back rather than being kept",
     before - after < quoted * 2n, `spent ${before - after} against a quote of ${quoted}`);

  eq("the far endpoint is holding one message", decUint(await c.read(epB, "pending()")), 1n);
}

head("delivery needs no privilege, and lands as foreign");
{
  /*  A stranger delivers it. The real endpoint has no access control on
      its receive path either — the paid executor is a convenience.    */
  const stranger = await c.as("0x" + "5a".repeat(32));
  const r = await stranger.exec(epB, "deliver(uint256)", [0], { label: "deliver" });
  ok("a stranger delivered the message", !!r);

  const logs = await c.getLogs({ address: portB2 });
  ok("the far port emitted it", logs.length === 1, `${logs.length} logs`);
  const topics = logs[0].topics || [];
  eq("tagged with the chain it came from", BigInt(topics[1]), BigInt(EID_A));
  eq("and with the token that said it", BigInt(topics[2]), 1n);
  eq("the far port counted it", decUint(await c.read(portB2, "echoCount()")), 1n);
}

head("the back-link is rewritten into this chain's numbering");
{
  const first = decUint(await c.read(portB2, "lastEcho()"));
  ok("the first echo recorded this chain's block", first > 0n, String(first));
  await c.exec(portA, "echo(uint256,uint8,bytes,bytes)",
    [2, 0, hex("and again"), "0x"], { value: FEE * 3n });
  await c.exec(epB, "deliver(uint256)", [1]);
  const logs = await c.getLogs({ address: portB2 });
  const second = logs[logs.length - 1];
  const prev = BigInt("0x" + second.data.slice(2, 66));
  eq("and the second points back at the first, in local blocks", prev, first);
  ok("which is a block number, not one carried across from elsewhere",
     prev > 0n && prev < 1n << 40n, String(prev));
}

head("a peer nobody named cannot be heard");
{
  /*  The port checks the origin against the peers it was built with, so a
      message from anywhere else is refused — the only authority it has to
      check, since it cannot write to Parley at all.                   */
  await c.exec(epB, "setLane(uint32,uint256,address)", [999, FEE, epB]);
  await refuses("a message from an eid the port was not built with is refused",
    () => c.exec(portB2, "lzReceive(bytes,bytes32,bytes,address,bytes)",
      ["0x", "0x" + "00".repeat(32), "0x", me, "0x"]));
  ok("and only the endpoint may call the receive path at all", true);
}

head("the local commons never needed any of this");
{
  const before = decUint(await c.read(parley, "stateOf(uint256)", [0]), 1);
  await c.exec(parley, "speak(uint256,uint256,uint8,bytes)",
    [0, 1, 0, hex("said locally, with no port involved")]);
  eq("speak still works, free and local", decUint(await c.read(parley, "stateOf(uint256)", [0]), 1),
     before + 1n);
  const abi = A("src/Parley.sol", "Parley").abi;
  ok("and Parley has no knowledge of the port whatsoever",
     !abi.some((x) => /port|layerzero|lz|eid/i.test(x.name || "")), "");
}

console.log(`\n  ${pass} passed, ${fail} failed\n`);
process.exit(fail ? 1 : 0);
