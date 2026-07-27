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
fetched. This is not a micro-optimisation: it is the difference between **8.4M and
23.6M gas** to put the document on chain, and between a 70 KB and a 193 KB
`tokenURI` response.

**It opens itself, inside itself.** The Nest instrument calls `tokenURI()` on chain,
decodes the base64, raises a depth counter, and mounts the result in a frame
positioned in the same 3-space as the solid. The instance inside can do it again.

**It checks the contract rather than believing it.** Both of a token's ERC-6551
addresses are re-derived inside the frame — registry, implementation, chain, contract,
token id, through the page's own keccak and CREATE2 — and then compared against what
the contract reported. They have never disagreed. The point of asking is that a viewer
which only renders what it is handed cannot tell a correct answer from a convenient
one.

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

**The offsets are anchored, and a trade never moves them.** This is the subtle part,
and it was got wrong first. The virtual reserves used to be derived from the live
reserves on every quote — which sounds equivalent and is not. Offsets proportional to
live reserves re-anchor the curve after every trade, so `k` is conserved *within* a
trade and not *across* two, and buying then selling straight back extracts the
difference: at eight-times concentration and a trade worth a third of the reserve,
**400 units in came back as 718**. They are stored on the market now, written only by
`openMarket`, `deposit`, `withdraw` and `syncCurve`, and read by `swap`. Every write
emits `CurveAnchored`, so the one thing a trade must never do is visible in the log if
it ever happens.

That bug survived two test suites, because both recomputed `k` the same wrong way and
the 200-trade walk caps every trade at 2.5% of the reserve, where the fee hides it. It
was found the first time the stated properties were actually run against random inputs
— see `tools/fuzz.mjs`, which exists for that reason.

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

## Security

Approached the way the Dave Held core approaches it: write down what must be
true, then attack it. [INVARIANTS.md](INVARIANTS.md) lists sixty-six such
statements and names the test for each, plus twelve known limitations that are
documented rather than defended.

Writing an invariant down is not the same as running it. Nine of these were
stated as Foundry `testFuzz_` properties and had never been executed, because
Foundry cannot be installed in this environment. `tools/fuzz.mjs` runs them
here instead, against the real contracts on a real EVM with a seeded generator
and a shrinker — and the first serious run found a leak in the pricing that
both existing suites had passed over. The details are under *The market* above,
and the fix is in `Curve.anchor`.

**A seven-day timelock.** `src/lib/Timelock.sol` is meant to own every
privileged path. Not because a delay makes a bad change good, but because it
makes one *visible* before it lands. The threat model is a stolen key, not a
dishonest curator: without a delay a compromise is an instant loss discovered
afterwards, and with one it is a queued transaction sitting in public for a week
with its full calldata in an event. Adapted with three changes — the admin can
rotate but only through its own queue, queued operations expire after a
fortnight so a forgotten proposal is not a live weapon, and an eta cannot be
re-queued out from under a watcher.

**Privilege never moves in one step.** Both the collection's curator and the
market's admin hand over by propose-and-accept. A one-step transfer to a
mistyped address is how a collection loses its admin permanently; this deviates
from a literal reading of ERC-173 and says so.

**The vault seals too.** ERC-6551 makes the registry canonical and the
*implementation* a parameter. Most collections pass the reference
implementation and inherit its one structural gap: the holder can empty the
vault between agreeing a price for the token and settling it. This one passes
`src/IpseityAccount.sol` instead, which carries the same ratcheting promise the
market does.

How "nothing leaves" is enforced matters more than that it is. Not by listing
the calls that move assets — that list cannot be completed, because `transfer`
is on it but so is any protocol's `withdrawTo`, `redeem`, `exit`, or a function
nobody has written yet. The account **measures**: it records its balance of
every manifest asset before a sealed call and checks that none fell after. What
the call did is irrelevant; what is left is not. The suite proves this with a
drainer whose function name was invented for the test and appears on no list
anywhere.

Measurement has exactly one blind spot, and it is covered separately: an
approval moves nothing at the moment it is granted, so the loss lands in a later
block where no same-transaction check can see it. So while sealed, approvals,
ether transfers and ERC-1271 signatures are refused outright — those being the
three authorities whose effect escapes the measurement window.

