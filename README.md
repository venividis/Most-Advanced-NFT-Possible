# IPSEITY

*ipseity, n. — the property of being oneself; selfhood as distinct from any of its appearances.*

A four-dimensional solid, and the instrument for turning it, are the same token.

---

## What it is

What a holder sees is a **three-dimensional section of a 4-polytope**. The solid is
never on screen — only the 3-space that currently cuts through it. Slide that space
along the fourth axis and a tesseract passes through cube, truncated cube, hexagon,
point. Nothing about the solid changed. Only where you stood.

The orientation of that cut — six plane angles, a position along `w`, which solid,
and the colour the interface takes from it — is **one 256-bit word** in the
contract's storage.

`tokenURI()` returns the instrument for editing that word. It is a WebGL2 engine, a
keccak-256, an ABI coder and a wallet client, held in the chain's state as contract
bytecode and handed back as a `data:` URI. It connects a wallet, reads the contract,
encodes its own calldata, and signs transactions — including transactions against
the token, which change the word, which changes what it renders the next time
anyone opens it.

Nothing is fetched. No IPFS, no gateway, no CDN, no font, no library, no build step
at read time.

---

## What is actually new here

Plenty of NFTs put HTML on chain. These are the parts that are not just that.

**The state is the geometry, and the geometry is editable.** Most on-chain
generative work fixes a seed at mint and renders a function of it forever. Here the
seed only decides where a token *starts*. The six rotation angles are live, holder-
writable state, and three of those six planes contain `w` — turning in those does
not spin the picture, it changes **what shape the section is**. The artwork has a
control surface because the artwork is a parameterised object and the parameters are
on chain.

**The still image is the complement of the animation, not a thumbnail of it.**
`Sigil.sol` is a 4D projector written in Solidity. It takes the token's committed
orientation, turns sixteen 4-vectors by six Givens rotations, divides through by
distance along `w`, and emits SVG path data. So the animation shows *the section and
never the whole*, and the still shows *the whole and nothing you could stand inside*.
Both are computed from the same word. There is no off-chain renderer anywhere in the
pipeline, including for the marketplace thumbnail.

**Four elevations.** A 3D object has three orthographic views. A 4D object has four.
`quartet()` draws the same solid projected along x, along y, along z, and along w —
three of those are drawings that nothing three-dimensional could cast. It is exposed
as an ERC-7160 face, so a holder can pin it as the token's public face.

**Gzip, inflated by the browser's own decompressor.** The document is stored as gzip
bytes and `tokenURI()` emits a short loader that hands them to
`DecompressionStream("gzip")` — part of the web platform since 2023, so nothing is
fetched. This is not a micro-optimisation: it is the difference between **7.2M and
20.1M gas** to put the document on chain, and between a 61 KB and a 163 KB
`tokenURI` response.

**It opens itself, inside itself.** The Nest instrument calls `tokenURI()` on chain,
decodes the base64, raises a depth counter, and mounts the result in a frame
positioned in the same 3-space as the solid. The instance inside can do it again.

---

## The market — every token is its own exchange

A token can hold two assets and let **anyone** trade against them. The holder is the
sole liquidity provider: they put the inventory in, they set the fee, they take the
fee, they take it back out. Because the right to all of that is "whoever `ownerOf()`
says", **selling the NFT sells the exchange** — reserves, fee income and price curve,
in one transaction, with no migration.

**The curve is the solid.** The pool prices on constant product with *virtual
reserves*, and those come from how far the artwork has been turned through `w` — the
same three rotation planes that change the shape of the section:

```
solid barely turned    →  concentration 0       →  a wide, forgiving market
solid turned edge on   →  concentration 80,000  →  a tight market that holds its price
```

Spinning the section (`xy`, `xz`, `yz`) does nothing to the market, exactly as it does
nothing to the shape. Only the three planes that reach into `w` matter, to the picture
and to the price alike.

This is safe because it is still constant product with a change of origin: the
invariant is a hyperbola for every rotation a holder can commit, so no shape anyone can
make will bend it into something that leaks. The one thing virtual reserves genuinely
break is the promise that the pool can pay — a curve pricing against liquidity it does
not hold will happily quote too much. That is not solved by cleverness. The pool
refuses: no single trade may take more than half the real reserve, and it says so.

