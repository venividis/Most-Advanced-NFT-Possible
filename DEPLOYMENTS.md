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
