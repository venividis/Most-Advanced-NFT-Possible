/*───────────────────────────────────────────────────────────────────────────
  Deploying the site, and speaking HTTP to it.

  Two tools need this and a third will: the front-door verifier, the service
  verifier, and the gas budget. A second copy of a deployment sequence is a
  second thing to forget to update, and the specific way that goes wrong here
  is a tool that keeps passing against a wiring nobody ships.
───────────────────────────────────────────────────────────────────────────*/
import { sel, encodeAddressArg } from "./evm.mjs";

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
export async function deploySite(c, A, { hub, pool, lease }) {
  const chrome = await c.deploy(A("src/Chrome.sol", "Chrome").bytecode, "", "Chrome");

  /*  Parley is the protocol, not a page: the rooms, the back-links that
      make a conversation walkable without an indexer, and the check that a
      message signed by an address is a message the token agreed to. It
      reads the collection and nothing reads it back.                     */
  const parley = await c.deploy(
    A("src/Parley.sol", "Parley").bytecode, encodeAddressArg(hub), "Parley");

  /*  Desk holds the application: the config block a page emits and the
      client that reads it. It knows the hub, the pool and the lease because
      the config is data about all three.                                 */
  const desk = await c.deploy(
    A("src/Desk.sol", "Desk").bytecode,
    encodeAddressArg(hub) + encodeAddressArg(pool) + encodeAddressArg(lease), "Desk");

  /*  And DeskTalk holds the client that reads a chat off a chain: the walk,
      the calldata, and the rule that nothing off the wire ever reaches the
      DOM as markup.                                                      */
  const deskTalk = await c.deploy(
    A("src/DeskTalk.sol", "DeskTalk").bytecode,
    encodeAddressArg(parley) + encodeAddressArg(hub), "DeskTalk");

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
    encodeAddressArg(parley), "PageManifest");

  const pDoor = await c.deploy(
    A("src/PageDoor.sol", "PageDoor").bytecode,
    encodeAddressArg(hub) + encodeAddressArg(chrome) + encodeAddressArg(desk) +
    encodeAddressArg(deskTalk) + encodeAddressArg(parley), "PageDoor");

  const pTalk = await c.deploy(
    A("src/PageTalk.sol", "PageTalk").bytecode,
    encodeAddressArg(hub) + encodeAddressArg(chrome) + encodeAddressArg(desk) +
    encodeAddressArg(deskTalk) + encodeAddressArg(parley), "PageTalk");

  const pRooms = await c.deploy(
    A("src/PageRooms.sol", "PageRooms").bytecode,
    encodeAddressArg(chrome) + encodeAddressArg(desk) +
    encodeAddressArg(deskTalk) + encodeAddressArg(parley), "PageRooms");

  const premises = await c.deploy(
    A("src/Premises.sol", "Premises").bytecode,
    encodeAddressArg(hub) + encodeAddressArg(chrome) + encodeAddressArg(pDoor) +
    encodeAddressArg(pToken) + encodeAddressArg(pMarket) + encodeAddressArg(pPool) +
    encodeAddressArg(pServices) + encodeAddressArg(pManifest) +
    encodeAddressArg(pTalk) + encodeAddressArg(pRooms),
    "Premises");

  return {
    chrome, parley, desk, deskTalk, pDoor, pToken, pMarket, pPool,
    pServices, pManifest, pTalk, pRooms, premises
  };
}
