/*───────────────────────────────────────────────────────────────────────────
  Deploying the site, and speaking HTTP to it.

  Two tools need this and a third will: the front-door verifier, the service
  verifier, and the gas budget. A second copy of a deployment sequence is a
  second thing to forget to update, and the specific way that goes wrong here
  is a tool that keeps passing against a wiring nobody ships.
───────────────────────────────────────────────────────────────────────────*/
import { sel, encodeAddressArg } from "./evm.mjs";

/*──────────────── where Uniswap actually is ────────────────

  Read from Uniswap's own deployment docs, not from memory, and kept here
  rather than in Solidity because they are a deployment fact and not a
  property of the collection. `Venue` takes all seven as constructor
  arguments; a chain with no deployment takes zeros and every page degrades
  to "no venue" instead of failing.

  The four v3 addresses are identical on Ethereum, Arbitrum, Optimism and
  Polygon, and every one of them is different on Base — which is exactly the
  shape of mistake a hardcoded constant makes: right four times, wrong once,
  and wrong in a way that shows a plausible page.

  `routerKind` travels with `router` because it decides the calldata shape.
  0 = v3-periphery SwapRouter, eight words, deadline at index 4.
  1 = SwapRouter02, seven words, no deadline. Base has no v3-periphery
  SwapRouter deployed, so Base is necessarily kind 1.                     */
export const UNISWAP = {
  1: {
    name: "Ethereum",
    factory: "0x1F98431c8aD98523631AE4a59f267346ea31F984",
    quoter: "0x61fFE014bA17989E743c5F6cB21bF9697530B21e",
    router: "0xE592427A0AEce92De3Edee1F18E0157C05861564",
    routerKind: 0,
    positions: "0xC36442b4a4522E871399CD717aBDD847Ab11FE88",
    wrapped: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
    governor: "0x408ED6354d4973f66138C91495F2f2FCbd8724C3",
    poolManager: "0x000000000004444c5dc75cB358380D2e3dE08A90",
    govToken: "0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984"},
  42161: {
    name: "Arbitrum One",
    factory: "0x1F98431c8aD98523631AE4a59f267346ea31F984",
    quoter: "0x61fFE014bA17989E743c5F6cB21bF9697530B21e",
    router: "0xE592427A0AEce92De3Edee1F18E0157C05861564",
    routerKind: 0,
    positions: "0xC36442b4a4522E871399CD717aBDD847Ab11FE88",
    wrapped: "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1",
    governor: "0x0000000000000000000000000000000000000000",
    poolManager: "0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32",
    govToken: "0x0000000000000000000000000000000000000000"},
  10: {
    name: "Optimism",
    factory: "0x1F98431c8aD98523631AE4a59f267346ea31F984",
    quoter: "0x61fFE014bA17989E743c5F6cB21bF9697530B21e",
    router: "0xE592427A0AEce92De3Edee1F18E0157C05861564",
    routerKind: 0,
    positions: "0xC36442b4a4522E871399CD717aBDD847Ab11FE88",
    wrapped: "0x4200000000000000000000000000000000000006",
    governor: "0x0000000000000000000000000000000000000000",
    poolManager: "0x9a13F98Cb987694C9F086b1F5eB990EeA8264Ec3",
    govToken: "0x0000000000000000000000000000000000000000"},
  137: {
    name: "Polygon",
    factory: "0x1F98431c8aD98523631AE4a59f267346ea31F984",
    quoter: "0x61fFE014bA17989E743c5F6cB21bF9697530B21e",
    router: "0xE592427A0AEce92De3Edee1F18E0157C05861564",
    routerKind: 0,
    positions: "0xC36442b4a4522E871399CD717aBDD847Ab11FE88",
    wrapped: "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270",
    governor: "0x0000000000000000000000000000000000000000",
    poolManager: "0x67366782805870060151383F4BbFF9daB53e5cD6",
    govToken: "0x0000000000000000000000000000000000000000"},
  8453: {
    name: "Base",
    factory: "0x33128a8fC17869897dcE68Ed026d694621f6FDfD",
    quoter: "0x3d4e44Eb1374240CE5F1B871ab261CD16335B76a",
    router: "0x2626664c2603336E57B271c5C0b26F421741e481",
    routerKind: 1,
    positions: "0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1",
    wrapped: "0x4200000000000000000000000000000000000006",
    governor: "0x0000000000000000000000000000000000000000",
    poolManager: "0x498581fF718922c3f8e6A244956aF099B2652b2b",
    govToken: "0x0000000000000000000000000000000000000000"}
};

const ZERO = "0x0000000000000000000000000000000000000000";

/** A chain with no Uniswap deployment. Every read degrades to "no venue". */
export const NO_VENUE = {
  name: "nowhere in particular",
  factory: ZERO, quoter: ZERO, router: ZERO, routerKind: 0,
  positions: ZERO, wrapped: ZERO, governor: ZERO, govToken: ZERO,
  poolManager: ZERO
};

/*──────────────── ERC-5219 on the wire ────────────────*/

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