A sealed vault can still act. Anything that leaves it no poorer goes through,
because a vault that cannot act is a safe.

**The other hand.** Look at what the seal cost: a manifest, a snapshot, a
verification pass, an approval blocklist, a delegatecall ban, an ERC-1271
refusal, and a documented blind spot for assets nobody thought to list. Every
one of those exists because the capability to spend exists and is being
policed.

So every token has a **second** ERC-6551 account, at a second salt, running
`src/GripVault.sol`. It receives and it does not spend. There is no `execute`,
no withdraw, no sweep, no rescue, no owner override, no admin — read the ABI:
there is no function on that contract that moves an asset out of it, for
anybody, ever. Nothing is policed because nothing is possible, and the test
for it is an assertion against the compiled ABI rather than a list of attacks
that bounced.

Two hands, on purpose. The **Reach** is working capital: it acts, and it is
guarded. The **Grip** is what a buyer prices the token on: `holdings()` there
is a floor rather than a snapshot, because the seller has no function with
which to move either number between a handshake and a settlement. Market
inventory is a third case again — it has to stay liquid, so it lives in
`Pool.sol` behind a time-boxed bond. Three places, three different promises.
The shape is the Gate from the CONGREGATION meld design: *Grip → Reach:
never. No function exists.*

The cost is stated in `INVARIANTS.md` rather than buried: a Grip is permanent,
there is no burn, and a mistaken transfer into one is a permanent mistake.

**The voice, and the wall that survives it.** A sealed vault used to return
zero to every signature. Safe, and wrong: an account that cannot sign anything
for a year cannot prove to a counterparty that it is the thing holding what it
holds, which is half of what this collection claims a token is.

The fix is domain separation rather than omission — the best idea in the DAVE
V2 audit, and it applies here exactly. Unsealed, the account validates any
digest its holder signed. **Sealed, it validates only digests it can rebuild
itself**, under its own EIP-712 domain (`IPSEITY_ATTESTATION`,
`verifyingContract` = the account), with the caller obliged to hand over the
preimage so the account reconstructs rather than trusts. Every venue hashes its
orders under its own domain separator, so an order hash can never be the output
of `attestationDigest`. A sealed vault is not *forbidden* from signing its
assets away — it is *incapable* of it. There is no allowlist to maintain and
none to get wrong.

**Session keys, for something that is not you.** A holder can grant a bounded
key to a bot, a keeper or a model without handing over the token. Four bounds,
all checked on every call: an expiry it cannot extend, a target allowlist and a
selector allowlist it cannot widen, and a cumulative spend cap it cannot raise.
Revocation is one transaction, immediate and unilateral.

Three escalations are refused by *shape* rather than by budget, because bounds
are only worth what the first move cannot undo. A session cannot call the
account (otherwise its first act is granting itself a session with no limits).
A session cannot approve a spender that is not itself on the target allowlist —
`approve` is called *on* the token contract, so allowlisting the callee says
nothing about who is being trusted, and the argument has to be checked. And a
session cannot touch the Grip, which nothing enforces because there is nothing
to enforce. The seal composes on top: a session is never more trusted than the
person who granted it. See [AGENT.md](AGENT.md).

**The bond.** "Selling the token sells the market" is mechanically true the
moment `ownerOf` changes and worth nothing to a buyer on its own — the seller
can empty it between the handshake and the settlement. So a holder may bond a
market: a date before which nothing leaves and no term changes. It ratchets, it
survives the sale, and while it holds there is no withdrawal, no closure, no fee
change and no curve re-shape. Deposits and trades still work, because those are
additive. Taken from the Dave Held stall bond, whose invariant reads
*"bondUntil never decreases, and no exit path exists while it holds"*.

**No admin path can move an asset.** The market's five admin entry points are
`setPaused`, `bless`, `setAllowlistEnforced`, `proposeAdmin` and `acceptAdmin`.
Not one takes a token id or an amount, so not one can name a thing to move —
asserted against the compiled ABI rather than by reading the source. The worst a
stolen admin key achieves is a market that will not trade.

