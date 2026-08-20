# Deployments

## Base Sepolia · chain 84532

Deployed 2026-08-18 over `https://base-sepolia-rpc.publicnode.com` with signed
legacy transactions — 68.41M gas across ~40 transactions, every route then read
back through the public node's own `eth_call`, and the conversation walked
through its production `eth_getLogs` in single-block queries. The full run is
`node tools/testnet.mjs`; nothing was deployed by hand.

```
Ipseity      0x13ed99319101cbc2bc09e3849af5462dae283f5d
Premises     0x646b0b8a99657bbb6cc53ad7b8374ceae29a4824
Parley       0xe08ff7cf056b2a3a067fa1b00476f663b9bcbfcb
```

The other ten site contracts (Chrome, Desk, DeskTalk, the seven pages) are
immutable constructor arguments of Premises and readable off it; `dist/testnet.json`
records them all when the deploy tool runs.

```
web3://0x646b0b8a99657bbb6cc53ad7b8374ceae29a4824:84532/
web3://0x646b0b8a99657bbb6cc53ad7b8374ceae29a4824:84532/chat
web3://0x646b0b8a99657bbb6cc53ad7b8374ceae29a4824:84532/token/1/live
```

Any HTTP gateway is `node tools/gateway.mjs` pointed at the chain — GET /chat
is an eth_call, and turning the gateway off loses nothing.

What is on it so far: tokens #1–#3 minted; #1 embodied; three messages in the
commons, a group ("the surveyors"), a whisper between #1 and #2. The engine is
**frozen**; the renderer is **not yet sealed** and the curator is the deploy
key, so this deployment is a rehearsal, not a covenant — reseal ceremony and a
timelocked curator belong to a mainnet deploy.

Measured there, not assumed: `tokenURI(1)` — 101.2 KB — answers through this
public RPC's eth_call, so its call ceiling clears the 19.99M read. The
transaction-shaped ceiling of EIP-7825 still stands as documented in the
README: readers that cap calls at 2^24 get the instrument via
`/token/<id>/live` at 4.48M.

### The whole surface, exercised — 2026-08-18

`node tools/exercise.mjs` walked every function of the six contracts on this
deployment with four accounts (the curator and three fresh keys): **235
functions — 231 exercised on the live chain, 4 skipped with written reasons,
zero unaccounted — 159 assertions, 0 failed, 101 transactions.** Refusals were
proven through `eth_estimateGas`, which replays the revert without spending
anything; every read was pinned to the newest block a receipt had proven mined,
because a load-balanced public RPC will otherwise answer from a replica living
one block in the past.

The skips, in full: `tokenURIs()` (37M gas, past this RPC's call ceiling —
measured in-suite), `renounceOwnership` / `setRenderer` / `sealRenderer`
(irreversible or deployment-breaking on a live rehearsal — the seal ceremony
belongs to mainnet), and `cloneWithKernel`'s enc-path duplicate (exercised
raw). What the live chain taught that the suite could not: a session grant's
empty selector list permits nothing — bare value transfers need `bytes4(0)`
granted like anything else; `guardNFT` refuses a manifest promise about a
piece the hand does not hold; the verifier really is write-once, curator
included, across runs; and `status()` on a freshly-rented lease answers
"occupied," which is the correct answer to a question the test first asked
wrongly.

Selected transactions in `dist/exercise-log.json` (all 101 hashes there);
tokens #1–#24 exist, #20 is the fully-exercised one, #23 its kernel clone.

### The site, rebuilt — 2026-08-19

The pages were replaced (wallet picker; eight tabs: door · terminal · social ·
agora · market · coins · charts · json) by `tools/redeploy-site.mjs`, which
deploys new pages and a new Premises and **keeps the Parley** — every message
ever sent is a log that contract emitted, and a new Parley would not migrate a
conversation, it would end one. The collection, pool, lease and every token are
untouched: same addresses, same holders, same history.

```
Base Sepolia    Premises 0x023b9d8834902ad3bf35b690db6e654d26c26463   (live, all tabs 200)
                Parley   0xe08ff7cf056b2a3a067fa1b00476f663b9bcbfcb   (unchanged)
Eth Sepolia     pending — the redeploy ran the deployer dry one contract
                short; it resumes when the deployer is topped up
```

The old Base Sepolia Premises (`0x646b…4824`) still serves the old pages
forever — an immutable router cannot be un-deployed, only pointed away from.

### Governance withdrawn — 2026-08-19