**The curve is a copy, not a live read** — and that distinction is a bug the test suite
caught. A token can be rented out under ERC-4907, and a renter may operate the artwork.
With a live read, a renter could concentrate a curve holding *someone else's* inventory,
trade through it at the improved rate, and hand the token back. So the market keeps its
own copy of the section word, only the holder can update it with `syncCurve()`, and
`pendingCurve()` reports when the two have drifted apart.

Deliberately absent: no LP shares (one provider per market removes share accounting and
the first-depositor attack, at the honest cost of not aggregating deep liquidity), no
oracle or TWAP (a curve its owner can move has no business being read as a price feed),
no flash loans.

## The instrument

Twelve nodes on two counter-tilted shells. Six are open at mint — the ones that only
look. The six that move value stay sealed until a holder deliberately opens them.

| | | |
|---|---|---|
| **Self** | reads the token out of the contract that rendered the page | open at mint |
| **Rotate** | six plane dials; three of them change the section's shape | open at mint |
| **Section** | choose the solid, the cut along `w`, and the hue | open at mint |
| **Scan** | block, fees, balances, bytecode, arbitrary storage slots | open at mint |
| **Vault** | the ERC-6551 account, derived by CREATE2 rather than asked for | open at mint |
| **Nest** | the token, inside the token, one section deeper | open at mint |
| **Send** | native value, from your wallet or from the token's own account | sealed |
| **Assets** | ERC-20 reads and transfers | sealed |
| **Call** | any signature, any contract, encoded in the frame | sealed |
| **Sign** | `personal_sign` and EIP-712, with the digest computed locally | sealed |
| **Issue** | the token mints its siblings | sealed |
| **Market** | this token's own exchange: quote, trade, add or take inventory | sealed |

Drag to orbit. The slider under the field moves your 3-space along `w`. The six chips
are dials — drag one to turn in that plane, click to set it spinning, double-click to
reset. `xw`, `yw` and `zw` are drawn dashed because those are the ones that reach
out of the space you are standing in. Press `/` for every command in one list.

**Nothing is signed without showing the bytes first.** Every transaction is
rebuilt from its signature, split into 32-byte words with each argument decoded
beside it, priced with `eth_estimateGas`, and put in front of you in a plain
sentence before the wallet is ever asked.

---

## Standards

Recomputed from the function selectors rather than copied. `tools/selftest.mjs`
derives them with the engine's own keccak; `test/Ipseity.t.sol` asserts the contract
answers to each.

| | ID | Why |
|---|---|---|
| ERC-165 | `0x01ffc9a7` | everything else is discovered through it |
| ERC-721 + Metadata | `0x80ac58cd` `0x5b5e139f` | the thing itself |
| ERC-721Enumerable | `0x780e9d63` | bounded supply, so the per-transfer index cost is affordable |
| ERC-2981 | `0x2a55205a` | royalties, 5%, capped at 10% forever in code |
| ERC-4906 | `0x49064906` | fired on every commit, or a dynamic token looks frozen to every indexer |
| ERC-4907 | `0xad092b5c` | the borrower may **operate** the instrument but not sell it |
| ERC-5192 | `0xb45a3c0e` | a holder may bind the token to themselves, and unbind it |
| ERC-6454 | `0x91a6262f` | the same flag `locked()` reports — one source of truth, never two |
| ERC-7160 | `0x06e1bc5b` | the instrument, the sigil, the quartet; the holder pins one |
| ERC-7496 | `0xaf332f3e` | traits readable without parsing a 60 KB data URI |
| ERC-7572 | `0xe8a3d485` | collection metadata, also fully on chain |
| ERC-173 | `0x7f5828d0` | how a marketplace decides who may edit the collection page |
| ERC-6551 | consumed, not implemented | the bound account, derived by CREATE2 |

**ERC-4906's identifier is a magic number.** Its interface is events only, so
`type(IERC4906).interfaceId` is `0x00000000`; the EIP fixes it by fiat at
`0x49064906`, which spells the EIP number twice. Contracts in the wild register the
zero. This one hardcodes the right value.