**The pause never traps money.** It halts trading and deposits. `withdraw` has
no pause modifier and is reachable in every state, because a pause that traps
money is a slower theft.

**Markets open only on blessed tokens**, while enforcement is on. A market is a
promise to strangers, and a token contract that lies about its own balances
breaks every guarantee above it. This is the Dave Held Granary pattern — *"silos
are timelock-blessed only"* — and it is a real centralisation trade-off, stated
rather than hidden.

### Read against the DAVE V2 audit

A v2 audit of a different collection — a covenant NFT with a 6551 vault, a
conviction pool and an on-chain website — was reviewed against this one. Its
findings are good, and the useful thing was that most of them **did not
transfer**, for reasons worth stating.

**C1, a single bag bricks the exit — applies inverted, and that was the find.**
Dave's ragequit hard-requires a transfer from every listed token, so one token
that reverts freezes the only exit from a four-year seal, and a stranger can
put that token on the list for dust. Here `guard` is holder-only, so nobody can
aim it, and `_balance` already used a staticcall so nothing bricks.

But the staticcall returned zero on failure, and the comment beside it claimed
that "can only ever tighten the check". **That was wrong.** A token that stops
answering reads as zero *before and after* a call, so `now < pre` is false and
the seal quietly stops promising anything about it — no revert, no event, no
signal to a buyer. Same root cause as Dave's brick — a measurement that does
not distinguish *answered zero* from *did not answer* — and the opposite
failure. Now the two are separate, `unmeasurable()` names every asset that has
fallen out of the promise, and an asset readable before a call and not after
reverts rather than shrugs.

**C2, a stranger fills the roster — does not apply, but half of it did.**
`guard` is `onlySigner`, so the attack is not available. The append-only part
was still a real cost: sixteen slots, no removal, and the manifest travels with
the token. `unguard` now exists, and reverts for everyone while sealed.

**C3, 1155 batch receiver missing — does not apply.** Both accounts already
implement `onERC1155BatchReceived`, and both `supportsInterface` answers are
already complete. The Grip's omission of `0x51945447` is deliberate and
documented.

**M1, no reentrancy guard — did not apply, added anyway.** Ownership already
stops the re-entry: a token called from inside `_act` that calls back arrives
as itself, not as the holder. But the thing being protected is a snapshot taken
around an external call, and this contract can never be redeployed — its
address is an input to every vault's address. On code that is final, cheap
insurance against a class of bug beats the gas.

**M2, ERC-1271 by domain separation — applies fully, and is the best idea in
the document.** This vault returned zero to every signature while sealed, which
is exactly the omission the audit criticises. See *the voice* above.

**C4, the website is one DNS record — does not apply, and could not.** There is
no hostname in this bytecode, no `fetch`, and no `new Function` over remote
bytes. One sub-point does land: the audit is right that serial on-chain
assembly grows quadratically and eventually exceeds the `eth_call` cap. This
collection's `tokenURI` read is **23.99M gas against a 30M ceiling** and it has
grown this cycle. That margin is measured on every run and it is the number to
watch.

### What was deliberately not taken from it

**Serving the artwork over a wire** — the chunked file store, the SHA-256
integrity manifest, the multi-transport loader, the compression codec. All of
that solves shipping a large application over a network and proving it arrived
intact. The artwork here does not travel over a network: it is a self-contained
`data:` URI out of contract code. Adding an origin server to remove a hostname
is a step backwards, and the chunk-integrity design is elegant precisely
*because* bytes arrive over a wire. Nothing here does, so there is nothing to
verify.

**ERC-5018 and ERC-7087** — a filesystem interface and MIME negotiation for a
contract that serves three routes and one content type each. Standards earn
their bytes by being consumed.

**ERC-7066 lienholder locks.** ERC-5192 is already here and `locked()` is the
part marketplaces read. ERC-7066 adds a third-party locker for lending against
the token — a capability with no consumer in this collection. Shipping the
surface before the desk is how immutable contracts accumulate attack surface
that never earns its keep.

**ERC-4494 permit.** Considered and declined. The audit's justification is "a
sale should be one transaction", which is a property Dave's covenant claims and
this one does not. External marketplaces use `setApprovalForAll`, 4494 adoption
is thin, and it would add a signature-verification surface plus ~1.5 KB to a
contract that can never be redeployed. If a desk here ever needs it, it needs
it for a stated reason.

