# probe/ — measurements, not machinery

Nothing in this directory ships, and nothing in it runs in `npm run check`.

These are the instruments used to answer a question the owner asked on
2026-08-22: whether a token that is a server and can hold other tokens
could run a music player, a game emulator, a cross-chain market, a render
market, or a holder's own shop. Every one of those questions has a number
attached to it, and a number nobody measured is an opinion.

So they were measured, on a real EVM, rather than recalled:

| tool | what it measures |
|---|---|
| `tools/probe-render.mjs` | what it costs the EVM to draw one pixel |
| `tools/probe-render-native.mjs` | the same field on a CPU, counted exactly, as the control |
| `tools/probe-emulator.mjs` | whether an emulator can run on each path the token has |
| `tools/emulator-envelope.mjs` | what an emulator costs to hold and to serve |
| `tools/probe-bridges.mjs` | what a settle message costs on each transport, priced today |
| `tools/probe-uln.mjs` | who actually secures a default LayerZero lane |
| `tools/probe-lz.mjs` | what LayerZero is on a given chain, read off it |
| `tools/probe-port-abi.mjs` | whether ParleyPort speaks the protocol's ABI or the mock's |
| `tools/probe-economy.mjs` | real gas for the settlement layer in `Bourse.sol` |

`Bourse.sol`, `Parts.sol` and `Stall.sol` are prototypes those probes
deploy. They are sketches with real gas costs, not proposals — read them
as the arithmetic behind a recommendation and not as code anybody
intends to ship.

## How they got here, which is worth writing down

They were written by research agents during that investigation and swept
into two commits by a `git add -A` whose messages describe only the
console. That is a mistake with a name: committing what has not been
read. They have been surveyed since, none of them is reachable from
`npm run check`, and two mocks they added — `test/mocks/LzStub.sol` and
`test/mocks/XSettle.sol` — do compile, which is why the suites stayed
green rather than telling anybody.

`probe-economy.mjs` was found broken and half-fixed: every deploy in it
read `r.createdAddress` from a harness that returns `r.address`, so every
address it captured was `undefined`. That fix is real and is kept. The
probe still reverts partway through, at `reclaim(bytes32)` with a custom
error, and it is left in that state deliberately rather than quietly
deleted — a measurement that stopped is a fact about the measurement.
