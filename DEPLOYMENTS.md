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