/* request(string[],(string,string)[]) — two dynamic arrays in the head */
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
 * Deploy Chrome, the four page contracts and the router.
 *
 * Every page address is an immutable constructor argument of Premises, and
 * Premises is the only thing that knows all of them. Replacing a page means
 * deploying a new router and pointing a name at it, which is the property
 * that keeps the routes serving the artwork off the mutable path.
 */
export async function deploySite(c, A, { hub, pool, lease, uniswap = NO_VENUE }) {
  const chrome = await c.deploy(A("src/Chrome.sol", "Chrome").bytecode, "", "Chrome");

  /*  Venue takes a `Wiring` struct, which as a constructor argument is a
      *static* tuple — seven addresses and a uint8, all fixed-size — so it
      encodes flat, in declaration order, with no offset word. Getting that
      wrong would put the quoter where the router goes.                    */
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
    encodeAddressArg(uniswap.poolManager ||
      "0x0000000000000000000000000000000000000000"),
    "Venue");

  /*  Desk holds the application: the config block a page emits and the
      client that reads it. It knows the hub, the pool and the lease because
      the config is data about all three.                                 */
  const desk = await c.deploy(
    A("src/Desk.sol", "Desk").bytecode,
    encodeAddressArg(hub) + encodeAddressArg(pool) + encodeAddressArg(lease), "Desk");

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
    encodeAddressArg(venue), "PageManifest");

  /*  The Uniswap side: one contract holding the data (addresses, the
      derived asset list, every selector) and one holding the programs that
      use it. Split because together they exceed EIP-170, and the split is
      where a reader would want it anyway.                                */
  const deskU = await c.deploy(
    A("src/DeskUni.sol", "DeskUni").bytecode,
    encodeAddressArg(venue) + encodeAddressArg(pool), "DeskUni");

  const deskT = await c.deploy(A("src/DeskTrade.sol", "DeskTrade").bytecode, "", "DeskTrade");

  const pSwap = await c.deploy(
    A("src/PageSwap.sol", "PageSwap").bytecode,
    encodeAddressArg(chrome) + encodeAddressArg(pool) + encodeAddressArg(desk) +
    encodeAddressArg(deskU) + encodeAddressArg(deskT) + encodeAddressArg(venue),
    "PageSwap");

  const pPools = await c.deploy(
    A("src/PagePools.sol", "PagePools").bytecode,
    encodeAddressArg(chrome) + encodeAddressArg(pool) + encodeAddressArg(desk) +
    encodeAddressArg(deskU) + encodeAddressArg(deskT) + encodeAddressArg(venue),
    "PagePools");

  const deskC = await c.deploy(A("src/DeskCivic.sol", "DeskCivic").bytecode, "", "DeskCivic");

  const pCivic = await c.deploy(
    A("src/PageCivic.sol", "PageCivic").bytecode,
    encodeAddressArg(chrome) + encodeAddressArg(pool) + encodeAddressArg(desk) +
    encodeAddressArg(deskU) + encodeAddressArg(deskC) + encodeAddressArg(venue),
    "PageCivic");

  const pExplore = await c.deploy(
    A("src/PageExplore.sol", "PageExplore").bytecode,
    encodeAddressArg(chrome) + encodeAddressArg(pool) + encodeAddressArg(desk) +
    encodeAddressArg(deskU) + encodeAddressArg(deskC) + encodeAddressArg(venue),
    "PageExplore");

  /*  The launchpad. `Kiln` is this collection's own contract — it deploys
      tokens and hooks and has no other power over either — and it needs the
      v4 PoolManager because the hooks it ships accept calls from nothing
      else.                                                                */
  const kiln = await c.deploy(
    A("src/Kiln.sol", "Kiln").bytecode,
    encodeAddressArg(uniswap.poolManager ||
      "0x0000000000000000000000000000000000000000"), "Kiln");

  const deskL = await c.deploy(A("src/DeskLaunch.sol", "DeskLaunch").bytecode, "", "DeskLaunch");

  const pLaunch = await c.deploy(
    A("src/PageLaunch.sol", "PageLaunch").bytecode,
    encodeAddressArg(chrome) + encodeAddressArg(desk) + encodeAddressArg(deskU) +
    encodeAddressArg(deskL) + encodeAddressArg(venue) + encodeAddressArg(kiln),
    "PageLaunch");

  const pHook = await c.deploy(
    A("src/PageHook.sol", "PageHook").bytecode,
    encodeAddressArg(chrome), "PageHook");

  const premises = await c.deploy(
    A("src/Premises.sol", "Premises").bytecode,
    encodeAddressArg(hub) + encodeAddressArg(chrome) + encodeAddressArg(pToken) +
    encodeAddressArg(pMarket) + encodeAddressArg(pPool) + encodeAddressArg(pServices) +
    encodeAddressArg(pManifest) + encodeAddressArg(pSwap) + encodeAddressArg(pPools) +
    encodeAddressArg(pCivic) + encodeAddressArg(pExplore) +
    encodeAddressArg(pLaunch) + encodeAddressArg(pHook),
    "Premises");

  return {
    chrome, desk, pToken, pMarket, pPool, pServices, pManifest,
    venue, deskU, deskT, deskC, pSwap, pPools, pCivic, pExplore, kiln, deskL, pLaunch, pHook, premises
  };
}
