# Mainnet readiness

IPSEITY is a testnet release candidate, not a mainnet release. A successful
testnet deployment or a green local suite is evidence; neither is an audit.
No contract that can custody user value should be advertised as production
ready until every blocking gate below is closed.

## Blocking gates

- [ ] Freeze a release commit and reproduce its bytecode from a clean clone.
- [ ] Run the complete JavaScript verification suite and native `forge test`.
- [ ] Add long-running stateful invariant campaigns for Pool, Reach, Lease,
      transfer/self-account refusal, and session-key accounting.
- [ ] Obtain an independent audit of the frozen release, prioritising Pool,
      IpseityAccount, Ipseity, Lease, the browser wallet, and LayerZero paths.
- [ ] Resolve every critical/high audit finding and retest accepted mediums.
- [ ] Put curator authority behind a hardware-backed multisig and timelock.
- [ ] Rehearse the exact engine freeze, renderer seal, verifier choice, and
      ownership-transfer ceremony on both target-network forks and testnets.
- [ ] Verify compiler settings, constructor arguments, creation bytecode, and
      deployed runtime bytecode independently before irreversible sealing.
- [ ] Publish the known limitations, immutable powers, deposit caps, and an
      incident-response contact before accepting public funds.
- [ ] Launch with conservative Pool caps and a funded bug bounty.

## Deployment safety requirements

Deployment keys must never be generated or retained by an ephemeral agent
workspace. Use an operator-controlled hardware wallet, multisig, or persistent
secret manager. `tools/testnet.mjs` writes an append-only JSONL receipt journal
to `dist/deployment-<chain>-<deployer>.jsonl` after every mined transaction.
The journal contains only public receipt metadata—never keys, signed
transactions, or calldata—and must be archived after each run.

Before broadcasting:

1. Run `npm run build`; deployment requires `dist/shards.json`.
2. Confirm the chain ID, ERC-6551 registry, Uniswap/LayerZero endpoints, and
   token-id band against primary network documentation.
3. Fund from the printed preflight requirement, not a historical estimate.
4. Set `DEPLOYMENT_JOURNAL` to persistent storage outside the build host when
   the default `dist/` directory is ephemeral.
5. Stop on any bytecode, nonce, balance, or endpoint disagreement.

After broadcasting:

1. Archive the receipt journal and public deployment record immediately.
2. Run `tools/recover-record.mjs` from a separate RPC and compare every
   reachable address with the record. Recovery is read-only and requires no
   deployer key.
3. Exercise every route and state transition against the deployed contracts.
4. Verify source and constructor arguments on the chain explorer.
5. Do not execute one-way seals until independent reviewers reproduce the
   artifact hashes and the multisig approves the ceremony.

## Explicit non-blocking limitations

These design constraints cannot be “fixed” by deployment procedure and must be
disclosed to users: Grip deposits are irreversible; a malicious asset may lie
about balances; an unbonded market can be reshaped subject to `minOut`; session
keys expose everything inside their bounds; kernel resealing cannot make a
seller forget; and no kernel proof exists without a real verifier.

This checklist may only be marked complete for one exact source commit and one
set of deployment artifacts. Later code changes reopen the applicable gates.