**ERC-7572 does not define an interface ID.** `0xe8a3d485` is simply
`bytes4(keccak256("contractURI()"))`. Registering it is harmless and nothing queries
it; it is not a spec-stated value and this document does not claim otherwise.

### Deliberately not claimed

**ERC-7857 (iNFT).** The mechanism is here — a token may carry a payload that is not
public, identified on chain only by its hash and sealed to a key its holder controls,
so that handing the token over is not enough and a transfer is only accepted
alongside a proof that the same payload was re-sealed to the recipient. What counts
as a proof is a swappable verifier's business, because a TEE attestation and a
zero-knowledge proof are both admissible and neither belongs hardcoded in a token.

It is **not** called ERC-7857, for three reasons. That specification's normative
entry points are `iTransfer` and `iClone(…, TransferValidityProof[])`, and these are
not those functions — a client written against the standard would not find them. It
defines no ERC-165 identifier, so there is nothing to register or detect. And its
premise is that the valuable metadata is encrypted and lives off chain behind an
executor the spec declines to specify, which is the exact inverse of a work whose
whole claim is that nothing is fetched. Shipping a false conformance claim in an
immutable contract is worse than shipping no kernel at all.

**ERC-7007 (AIGC-NFT).** Requires a model and a verifier that do not exist here.
There is no inference in this pipeline; the image is a deterministic function of a
256-bit word, and `verify()` would be a tautology.

Also considered and skipped: ERC-5484 (forbids metadata change, contradicts 4906 and
7496 simultaneously), ERC-721C (a mutable pointer to off-contract transfer policy is
the antithesis of a permanent artifact), ERC-5643, ERC-5773, the deactivated OpenSea
Operator Filter Registry.

---

## The numbers

Measured, not estimated — every figure below comes from `node tools/verify.mjs`,
which deploys the whole collection into an EVM at Cancun and reads it back.

```
document, as written                137,500 bytes
after minifying                      90,520 bytes    65.8%
stored on chain (gzip)               32,439 bytes    23.6%      3 shards

deployment (4 contracts)              12.16M gas
loading the document                   7.32M gas
                                     ─────────
total to launch                       19.49M gas

mint                                   0.19M gas
commit a new orientation               0.05M gas
tokenURI() read                       20.68M gas    (geth caps eth_call at 50M)
tokenURI() response                      61 KB
```

Storing the document as plain text instead costs **20.09M gas** to load and makes the
`tokenURI` read **30.7M**. Both modes are implemented and both are verified; packed
is the default because it is what makes the document deployable without fighting the
per-transaction gas cap.

Deployed bytecode, against the 24,576-byte EIP-170 ceiling:

```
Renderer   20,026 B   81%
Ipseity    15,974 B   65%
Sigil      14,129 B   57%
Engine      2,724 B   11%
```

---

## Building it

```bash
npm install

node tools/selftest.mjs         # the engine's own keccak, ABI coder, EIP-712, CREATE2
node tools/build-engine.mjs     # minify, gzip, shard  → dist/shards.json
node tools/verify.mjs           # deploy on a real EVM and read it all back
node tools/preview.mjs          # dist/preview.html — open it in a browser
```

`selftest.mjs` lifts the chain half of the engine straight out of
`engine/ipseity.html` — the same bytes that go on chain, not a copy — and holds it
against published vectors: keccak-256, nine function selectors the whole chain
agrees on, the EIP-55 checksum cases, ABI encoding and decoding, and the full
**EIP-712 `Mail` vector from the EIP itself**, domain separator through final digest.

`verify.mjs` is the one that matters. It loads the shards, freezes the engine, mints,
pulls `tokenURI()` back, and walks it: base64 → JSON → base64 → gzip → the document.
The document that comes back must be **byte for byte** the document that went in, and
the state written into the gap must be the state the contract actually holds. Then it
commits a new orientation and checks that everything downstream moved and the engine
itself did not.