The agora tab, its page and its contract are removed from the codebase before
Ethereum Sepolia ever deployed them; the terminal's propose/vote commands went
with them. The Base Sepolia site that briefly carried the tab is superseded by
the next redeploy. Rooms remain the place the tokens organise; a decision the
holders want to bind can always come back as a contract when there is
something for it to bind.

### Charts withdrawn, the swap card returns — 2026-08-19

`/charts` — the one tab that left the chain — is deleted outright, and `/swap`
comes back from this repository's history as a single `exactInputSingle` card
against the chain's own Uniswap v3: no pools page, no positions client, no
governance reader, no v4 wiring. The card checks the factory for a pool at
every fee tier for whatever address is pasted into it, so there is no token
list to be wrong about. One wiring table in `tools/site.mjs` carries the four
per-chain address sets (probed live against each chain's deployments on this
date; all four route through `SwapRouter02`, seven words, no deadline), and
the door grew an EIP-3326/3085 chain switcher. `npm run check` green
throughout; `verify-site` 324/0 with the card driven field-by-field on both
router calldata shapes.

```
Base Sepolia    Premises 0x9d012f98bf4fdf6937c892b71b882631547467b9   (live, all tabs 200)
                Venue    0x81605ab877cedbc497a9b45049a79a6bb121fd42   (factory/quoter/router = Base Sepolia's own Uniswap v3)
                Parley   0xe08ff7cf056b2a3a067fa1b00476f663b9bcbfcb   (kept — same conversation)
                Foundry  0xe32eeb14bd0ba789d1edd8ae1d9c184d9ececf76   (fresh — the redeploy resets the /coins ledger;
                                                                       coins poured before it live on as contracts,
                                                                       unlisted)
                https://0x9d012f98bf4fdf6937c892b71b882631547467b9.basesep.w3link.io/
Eth Sepolia     still pending the top-up; the same final shape (with Eth
                Sepolia's own v3 wiring) deploys the moment it lands
```

An earlier entry on this page recorded the Base Sepolia Parley as
`0x9599…07b1`; that address holds no code on Base Sepolia and never did — it
was a local-chain address copied into prose. The deployment records were
always right, and they are the ones the redeploys read.

### The launchpad and the vault — 2026-08-19

The coin pourer is withdrawn and three surfaces replace it, all live in the
same redeploy: `/launch` (a v4 launchpad — fixed-supply no-owner token
signed by a collection token, hook address mined by the visitor's own node
under `eth_call`, pool initialized with six flat words at the chain's real
PoolManager, sliders for supply, fee, spacing, and a liquidity lock that
runs to ten years), `/hook/<address>` (a hook's powers read off its address
alone, canonicalized with 301s), and `/lock` (the vault: any ERC-20, a
ten-year bar, extend-only, no owner, no rescue path). The whole pipeline
was green before the deploy — `verify-site` 392/0 with the launch driven
field-by-field into a recording PoolManager and the vault through all five
refusals by error selector.

```
Base Sepolia    Premises 0xb0e9e0d5a80b92a812ca682fa7e908a365a70db1   (live, 13 routes, all 200)
                Kiln     0x353511322c9f4f17e2d37df4e32348509f594d03   (v4 PoolManager 0x05E7…3408, live-probed)
                Locker   0x8886088382d933b05a18d45efa04339cf40f2632
                Venue    (Base Sepolia's own Uniswap v3, routerKind 1)
                Parley   0xe08ff7cf056b2a3a067fa1b00476f663b9bcbfcb   (kept — same conversation)
                https://0xb0e9e0d5a80b92a812ca682fa7e908a365a70db1.basesep.w3link.io/
Eth Sepolia     still pending the top-up (~0.06 ETH to the deployer);
                the watcher deploys this same shape the moment it lands
```

The redeploy probe loop also learned that a load-balanced RPC's replica
answering `0x` for a fresh contract is lag, not absence — probes now retry
before they believe a failure. Two prior Premises on this chain
(`0x023b…6463`, `0x9d01…67b9`) still serve their older pages forever; an
immutable router cannot be un-deployed, only pointed away from.

### The Tesseract harvest — 2026-08-19

