/*───────────────────────────────────────────────────────────────────────────
  Deploying the site, and speaking HTTP to it.

  Two tools need this and a third will: the front-door verifier, the service
  verifier, and the gas budget. A second copy of a deployment sequence is a
  second thing to forget to update, and the specific way that goes wrong here
  is a tool that keeps passing against a wiring nobody ships.
───────────────────────────────────────────────────────────────────────────*/
import { sel, encodeAddressArg } from "./evm.mjs";
import { keccak256 } from "ethereum-cryptography/keccak.js";

/*  ABI encoding for exactly the two shapes this file needs: a `string[]`
    going out, and a `(uint16,string,(string,string)[])` coming back. Both
    are laid out by hand, which is a small thing to own and a large thing to
    depend on somebody else for.                                          */
const w = (n) => BigInt(n).toString(16).padStart(64, "0");

const encStr = (s) => {
  const b = Buffer.from(s, "utf8");
  return w(b.length) + b.toString("hex").padEnd(Math.ceil(b.length / 32) * 64, "0");
};

const encStrArray = (arr) => {
  const bodies = arr.map(encStr);
  let off = arr.length * 32;
  const heads = bodies.map((b) => { const h = w(off); off += b.length / 2; return h; });
  return w(arr.length) + heads.join("") + bodies.join("");
};

/*──────────────── where Uniswap actually is ────────────────

  Every address below was probed for code over live RPC on 2026-08-19 —
  factory, SwapRouter02, QuoterV2 and the wrapped native, on each chain —
  not copied from memory. All four chains carry SwapRouter02, so every
  entry is routerKind 1: seven words, no deadline. A chain missing from
  this table deploys with NO_VENUE and the swap tab says so instead of
  failing.

  The stock-token consequence is the design, not the table: the card
  checks the pool for whatever address you paste, so a tokenized equity
  with v3 liquidity on that chain trades like anything else, and one
  without gets an honest "no pool" — there is no list here to be wrong. */
const ZERO = "0x0000000000000000000000000000000000000000";

export const UNISWAP = {
  1: {
    name: "Ethereum",
    factory: "0x1F98431c8aD98523631AE4a59f267346ea31F984",
    quoter: "0x61fFE014bA17989E743c5F6cB21bF9697530B21e",
    router: "0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45", routerKind: 1,
    positions: "0xC36442b4a4522E871399CD717aBDD847Ab11FE88",
    wrapped: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
    governor: ZERO, govToken: ZERO,
    poolManager: "0x000000000004444c5dc75cB358380D2e3dE08A90",
    ens: "0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e"
  },
  8453: {
    name: "Base",
    factory: "0x33128a8fC17869897dcE68Ed026d694621f6FDfD",
    quoter: "0x3d4e44Eb1374240CE5F1B871ab261CD16335B76a",
    router: "0x2626664c2603336E57B271c5C0b26F421741e481", routerKind: 1,
    positions: "0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1",
    wrapped: "0x4200000000000000000000000000000000000006",
    governor: ZERO, govToken: ZERO,
    poolManager: "0x498581fF718922c3f8e6A244956aF099B2652b2b"
  },
  84532: {
    name: "Base Sepolia",
    factory: "0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24",
    quoter: "0xC5290058841028F1614F3A6F0F5816cAd0df5E27",
    router: "0x94cC0AaC535CCDB3C01d6787D6413C739ae12bc4", routerKind: 1,
    positions: "0x27F971cb582BF9E50F397e4d29a5C7A34f11faA2",
    wrapped: "0x4200000000000000000000000000000000000006",
    governor: ZERO, govToken: ZERO,
    poolManager: "0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408"
  },
  11155111: {
    name: "Ethereum Sepolia",
    factory: "0x0227628f3F023bb0B980b67D528571c95c6DaC1c",
    quoter: "0xEd1f6473345F45b75F8179591dd5bA1888cf2FB3",
    router: "0x3bFA4769FB09eefC5a80d6E87c3B9C650f7Ae48E", routerKind: 1,
    positions: "0x1238536071E1c677A632429e3655c799b22cDA52",
    wrapped: "0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14",
    governor: ZERO, govToken: ZERO,
    poolManager: "0xE03A1074c86CFeDd5C142C4F04F1a1536e203543",
    ens: "0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e"
  }
};