That check found a real bug. The SSTORE2 init code carried the wrong `CODECOPY`
source offset — `PUSH1 10` where the prologue is 12 bytes long — so every shard came
back with two bytes of init code glued to its front and two bytes missing from its
end. It deploys. It reads. It silently corrupts the document. The same error is
present in the reference implementation this was built from.

### Deploying

```bash
node tools/build-engine.mjs
node tools/verify.mjs                    # do not skip this
forge script script/Deploy.s.sol --rpc-url <chain> --broadcast

# check engine.headBytes()/bodyBytes() against dist/ipseity.min.html, then:
ENGINE=0x… IPSEITY=0x… forge script script/Seal.s.sol --rpc-url <chain> --broadcast
```

`freeze()` and `sealRenderer()` are both one-way. After them the document and the
renderer are permanent, and nobody — including the curator — can alter what the
collection looks like.

Before broadcasting to a live chain, **re-verify the ERC-6551 registry and account
implementation addresses on that chain**. They are baked into an immutable contract,
and passing the wrong implementation yields a different, valid-looking, entirely
broken account address.

---

## Layout

```
engine/ipseity.html     the artwork: one file, no dependencies, 137 KB
src/
  Ipseity.sol           the token — state, standards, the causal loop
  Engine.sol            the document, held as contract bytecode
  Renderer.sol          tokenURI, the three faces, the JSON
  Sigil.sol             the 4D projector, in Solidity
  Pool.sol              every token as its own exchange
  lib/                  SSTORE2, Base64, Trig, Curve, LibNum, the section word
  interfaces/           every standard, with the reasoning
tools/
  glsl-check.mjs        every shader parses and type-checks
  selftest.mjs          the engine's crypto against published vectors
  build-engine.mjs      minify → gzip → shards
  verify.mjs            deploy on a real EVM, read it all back
  verify-pool.mjs       try to break the market on a real EVM
  preview.mjs           dist/preview.html
  evm.mjs, compile.mjs  the harness
test/                   Foundry unit, property and fuzz tests
script/Deploy.s.sol     deploy, load, seal
```

---

## What was and was not run here

`glsl-check.mjs`, `selftest.mjs` (52 assertions), `build-engine.mjs`, `verify.mjs` in
both storage modes (122 packed / 121 raw) and `verify-pool.mjs` (35 assertions) were
executed in this environment, and every number in this document comes from those runs.

`forge test` was **not** executed: Foundry's installer host is blocked by this
session's network egress policy. The Foundry suite and the deploy script were
type-checked against the compiler with a `forge-std` stub, so they compile, but they
have not been run. Run them before deploying anywhere real.

**Nothing here has been audited, and `Pool.sol` holds other people's money.** That is
a different risk class to the rest of the repo: the worst bug in the artwork renders a
picture wrong, the worst bug in the market takes funds, permanently, with no undo. It
ships with a per-market deposit cap for exactly that reason — raise it only after a
review. The artwork also has a wallet client inside it that can sign arbitrary
calldata; that is the point of the Call node and the other thing an auditor would want
to look at first.

---

## Tradeoffs worth knowing

**Inside a marketplace frame, nothing can be signed.** The `animation_url` is
sandboxed without `allow-same-origin`, so the origin is opaque, no extension injects
a provider, and no wallet ever announces itself under EIP-6963. The engine detects
this — storage throwing is the cheapest reliable signal — and says so plainly rather
than offering a Connect button that cannot work. The field still turns, because the
field never needed a network.

**ERC-721Enumerable costs real gas on every transfer.** It is implemented because
supply is capped at 4096 and other contracts do read it. On an unbounded collection
it would be the wrong call.

**`tokenURI()` reads at 20.68M gas.** Comfortably inside go-ethereum's 50M `eth_call`
cap and the 30M engineering target, but not free. `tokenURIAt(id, index)` exists so
a client that wants one face does not pull all three.

**ERC-5192 and ERC-6454 both being registered is a known smell** — two ways of asking
whether a token can move. They are wired to one flag here, and `isTransferable()` is
written in terms of `locked()`, so they cannot diverge; but a strict reading would
pick one.

---

*Held entirely in chain state. The section is where you stand; the solid is what you are.*