Three upgrades mined from `venividis/Launchpad-nft` (branch
`claude/defi-nft-multidimensional-39jijn`, the "Tesseract" build), each
rebuilt to this collection's rules rather than copied, all live in one
redeploy. The vault's locks became transferable positions (`give`, most
usefully into a token's own 6551 account so a locked treasury travels with
the token) with an EIP-2612 fast path that fails soft. The **Nameplate**
is an adminless ENS resolver: bind a name to a token, claim a wildcard
parent once, and the name answers with the token's account, its sigil as
avatar, and ERC-6821's `contentcontract` — the record that resolves a
name straight into this site over web3://, which the Tesseract's own
resolver never carried. And the DMs **seal**: signature-derived P-256
keys published through Parley's own `announce`, static-static ECDH,
AES-GCM, all WebCrypto — the client half of a promise Parley's envelope
made on the day it was written. Suite: verify-site 422/0, full pipeline
green. Diagnosing the drive for it also taught the test shim's provider
to serialize requests, after two overlapping page chains deadlocked the
in-process EVM — a real node's front door absorbs that race.

```
Base Sepolia    Premises  0x257496d2270e45c36fb232fed3b5f0a87cce3dca   (live, all routes 200 by RPC)
                Nameplate 0x551fa98b7f08e06b794c334aaacbbd3c39a0c506   (no ENS registry on this chain:
                                                                        binding refuses honestly; the
                                                                        contract is here so the address
                                                                        matches the chains where it works)
                Locker    0x5101c6edf5cde1215f9f9afd09ce857e5cbcbdc3   (give + lockWithPermit)
                Kiln      0x4b1b7992e626aac88731d98dc3d0e5c779951245
                DeskSeal  0x5d88564a78361607ffed9375e9a49800b1577bc1
                Parley    0xe08ff7cf056b2a3a067fa1b00476f663b9bcbfcb   (kept — and its announce/keyOf
                                                                        now have their client)
                https://0x257496d2270e45c36fb232fed3b5f0a87cce3dca.basesep.w3link.io/
                (w3link's basesep backend is mid-outage as this is written — the
                 previous premises 400s identically; the chain itself serves 200s
                 and the URL comes alive when their backend does)
Eth Sepolia     still pending the top-up; deploys this shape when it lands
```

Deliberately not taken from the Tesseract, with reasons: the
MetaForwarder (a relayer is a server, and this site's whole claim is that
there is none); the DAO (governance was withdrawn here on purpose); the
bridge intents (moving value between chains is a bridge's job, stated on
the door); the bonding-curve launch protections (anti-snipe and
max-wallet need to see the buyer, and on a real Uniswap router the buyer
is hidden behind the router — the Tesseract could offer them only because
it owned its own toy AMM); and the iNFT memory slot (this collection's
sealed kernel already is that idea). One thing it taught that cannot be
fixed on a deployed testnet hub: `transferFrom(holder, account(id), id)`
would hand a token to its own 6551 account and freeze it — the Tesseract
guards this; the mainnet hub should refuse `to == account(id)` at the
ceremony.

### The instrument becomes the entrance — 2026-08-19

Two deploys, one turn of the design inside-out. The **engine was rebuilt
and the hub re-pointed** — possible precisely because the renderer is not
yet sealed, which is what testnets are for. Every token's instrument now
carries a third orbit: eight door-vertices (terminal · swap · launch ·
lock · social · gallery · archive · site) that open the 2-D surfaces, and
a terminal veil drawn over the field itself, so the NFT is the first
interface and the site is what its doors open. The ring forms only where
an origin can answer — over web3:// or any gateway — and never inside a
marketplace's data: sandbox, where a door would be a painting of one. The
doors ride outside the shader's twelve node uniforms, so the instrument's
own sealed geometry is untouched.

And the **2-D site was reborn to deserve it**: void and gold, serif
ceremony, a slowly turning 4-polytope on the door whose eight inner
vertices are the same eight doors, the terminal speaking from the door
with a `go` that walks by word, and every explanatory paragraph folded
behind a small star — hover reads, click pins, warnings never fold,
scripts-off shows every word.

```
Base Sepolia    Premises  0x6e5315360522af0203af7a0f84aac8202c1e8ec7   (the divine site, all routes 200)
                Engine    0x5f3cc653b86e2d09fde3bd475420f57026ab0398   (frozen; 3 shards, 40,318 B packed)
                Renderer  0xb41f012b2a6f145099972be7032189343bc7e0f9   (the hub looks here now)
                Parley    0xe08ff7cf056b2a3a067fa1b00476f663b9bcbfcb   (kept, as ever)
                https://0x6e5315360522af0203af7a0f84aac8202c1e8ec7.basesep.w3link.io/
                …/token/<id>/live — any token's instrument, doors and all
Eth Sepolia     the watcher now deploys site + engine together when funded;
                the honest ask rose to ~0.08 ETH to cover both
```