**`setTrait` reverting unconditionally.** Right for Dave, wrong here. Its
traits are pure functions of covenant state, so a settable one could be false.
This collection's only settable trait is `hue`, which is genuinely holder
state — part of the section word the artwork exists to let you edit. Reverting
would remove a real function to make a point that does not apply.

**ERC-2309, ERC-721A, the royalty splitter doctrine.** No batch mint, a
different base, and no 69/31 split to obey.

## The front door

Every token is already a website — `tokenURI` hands back a WebGL2 engine, a
keccak, an ABI coder and a wallet client, out of contract code, fetching
nothing. What was missing was somewhere to send a person who does not own one
yet.

`src/Premises.sol` is an **ERC-5219** contract: `request(resource, params)`
returns a status code, a body and headers. An **ERC-4804 / ERC-6860** client
reaches it with no DNS and no server —

```
web3://<premises>/               the index
web3://<premises>/token/42       one token
web3://<premises>/token/42/raw   that token's tokenURI, plain
web3://<premises>/token/42/live  the instrument, on its own origin
```

— and an ENS `contenthash` makes that a name. An HTTP gateway is a convenience
for everyone else, and a convenience is exactly what it should be.

**The constraint is the design.** Premises never serves the artwork. It serves
a document that *names* it, emitting the token's own `data:` URI read from the
hub at request time. The suite asserts that byte for byte: what the page hands
a viewer equals `tokenURI(id)` exactly, and the contract's deployed code
contains none of the document.

Be exact about what that buys. Premises composes the page, so a compromised
Premises could put anything in that frame — no assertion prevents that. What it
buys is that **the artwork is untouched**: the bytes are in the collection,
anyone can call `tokenURI` directly, `/raw` hands back the URI to check against,
and every token renders identically whether this contract exists, is abandoned,
or is replaced. The index is convenience, and nothing depends on it. That is the
difference between a front door and infrastructure, and it is why this one is
safe to have where a hostname in immutable bytecode is not.

**`/live` is the route that makes it usable.** A `data:` document gets an opaque
origin and wallet extensions do not inject into one — so the instrument in the
frame renders perfectly and cannot connect to anything. It can be looked at, not
used. `/token/42/live` serves `Renderer.document(...)`, the same bytes one step
before base64, as a first-class HTML response on a real `web3://` origin, where
EIP-6963 discovery works and the twelve instruments do what they were built for.
The suite asserts those bytes equal what `tokenURI` base64s.

No state-changing function at all, and a request for nonsense is a 404 rather
than a revert.

---

### What was deliberately not taken from the Dave Held core

The Dave Held core is twenty-one DeFi desks. Porting them into an artwork would
be reckless, so the teardown asked of each mechanism: *what guarantee does this
serve, and does anything here make that promise?*

**The selector firewall** — refusing transfer-family selectors by shape while a
vault is sealed — was initially skipped on the grounds that IPSEITY's vault made
no promise, so the firewall would guard nothing. Adding the seal created the
promise, and the question came back. The answer, on a second look, is that the
firewall is *not* the mechanism: a selector list only blocks the words it knows,
and the drainer in `tools/verify-vault.mjs` walks straight past any such list.
Measurement is the mechanism. The firewall survives as a second layer covering
one specific case — approvals — because that is the case measurement is blind
to. Dave Held's Chambers has both for the same reason, and their hardening pass
(finding S1) is a record of learning it.

**The covenant seal, ragequit tax, tranches, rank engraving, Harberger keeper
seats, perps, RWA lots, options, bonds, strips, restaking, basket funds** —
skipped. Each is a product, not a safety property, and none of them is this one.

**The stall curve library** (FLAT / LINEAR / EXPO) is skipped for a specific
reason rather than a general one: this collection's curve comes from the
artwork, and a second, unrelated family of curves would either contradict that
or sit unused.

---

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
| **Market** | this token's own exchange: quote, trade, bond, add or take inventory | sealed |

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
| ERC-6551 | consumed, not implemented | two bound accounts per token, at two salts, derived by CREATE2 |