/*  The address CREATE will produce for `sender` at `nonce` — keccak of the
    two, RLP-encoded. Used to hand a page the address of a contract that
    deploys after it; the deploy asserts the prediction held, so a reordered
    pipeline fails loudly instead of wiring a page to nothing.            */
export function predictCreate(sender, nonce) {
  const a = Buffer.from(sender.replace(/^0x/, ""), "hex");
  const n = BigInt(nonce);
  let nb;
  if (n === 0n) nb = Buffer.from([0x80]);
  else if (n < 0x80n) nb = Buffer.from([Number(n)]);
  else {
    let h = n.toString(16); if (h.length % 2) h = "0" + h;
    const raw = Buffer.from(h, "hex");
    nb = Buffer.concat([Buffer.from([0x80 + raw.length]), raw]);
  }
  const payload = Buffer.concat([Buffer.from([0x80 + a.length]), a, nb]);
  const rlp = Buffer.concat([Buffer.from([0xc0 + payload.length]), payload]);
  return "0x" + Buffer.from(keccak256(rlp)).toString("hex").slice(24);
}

/** A chain with no verified deployment: every read degrades to "no venue". */
export const NO_VENUE = {
  name: "nowhere in particular",
  factory: ZERO, quoter: ZERO, router: ZERO, routerKind: 0, poolManager: ZERO,
  positions: ZERO, wrapped: ZERO, governor: ZERO, govToken: ZERO
};

export const REQUEST = sel("request(string[],(string,string)[])");

export const encRequest = (resource) => {
  const res = encStrArray(resource);
  return REQUEST + w(0x40) + w(0x40 + res.length / 2) + res + w(0);
};

export const decResponse = (hex) => {
  const h = hex.replace(/^0x/, "");
  const status = Number(BigInt("0x" + h.substr(0, 64)));
  const bodyOff = Number(BigInt("0x" + h.substr(64, 64))) * 2;
  const hdrOff = Number(BigInt("0x" + h.substr(128, 64))) * 2;

  const bodyLen = Number(BigInt("0x" + h.substr(bodyOff, 64)));
  const body = Buffer.from(h.substr(bodyOff + 64, bodyLen * 2), "hex").toString("utf8");

  const n = Number(BigInt("0x" + h.substr(hdrOff, 64)));
  const headers = [];
  for (let i = 0; i < n; i++) {
    const t = hdrOff + 64 + Number(BigInt("0x" + h.substr(hdrOff + 64 + i * 64, 64))) * 2;
    const readAt = (at) => {
      const o = t + Number(BigInt("0x" + h.substr(at, 64))) * 2;
      const len = Number(BigInt("0x" + h.substr(o, 64)));
      return Buffer.from(h.substr(o + 64, len * 2), "hex").toString("utf8");
    };
    headers.push([readAt(t), readAt(t + 64)]);
  }
  return { status, body, headers };
};

/// @notice A GET against a deployed Premises, returning status/body/headers.
export const getter = (c, premises) => async (path) =>
  decResponse(await c.call(premises, encRequest(path)));

/*──────────────── the deployment ────────────────*/

/**
 * Deploy Chrome, Parley, the two desks, the seven page contracts and the
 * router.
 *
 * Every page address is an immutable constructor argument of Premises, and
 * Premises is the only thing that knows all of them. Replacing a page means
 * deploying a new router and pointing a name at it, which is the property
 * that keeps the routes serving the artwork off the mutable path.
 */