### Four more doors, and two things found by opening them — 2026-08-20

`/projector` hands the 4-D renderer to anyone: the contract that draws every
token's still is `public pure`, so the page is eight solids on chips, every
number of the section word on its own bar, and a picture redrawn by the
caller's own node. Nothing on it can spend anything. `/seal` reads the three
seals a token can carry and works the two that belong to the holder.
`/keys` grants scoped, expiring session keys on a token's Reach and then asks
the account, selector by selector, what it believes it permits. `/name` binds
an ENS name to a token, building DNS wire format with string arithmetic
because this client carries no keccak — and the drive proves that encoding by
making the contract that *does* hash agree about which node it meant.

Writing the pages found two defects in the contracts they describe, both
measured before they were fixed and both now run as attacks on every check:

  · **The soulbind did not survive a stolen approval.** `onlyHolder` admits
    an approved operator, so a thief holding a phished approval could call
    `unlock` on a bolted token and take it — which is exactly the attack the
    bolt claims to answer. `lock` and `unlock` now admit the owner and the
    token's own account and nobody else.
  · **A token handed to its own hand froze forever.** Transferred to its own
    Reach or Grip, nothing could ever move it again: the account asks who
    holds the token, and the holder would be the account. Both are refused,
    computed rather than looked up so an undeployed account is covered too.

Neither fix can reach the hubs already deployed on the testnets — a collection
is immutable, which is the point — so Base Sepolia's live hub predates both
and the source is what mainnet will carry. That is what a rehearsal is for.

```
Base Sepolia    Premises 0x34a0e6eceef860a6b5c70d092e124904ca797d70   (eleven routes, all 200)
                Parley   0xe08ff7cf056b2a3a067fa1b00476f663b9bcbfcb   (kept, as ever)
                https://0x34a0e6eceef860a6b5c70d092e124904ca797d70.basesep.w3link.io/
                  …/projector  …/seal  …/keys  …/name
                (the hub, engine and renderer are unchanged from the entries
                 above; only the site was redeployed)
Eth Sepolia     still pending the top-up; the watcher ships site and engine
                together when it lands
```

The three page contracts were written in parallel by three agents against a
shared house-style brief, then integrated by hand. Two integration details
worth recording because they will recur: seventeen flat constructor arguments
put `Premises` past what even viaIR keeps on the stack, so the pages are now
passed as one named struct — identical calldata, one memory pointer; and the
name page needs the resolver's address while the resolver needs the premises
which needs the name page, so the resolver's address is computed from the
deployer and the nonce it will hold, and asserted the moment it exists.

### The token is the front page — 2026-08-20

Clicking a link to this NFT used to land you on a page *about* the NFT, with
the artwork one link further in. That was backwards, and it is now the other
way round: `/` serves the live instrument, and the flat pages — still the
right shape for anything a form does better than an orbit — sit behind its
doors and at `/door`. Before the first mint there is no token to render and
the flat page answers instead.

Three things were wrong with reaching the 2-D site *from* the instrument, and
all three only appeared on a phone:

  · the command list opened with `/` and a phone has no `/` key, so on touch
    there was no way to open it at all — the rail carries a button now;
  · the door nodes orbit at the widest radius, and the field is projected
    against the taller side of the screen, so in portrait they spent most of
    their time off both edges — door labels are pinned inside the viewport
    now, with the wire still running to where the node actually is;
  · and the rail's chain cell was `flex:1` behind an id selector, so it took
    every spare point and pushed the buttons past the right edge. Measured,
    not guessed: at a 500-point viewport the cell was 237 points wide and the
    buttons began at 418. It takes what it needs now.

The palette also learned the verb a person would actually type: `launch 2D`,
and `launch 2D swap`, `lock`, `social`, `gallery`, `terminal` beside it.

```
Base Sepolia    Premises 0x3045c6db8cc685b9312f7209f2ee36b04ed0648a   (/ is the instrument; /door the flat page)
                Engine   0x7db52df6a2f5e02fe6dc22918ec1770aa629dc60   (frozen; 4 shards, 40,771 B packed)
                Renderer 0xfa5c47d8201ae204f261d2b78e6357e2dd7a0ed4
                https://0x3045c6db8cc685b9312f7209f2ee36b04ed0648a.basesep.w3link.io/
```