**ERC-4906's identifier is a magic number.** Its interface is events only, so
`type(IERC4906).interfaceId` is `0x00000000`; the EIP fixes it by fiat at
`0x49064906`, which spells the EIP number twice. Contracts in the wild register the
zero. This one hardcodes the right value.

**ERC-7572 does not define an interface ID.** `0xe8a3d485` is simply
`bytes4(keccak256("contractURI()"))`. Registering it is harmless and nothing queries
it; it is not a spec-stated value and this document does not claim otherwise.

### Deliberately not claimed

**ERC-7857 (iNFT).** The *mechanism* is built, in the token itself, and the
*conformance claim* is deliberately withheld. Both halves of that are on purpose.

Built, because once the collection grew session keys it grew a secret worth
protecting. Not what an agent may do — that is on chain, bounded and public, and has
to be, or nobody can price the token — but **how it decides**: the prompt, the
thresholds, the strategy. That is valuable, worthless once public, genuinely part of
what the token is, and useless to a buyer unless it is re-sealed to them. Which is
precisely and only what ERC-7857 is for. So a token may carry a payload named on
chain only by hash and sealed to a key its holder controls, and `transferWithKernel`
moves the token and the re-sealing together, gated on a proof checked against *this*
token's hashes.

The part worth building is the seam. `transferFrom` still exists — remove it and the
token stops being an ERC-721 — and an ordinary transfer moves the token while leaving
the payload encrypted to the seller. Nothing is violated; the buyer simply owns a
pointer to a ciphertext they cannot open, and no event says so. So `kernelStatus()`
compares the owner the kernel was sealed under against `ownerOf` at read time: an
ordinary transfer reads **STALE**, with no hook, no gas, and no cooperation from a
seller who would rather it went unmentioned. It surfaces in the ERC-7496 trait too.
`kernelStatus` and `kernelProved` are separate questions so a client cannot merge
"there is a kernel" with "somebody checked it".

Not claimed, for four reasons. The specification's normative entry points are
`iTransfer` and `iClone(…, TransferValidityProof[])`, and these are not those
functions — a client written against the standard would not find them. It defines no
ERC-165 identifier, so there is nothing to register or detect, and anything
advertising 7857 through `supportsInterface` is advertising something the standard
does not define. Its premise — that the valuable metadata is encrypted and lives off
chain — is the exact inverse of a work whose whole claim is that nothing is fetched,
so it is applied to the agent's disposition and never to the artwork. And the
re-seal proof requires a TEE attestation or a ZK circuit that this collection does
not ship: `verifier` is zero, `hasVerifier()` says so, `kernelProved()` is false for
every token, and `transferWithKernel` on a live kernel **reverts** rather than
waving it through. A stub would let a marketplace draw a green check nobody checked
— and it would be permanent, because `setVerifier` may be called once, from zero,
and never again. A rotatable verifier is not a verifier: whoever can swap it can
install one that approves anything.

The full design, and the answer to what an agent can and cannot be given here, is in
[AGENT.md](AGENT.md).

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
document, as written                173,261 bytes
after minifying                     113,379 bytes    65.4%
stored on chain (gzip)               39,501 bytes    22.8%      3 shards

deployment (6 contracts)              12.80M gas
loading the document                   8.86M gas
                                     ─────────
total to launch                       21.65M gas