export async function deploySite(c, A,
    { hub, pool, lease, sigil, parley: existingParley, uniswap = NO_VENUE }) {
  const chrome = await c.deploy(A("src/Chrome.sol", "Chrome").bytecode, "", "Chrome");

  /*  Parley is the protocol, not a page: the rooms, the back-links that
      make a conversation walkable without an indexer, and the check that a
      message signed by an address is a message the token agreed to. It
      reads the collection and nothing reads it back.                     */
  /*  The parley is the protocol, and every message ever sent is a log this
      address emitted — a redeploy of the SITE reuses it, because replacing
      it would not migrate a conversation, it would end one.             */
  const parley = existingParley ||
    await c.deploy(A("src/Parley.sol", "Parley").bytecode, encodeAddressArg(hub), "Parley");

  /*  The kiln launches (gated by holding a token), the locker keeps.
      The kiln learns the PoolManager so the Gate hooks it ships refuse
      callbacks from anywhere else.                                       */
  const kiln = await c.deploy(
    A("src/Kiln.sol", "Kiln").bytecode,
    encodeAddressArg(hub) + encodeAddressArg(uniswap.poolManager || ZERO), "Kiln");
  const locker = await c.deploy(
    A("src/Locker.sol", "Locker").bytecode, "", "Locker");

  /*  Venue takes a `Wiring` struct — a static tuple, so it encodes flat in
      declaration order with no offset word. Getting that wrong would put
      the quoter where the router goes.                                   */
  const venue = await c.deploy(
    A("src/Venue.sol", "Venue").bytecode,
    encodeAddressArg(uniswap.factory) +
    encodeAddressArg(uniswap.quoter) +
    encodeAddressArg(uniswap.router) +
    BigInt(uniswap.routerKind).toString(16).padStart(64, "0") +
    encodeAddressArg(uniswap.positions) +
    encodeAddressArg(uniswap.wrapped) +
    encodeAddressArg(uniswap.governor) +
    encodeAddressArg(uniswap.govToken) +
    encodeAddressArg(uniswap.poolManager || ZERO),
    "Venue");

  const deskU = await c.deploy(
    A("src/DeskUni.sol", "DeskUni").bytecode,
    encodeAddressArg(venue) + encodeAddressArg(pool), "DeskUni");
  const deskT = await c.deploy(A("src/DeskTrade.sol", "DeskTrade").bytecode, "", "DeskTrade");

  /*  Desk holds the application: the config block a page emits and the
      client that reads it. It knows the hub, the pool and the lease because
      the config is data about all three.                                 */
  const desk = await c.deploy(
    A("src/Desk.sol", "Desk").bytecode,
    encodeAddressArg(hub) + encodeAddressArg(pool) + encodeAddressArg(lease), "Desk");

  /*  And DeskTalk holds the client that reads a chat off a chain: the walk,
      the calldata, and the rule that nothing off the wire ever reaches the
      DOM as markup.                                                      */
  /*  A read-only companion over the archive: it answers who is in a room by
      asking the mapping directly, a window of tokens per call, so nothing
      needs replaying and nothing about Parley had to change to make
      membership visible. It can be replaced any week; the archive does not
      notice.                                                            */
  const roster = await c.deploy(
    A("src/Roster.sol", "Roster").bytecode,
    encodeAddressArg(parley) + encodeAddressArg(hub), "Roster");

  const deskTalk = await c.deploy(
    A("src/DeskTalk.sol", "DeskTalk").bytecode,
    encodeAddressArg(parley) + encodeAddressArg(hub) +
    encodeAddressArg(roster), "DeskTalk");
  const deskSeal = await c.deploy(
    A("src/DeskSeal.sol", "DeskSeal").bytecode, "", "DeskSeal");

  const pSwap = await c.deploy(
    A("src/PageSwap.sol", "PageSwap").bytecode,
    encodeAddressArg(chrome) + encodeAddressArg(pool) + encodeAddressArg(desk) +
    encodeAddressArg(deskU) + encodeAddressArg(deskT) + encodeAddressArg(venue),
    "PageSwap");

  const pToken = await c.deploy(
    A("src/PageToken.sol", "PageToken").bytecode,
    encodeAddressArg(hub) + encodeAddressArg(chrome) +
    encodeAddressArg(pool) + encodeAddressArg(lease), "PageToken");

  const pMarket = await c.deploy(
    A("src/PageMarket.sol", "PageMarket").bytecode,
    encodeAddressArg(hub) + encodeAddressArg(chrome) +
    encodeAddressArg(pool) + encodeAddressArg(desk), "PageMarket");

  const pPool = await c.deploy(
    A("src/PagePool.sol", "PagePool").bytecode,
    encodeAddressArg(hub) + encodeAddressArg(chrome) +
    encodeAddressArg(pool) + encodeAddressArg(desk), "PagePool");

  const pServices = await c.deploy(
    A("src/PageServices.sol", "PageServices").bytecode,
    encodeAddressArg(hub) + encodeAddressArg(chrome) +
    encodeAddressArg(lease) + encodeAddressArg(desk), "PageServices");

  const pManifest = await c.deploy(
    A("src/PageManifest.sol", "PageManifest").bytecode,
    encodeAddressArg(hub) + encodeAddressArg(pool) + encodeAddressArg(lease) +
    encodeAddressArg(parley) + encodeAddressArg(kiln) +
    encodeAddressArg(locker) + encodeAddressArg(venue),
    "PageManifest");

  const deskTerm = await c.deploy(
    A("src/DeskTerm.sol", "DeskTerm").bytecode,
    encodeAddressArg(hub) + encodeAddressArg(pool) + encodeAddressArg(lease) +
    encodeAddressArg(parley) + encodeAddressArg(kiln) + encodeAddressArg(locker) +
    encodeAddressArg(roster),
    "DeskTerm");

  const deskRooms = await c.deploy(
    A("src/DeskRooms.sol", "DeskRooms").bytecode, "", "DeskRooms");

  const pTerminal = await c.deploy(
    A("src/PageTerminal.sol", "PageTerminal").bytecode,
    encodeAddressArg(chrome) + encodeAddressArg(desk) + encodeAddressArg(deskTerm) +
    encodeAddressArg(deskRooms),
    "PageTerminal");

  const pGallery = await c.deploy(
    A("src/PageGallery.sol", "PageGallery").bytecode,
    encodeAddressArg(hub) + encodeAddressArg(chrome) + encodeAddressArg(pool) +
    encodeAddressArg(lease) + encodeAddressArg(sigil), "PageGallery");

  const deskL = await c.deploy(
    A("src/DeskLaunch.sol", "DeskLaunch").bytecode, "", "DeskLaunch");
  const pLaunch = await c.deploy(
    A("src/PageLaunch.sol", "PageLaunch").bytecode,
    encodeAddressArg(chrome) + encodeAddressArg(desk) + encodeAddressArg(deskU) +
    encodeAddressArg(deskL) + encodeAddressArg(venue) + encodeAddressArg(kiln),
    "PageLaunch");
  const pLock = await c.deploy(
    A("src/PageLock.sol", "PageLock").bytecode,
    encodeAddressArg(chrome) + encodeAddressArg(desk) + encodeAddressArg(locker),
    "PageLock");
  const pHook = await c.deploy(
    A("src/PageHook.sol", "PageHook").bytecode,
    encodeAddressArg(chrome), "PageHook");
  const pCast = await c.deploy(
    A("src/PageCast.sol", "PageCast").bytecode,
    encodeAddressArg(chrome) + encodeAddressArg(desk) + encodeAddressArg(sigil),
    "PageCast");

  const pDoor = await c.deploy(
    A("src/PageDoor.sol", "PageDoor").bytecode,
    encodeAddressArg(hub) + encodeAddressArg(chrome) + encodeAddressArg(desk) +
    encodeAddressArg(deskTalk) + encodeAddressArg(parley) +
    encodeAddressArg(deskTerm) + encodeAddressArg(deskRooms), "PageDoor");

  const pTalk = await c.deploy(
    A("src/PageTalk.sol", "PageTalk").bytecode,
    encodeAddressArg(hub) + encodeAddressArg(chrome) + encodeAddressArg(desk) +
    encodeAddressArg(deskTalk) + encodeAddressArg(parley) +
    encodeAddressArg(deskSeal), "PageTalk");

  const pRooms = await c.deploy(
    A("src/PageRooms.sol", "PageRooms").bytecode,
    encodeAddressArg(chrome) + encodeAddressArg(desk) +
    encodeAddressArg(deskTalk) + encodeAddressArg(parley), "PageRooms");

  const pSeal = await c.deploy(
    A("src/PageSeal.sol", "PageSeal").bytecode,
    encodeAddressArg(chrome) + encodeAddressArg(desk) + encodeAddressArg(hub),
    "PageSeal");

  const pKeys = await c.deploy(
    A("src/PageKeys.sol", "PageKeys").bytecode,
    encodeAddressArg(chrome) + encodeAddressArg(desk) + encodeAddressArg(hub),
    "PageKeys");

  /*  Three contracts, one cycle: the name page must know the resolver, the
      resolver must know the premises, and the premises must know the name
      page. Somebody has to be told where a contract will be before it is
      there, so the resolver's address is computed from the deployer and the
      nonce it will hold — this deploy, then the premises, then it — and
      asserted the moment it exists. A prediction that quietly missed would
      wire this page to an address with nothing at it.                    */
  const nameplateWillBe = predictCreate(c.from.toString(), (await c.nonceNow()) + 2n);

  const pName = await c.deploy(
    A("src/PageName.sol", "PageName").bytecode,
    encodeAddressArg(chrome) + encodeAddressArg(desk) +
    encodeAddressArg(nameplateWillBe) + encodeAddressArg(hub),
    "PageName");

  const premises = await c.deploy(
    A("src/Premises.sol", "Premises").bytecode,
    encodeAddressArg(hub) + encodeAddressArg(chrome) + encodeAddressArg(pDoor) +
    encodeAddressArg(pToken) + encodeAddressArg(pMarket) + encodeAddressArg(pPool) +
    encodeAddressArg(pServices) + encodeAddressArg(pManifest) +
    encodeAddressArg(pTalk) + encodeAddressArg(pRooms) +
    encodeAddressArg(pTerminal) + encodeAddressArg(pSwap) + encodeAddressArg(pGallery) +
    encodeAddressArg(pLaunch) + encodeAddressArg(pLock) + encodeAddressArg(pHook) +
    encodeAddressArg(pCast) + encodeAddressArg(pSeal) +
    encodeAddressArg(pKeys) + encodeAddressArg(pName),
    "Premises");

  /*  The resolver deploys on every chain so the address matches
      everywhere; where no ENS registry exists, binding refuses and says
      why. It learns the premises, so it must follow it.                */
  const nameplate = await c.deploy(
    A("src/Nameplate.sol", "Nameplate").bytecode,
    encodeAddressArg(uniswap.ens || ZERO) + encodeAddressArg(hub) +
    encodeAddressArg(premises), "Nameplate");

  if (nameplate.toLowerCase() !== nameplateWillBe.toLowerCase()) {
    throw new Error(`the resolver landed at ${nameplate}, not the ${nameplateWillBe} ` +
      `the name page was given — a deploy was inserted between them`);
  }

  return {
    chrome, parley, roster, deskRooms, kiln, locker, venue, nameplate, deskU, deskT, deskL, deskSeal, pSwap, desk, deskTalk, deskTerm,
    pDoor, pToken, pMarket, pPool, pServices, pManifest, pTalk, pRooms,
    pTerminal, pGallery, pLaunch, pLock, pHook, pCast,
    pSeal, pKeys, pName, premises
  };
}