mint                                   0.19M gas
commit a new orientation               0.05M gas
tokenURI() read                       25.14M gas    ← 4.86M under the ceiling
tokenURI() response                     ~74 KB
```

Storing the document as plain text instead costs **23.58M gas** to load and makes the
`tokenURI` read **36.31M**. Both modes are implemented and both are verified; packed
is the default because it is what makes the document deployable without fighting the
per-transaction gas cap — and because a 36M read is past what several public nodes
will serve.

**The `tokenURI` read is the budget that binds.** It is asserted under 30M on every
run, because that is where several public nodes cap `eth_call`. It has gone
23.99M → 25.14M this cycle as the instrument grew. Roughly 4.8M of headroom is
left, and every feature added to `engine/ipseity.html` spends some of it. When it
runs out the answer is not a bigger cap, it is a smaller document.

Deployed bytecode, against the 24,576-byte EIP-170 ceiling:

```
Renderer         20,731 B   84%
Ipseity          18,203 B   74%
Sigil            14,129 B   57%
Pool              8,465 B   34%
IpseityAccount    7,302 B   30%    the Reach
Engine            2,724 B   11%
GripVault         1,933 B    8%    the Grip
```

`GripVault` is the smallest contract in the collection and carries the strongest
promise in it. That is not a coincidence — it is the whole argument. Its guarantee
costs 1,933 bytes because the guarantee is a function that was never written, where
the Reach spends 7,302 policing a capability it has.

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
  Premises.sol          the front door: ERC-5219, holds none of the artwork
  IpseityAccount.sol    the Reach — the ERC-6551 vault, sealable and measured
  GripVault.sol         the Grip — the second account, which cannot spend
  lib/                  SSTORE2, Base64, Trig, Curve, Timelock, the section word
  interfaces/           every standard, with the reasoning
tools/
  glsl-check.mjs        every shader parses and type-checks
  selftest.mjs          the engine's crypto against published vectors
  build-engine.mjs      minify → gzip → shards
  verify.mjs            deploy on a real EVM, read it all back
  verify-pool.mjs       try to break the market on a real EVM
  verify-vault.mjs      try to drain a sealed vault, and to widen a session key
  verify-kernel.mjs     try to lie to a buyer about a sealed kernel
  verify-premises.mjs   prove the index cannot touch the artwork
  verify-timelock.mjs   try to escape the delay
  fuzz.mjs              the stated properties, under seeded random attack
  preview.mjs           dist/preview.html
  evm.mjs, compile.mjs  the harness
test/                   Foundry unit, property and fuzz tests
script/Deploy.s.sol     deploy, load, seal

INVARIANTS.md           fifty statements that must hold, and the test for each
AGENT.md                ERC-7857, session keys, and what an agent can be given
```

---

## What was and was not run here

`glsl-check.mjs`, `selftest.mjs` (55 assertions), `build-engine.mjs`, `verify.mjs` in
both storage modes (122 packed / 121 raw), `verify-pool.mjs` (62), `verify-vault.mjs`
(97), `verify-kernel.mjs` (36), `verify-premises.mjs` (29), `verify-timelock.mjs` (24)
and `fuzz.mjs` (14
properties) were executed in this environment — 425 assertions, 14 properties, 15 refuted claims and a 220-tick agent run —
and every number in this document comes from those runs.

`forge test` was **not** executed: Foundry's installer is unreachable from this
session, and so are GitHub, codeload and the crates.io API, so there is no route to it.
The Foundry suite and the deploy script were type-checked against the compiler with a
`forge-std` stub, so they compile, but they have not been run.

The nine `testFuzz_` properties they state **are** run, by `tools/fuzz.mjs`, against
the same contracts compiled by the same solc on the same EVM as everything else in
`tools/`. The generator is seeded and prints its seed, so a failure reproduces for
anyone rather than only for whoever hit it, and it shrinks a counterexample before
reporting it. That suite found the pricing bug described under *The market* on its
first serious run. What it does not do is stateful invariant campaigns, coverage-guided
corpora or cheatcodes — it is a smaller net, not a replacement. Run the Foundry suite
before deploying anywhere real.

**Nothing here has been audited, and `Pool.sol` holds other people's money.** That is
a different risk class to the rest of the repo: the worst bug in the artwork renders a
picture wrong, the worst bug in the market takes funds, permanently, with no undo. It
ships with a per-market deposit cap for exactly that reason — raise it only after a
review. The artwork also has a wallet client inside it that can sign arbitrary
calldata; that is the point of the Call node and the other thing an auditor would want
to look at first.

**The off-chain half of the agent story is not in this repository.** `AGENT.md`
specifies the MCP surface a model would drive the session key through, and that
service holds a private key and talks to a live RPC — so nothing about it can be
exercised by the harness here. Shipping untested key-handling code alongside tested
contracts would misrepresent which parts have been checked. The on-chain side —
the four bounds, the three structural refusals, the kernel — is built and
tested; the signer is specified and not written.

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
