# Invariants

Statements that must hold in every reachable state. Each names the test that
tries to break it. If any of these can be made false, that is a bug regardless
of what else passes.

The form is borrowed from the Dave Held core, which lists twenty-five of these
above its contracts. It is the most useful thing in that repository: an
invariant written down is a claim that can be attacked, where a feature list is
only a claim that something happened.

---

## The artwork

**1. The document that comes back is the document that went in.**
Every byte of `tokenURI`'s `animation_url`, after base64 → JSON → base64 → gzip,
equals the source. Nothing in the pipeline may quietly alter the engine.
→ `tools/verify.mjs` · *"the document that comes back is byte-for-byte the document that went in"*

**2. A shard round-trips exactly.**
`SSTORE2.read(SSTORE2.write(x)) == x` for any non-empty `x` under 24,575 bytes,
and the deployed runtime always begins with `STOP`.
→ `test/Ipseity.t.sol::testFuzz_sstore2_roundTrips`, `test_sstore2_roundTripsExactly`

**3. A frozen engine never changes again.**
After `freeze()` no shard can be added, replaced or dropped, by anyone, forever.
→ `test_engine_frozenIsForever`, `tools/verify.mjs`

**4. A sealed renderer never changes again.**
After `sealRenderer()` the renderer pointer and the market pointer are both fixed.
→ `test_sealedRendererIsForever`

**5. Every token is born renderable.**
A minted token's section word always names one of the eight solids and never
sets a bit above 128. No mint can produce a token that cannot be drawn.
→ `testFuzz_mint_alwaysBornRenderable`

**6. Only a renderable section can be committed.**
→ `test_commit_refusesASolidThatDoesNotExist`, `test_commit_refusesBitsAboveTheWord`

**7. The section word round-trips.**
Six angles, an offset, a solid and a hue pack into one word and come back
identical.
→ `testFuzz_sectionWord_roundTrips`

**8. Every shader compiles.**
No document is ever packaged whose GLSL would fail to compile.
→ `tools/glsl-check.mjs`, enforced in `tools/build-engine.mjs`

**9. The token's own cryptography agrees with Ethereum.**
The keccak-256, ABI coder, EIP-55 checksum, EIP-712 hasher and CREATE2
derivation carried inside the engine match published vectors.
→ `tools/selftest.mjs`

---

## Custody

**10. `locked()` and `isTransferable()` never disagree.**
There is one flag. ERC-6454 is written in terms of ERC-5192, so the collection
cannot tell two different stories about whether a token can be sold.
→ `testFuzz_lockAndTransferableNeverDisagree`

**11. A bound token does not move.**
→ `test_boundTokenWillNotMove`

**12. A lease never survives a sale.**
Transferring a token clears its ERC-4907 user in the same transaction.
→ `test_leaseDoesNotSurviveTheSale`

**13. A renter operates the artwork and never the money.**
The ERC-4907 user may commit a section. They may not transfer the token,
withdraw inventory, or sync a market's curve.
→ `test_borrowerMayOperateButNotSell`, `test_renterCannotRepriceSomeoneElsesLiquidity`

**14. Enumeration survives churn.**
`tokenOfOwnerByIndex` remains a complete, duplicate-free view of each owner's
holdings across arbitrary transfer orders.
→ `test_enumerationSurvivesChurn`, `tools/verify.mjs`

---

## The market

**15. The invariant never falls.**
`(x + vx)(y + vy)` is the same or larger after every trade that succeeds, at
every curve a holder can commit. If it can be made to fall the pool can be
drained one trade at a time.
→ `testFuzz_invariantNeverFalls`, `tools/verify-pool.mjs` (200 random trades)

**16. A round trip never profits.**
Buying and immediately selling back always returns less than it cost, at every
curve. There is no free arbitrage inside the pricing.
→ `testFuzz_roundTripNeverProfits`, `tools/verify-pool.mjs`

**17. The pool never pays out more than it holds.**
The curve prices against virtual reserves and will quote more than the real
balance; no trade may take more than half the outgoing reserve, and an
oversized trade is refused rather than partially filled.
→ `testFuzz_neverPaysMoreThanItHolds`

**18. More in never means less out.**
The pricing is monotonic in the input at every curve.
→ `testFuzz_outputIsMonotonicInInput`

**19. Concentration is bounded, and only `w` moves it.**
Concentration is always within `[0, MAX_CONCENTRATION]`, and rotations in the
three planes that do not contain `w` leave it exactly zero — spinning the
section changes the picture's orientation and never the price.
→ `testFuzz_concentrationIsBounded`, `test_turningThroughWConcentratesTheCurve`

**20. The market's curve is a copy, never a live read.**
Turning the artwork does not move a market until the holder syncs it.
→ `test_renterCannotRepriceSomeoneElsesLiquidity`

**21. Only the holder moves inventory.**
Depositing, withdrawing, opening, closing, re-pricing and syncing are all
holder-only. Trading is open to everyone.
→ `test_onlyHolderMayOpenDepositWithdrawOrSetFee`

**22. Selling the token sells the market.**
Reserves, fee income and curve follow `ownerOf`. The seller loses access in the
same transaction the buyer gains it.
→ `test_sellingTheTokenSellsTheMarket`

**23. A bond only ever moves further out, and it survives the sale.**
`bondUntil` cannot be lowered by anyone, including through a transfer. While it
holds, nothing exits and no term changes — not withdrawal, not closure, not the
fee, not the curve. Deposits and trades still work, because those are additive.
→ `tools/verify-pool.mjs` · *the bond*

**24. A bond has a ceiling.**
No bond may run longer than a year. A promise nobody can outlive is
indistinguishable from burning the inventory.
→ `tools/verify-pool.mjs` · *"a bond longer than anyone can outlive"*

**25. The credited reserve is what arrived, never what was asked for.**
A token that takes a cut on transfer is credited its net; a token that returns
no data at all is accepted.
→ `test_feeOnTransferTokenIsCreditedOnlyWhatArrived`, `test_silentTokenIsAccepted`

**26. A trade honours its floor and its deadline.**
→ `test_slippageFloorIsHonoured`, `test_deadlineIsHonoured`

---

## The vault

**32. A sealed vault's manifest never shrinks.**
While `sealedUntil` has not passed, no call through `execute` may leave the
account holding less of any listed asset, or less ether, than it held before —
whatever that call was. Enforced by measuring balances either side of the call,
not by listing the words that move assets, because that list cannot be
completed.
→ `tools/verify-vault.mjs` · *"a word no list has ever heard of"*

**33. While sealed, no approval executes.**
An approval moves nothing at the moment it is granted, so measurement is
structurally blind to it and the loss lands in a later block. `approve`,
`setApprovalForAll`, `increaseAllowance` and both `permit` shapes are refused
outright. There is no venue registry here to make exceptions for, so there are
no exceptions.
→ `tools/verify-vault.mjs` · *"approving a spender to pull later"*

**34. While sealed, no ether leaves and no signature is honoured.**
Both are authorities whose effect lands outside the window a same-transaction
measurement can observe. `isValidSignature` returns zero while sealed.
→ `tools/verify-vault.mjs`

**35. The seal only ratchets, has a ceiling, and survives the sale.**
It can be pushed further out by the holder and lowered by nobody. It cannot run
past a year. It binds the buyer exactly as it bound the seller.
→ `tools/verify-vault.mjs` · *the seal*, *the promise survives the sale*

**36. `execute` is CALL only.**
`delegatecall` would let the holder rewrite the account's own storage, including
the seal. Any operation other than 0 reverts.
→ `tools/verify-vault.mjs` · *"delegatecall, which would rewrite the account"*

**37. A sealed vault can still act.**
Anything leaving it no poorer goes through. Measuring rather than freezing is
the whole reason: a vault that cannot act is a safe.
→ `tools/verify-vault.mjs` · *"but the vault still works"*

---

## The other hand

Every token has two ERC-6551 accounts at two salts. The Reach
(`IpseityAccount`) can act and is policed. The Grip (`GripVault`) cannot act
and needs no policing. The registry is canonical and the implementation is a
parameter, which is what makes this possible at all.

**38. The Grip has no function that spends.**
Every state-changing function in its compiled ABI is a token receiver. There
is no `execute`, no withdraw, no sweep, no rescue, no owner override, no
admin, no upgrade path — for the holder, for the collection, for governance,
forever. Asserted against the ABI, not the source, because the guarantee is
structural rather than behavioural.
→ `tools/verify-vault.mjs` · *"every state-changing function is a token receiver"*, *"there is no execute"*

**39. The Grip does not advertise a capability it lacks.**
`supportsInterface` deliberately excludes `0x51945447` (IERC6551Executable), so
a client that checks before calling `execute` is told the truth in advance
rather than discovering it in a revert.
→ `tools/verify-vault.mjs` · *"it declines to advertise IERC6551Executable"*

**40. A Grip's holdings are a floor, not a snapshot.**
Because nothing can leave, the number a buyer reads before they pay is a
number the seller cannot move between a handshake and a settlement. This is
the invariant the whole two-hand split exists to produce.
→ `tools/verify-vault.mjs` · *"so the attacks have nothing to aim at"*

---

## Session keys

**41. A session is bounded four ways and can widen none of them.**
An expiry it cannot extend, a target allowlist it cannot widen, a selector
allowlist it cannot widen, and a cumulative native spend cap it cannot raise.
All four are checked on every call, and the cap counts across the session's
whole life rather than per call, so the same allowance cannot be spent twice.
→ `tools/verify-vault.mjs` · *"a selector it was not granted"*, *"a target it was not granted"*, *"the spend cap counts across the whole session"*, *"the expiry is a wall the key cannot move"*

**42. A session cannot reach the account itself.**
`to == address(this)` reverts in `executeAsSession`, and `address(this)` is
refused as an allowlist entry at grant time. Otherwise the agent's first act
is granting itself a session with no limits and every other bound is
decorative.
→ `tools/verify-vault.mjs` · *"calling the account itself, to grant itself more"*

**43. A session cannot approve a spender that was not named.**
For `approve`, `increaseAllowance` and `setApprovalForAll`, the *spender
argument* must itself be on the target allowlist. Allowlisting the token
contract says who is being called, never who is being trusted.
→ `tools/verify-vault.mjs` · *"approving a spender nobody named"*, *"setApprovalForAll is checked the same way"*

**44. Revocation is immediate and unilateral.**
One transaction by the holder, no delay, no notice, no appeal.
→ `tools/verify-vault.mjs` · *"revoked instantly"*

**45. A session is never more trusted than the holder.**
Session calls go through the same `_act` gauntlet, so while the Reach is
sealed a session is subject to the same measurement and the same approval
refusals. And the Grip is out of reach because the Grip has no function to
reach for.
→ `tools/verify-vault.mjs` · *"the Grip is not on any allowlist it could be given"*

---

## The sealed kernel

The one place ERC-7857 is not a stretch here: a token carries a payload that
is not public — the disposition an agent runs under — named on chain only by
hash. See `AGENT.md`. Conformance is deliberately not claimed; see the note in
`src/interfaces/Standards.sol`.

**46. A kernel's staleness is derived, never announced.**
`kernelStatus` compares the owner the kernel was sealed under against
`ownerOf` at read time. `transferWithKernel` re-seals atomically, but ordinary
`transferFrom` still exists — it has to, or the token stops being an ERC-721 —
and it moves the token while leaving the payload encrypted to the seller. That
shows up as STALE with no hook, no gas and no cooperation from a seller who
would rather it went unmentioned. The only half of the comparison a seller
controls is the one that already moved.
→ `tools/verify-kernel.mjs` · *"the kernel went STALE by itself"*, *"the ERC-7496 trait reports it too"*

**47. Sealed, current and proved are three questions, asked separately.**
`sealKernel` is an assertion by the holder. `kernelStatus` says the payload was
sealed under whoever holds the token now. `kernelProved` says a verifier
checked that exact re-sealing. With no verifier deployed the third is false
everywhere, and no reading of the first two can be mistaken for it.
→ `tools/verify-kernel.mjs` · *"sealed is not proved"*, *"proved goes with it"*

**48. A proof is about this token's payload, or it is refused.**
The old hashes in a proof must equal the hashes on file, so a proof cannot be
lifted from one token and replayed against another, and a re-seal cannot empty
a kernel under cover of a transfer.
→ `tools/verify-kernel.mjs` · *"a proof about a different payload is rejected"*

**49. The verifier is chosen once and never rotated.**
It may be set from zero exactly one time, never to zero, and after that
`setVerifier` reverts for everybody including the curator. A rotatable
verifier is not a verifier: whoever can swap it can install one that approves
anything, and every kernel becomes a claim about the curator rather than about
a proof.
→ `tools/verify-kernel.mjs` · *"it can never be swapped"*

**50. With no verifier, the proved paths refuse rather than wave through.**
`transferWithKernel` and `cloneWithKernel` revert on a live kernel when there
is no oracle. A token with no kernel still transfers through them, because
there is nothing to prove.
→ `tools/verify-kernel.mjs` · *"the atomic path refuses rather than waving through"*

---

## Privilege

**27. No admin path can move an asset.**
The market's five admin entry points are `setPaused`, `bless`,
`setAllowlistEnforced`, `proposeAdmin`, `acceptAdmin`. Not one takes a token id
or an amount, so not one can name a thing to move. Asserted against the compiled
ABI rather than by reading the source.
→ `tools/verify-pool.mjs` · *"what the admin cannot do"*

**28. The pause never traps money.**
Pausing halts trading and deposits. Withdrawal has no pause modifier and is
reachable in every state. A pause that traps money is a slower theft.
→ `tools/verify-pool.mjs` · *"but withdrawal still works"*

**29. Privilege never transfers in one step.**
Both the collection's curator and the market's admin move by propose-and-accept.
An address that cannot answer never receives the role, so a mistyped handover
is recoverable rather than permanent.
→ `tools/verify-timelock.mjs`, `tools/verify-pool.mjs` · *admin handover*

**30. A timelocked change takes seven days and announces itself first.**
Queued operations cannot execute early, cannot execute after the fortnight
grace window, cannot be re-queued to move a published eta, and cannot be
replayed. The full calldata is in the `Queued` event.
→ `tools/verify-timelock.mjs`

**31. The timelock admin cannot escape the delay.**
Rotating the admin is only reachable through the queue, so it takes the same
seven days as anything else.
→ `tools/verify-timelock.mjs` · *"the admin rotating itself directly"*

---

## Known and not fixed

These are true, they are not tested, and they are not defended against. They are
here because an undocumented limitation is worse than a documented one.

**A0. A Grip is permanent, and permanence is not a feature that can be
walked back.**
An asset sent to a Grip is there until the token stops existing, which in
this collection is never — there is no burn. A mistaken transfer into a Grip
is a permanent mistake. The interface says so before it will build the
calldata, and that is all any interface can do. This is the correct trade for
holdings a token carries as part of what it *is*, and the wrong trade for
anything that has to stay liquid — which is why market inventory lives in
`Pool.sol` behind a time-boxed bond and working capital lives in the Reach.

**A. The seal covers the manifest, and nothing else.**
*(This was previously "the vault can be emptied between a handshake and a
settlement", with no fix. It is fixed: the collection ships its own ERC-6551
implementation — see `src/IpseityAccount.sol` — so the vault can be sealed the
same way a market can be bonded. What follows is what remains.)*

Only assets on the manifest are measured. An asset that arrives after the seal,
in a contract nobody listed, can leave freely. The manifest is additive and
public for exactly that reason: a buyer reads `manifest()` and `holdings()`,
they do not assume. The cap is sixteen entries, because every entry is two
balance reads on every sealed call.

**A2. The seal cannot promise about a lying token.**
`_balance` reads `balanceOf(address)` from the asset itself. A token contract
that misreports its own balances defeats the measurement, as it defeats every
other accounting built on it. Seal assets you would hold anyway.

**B. A holder can re-shape an unbonded curve against a pending trade.**
Where the art and the price are the same numbers, this is not preventable. It is
bounded instead: every swap carries a trader-set `minOut`, checked after the
fact. A trader who sets it is unharmed. A bond removes the possibility entirely
for as long as it holds.

**B2. A session key is a hot key.**
Its bounds hold if it is stolen — that is the entire design — but everything
inside those bounds is gone. `spendCap` and `expires` should be numbers you
would be willing to lose outright, and targets should be granted one at a
time. The collection makes theft survivable; it does not make it free.

**B3. Re-sealing a kernel does not make the seller forget.**
ERC-7857's re-encryption gives the buyer the secret. Nothing on any chain
takes it back from whoever held it first, and no oracle changes that. A kernel
is worth buying when its value is *use going forward*, and worth nothing when
its value is *exclusivity*. This is a limitation of the standard rather than
of this implementation.

**B4. There is no verifier, so no kernel has ever been proved.**
`verifier` is zero as this collection deploys, `hasVerifier()` says so, and
`kernelProved()` is false for every token. A buyer must fetch the payload,
hash it, compare against `dataHashesOf` and decrypt it themselves before
paying. The contract makes that possible and does not make it unnecessary. A
stub verifier was not shipped because a green check nobody earned is worse
than no check at all — and because the verifier can only be chosen once, a
stub would have been permanent.

**B5. A kernel names its payload by hash and does not store it.**
The hashes are permanent; whatever they hash to is not. If the payload
disappears, the token still states what it committed to and can no longer
demonstrate what that was. Pin it.

**C. Nothing here has been audited.**
`Pool.sol` holds other people's money and has never been reviewed by anyone. The
per-market deposit cap exists for that reason and should be raised only after a
review.

**D. `forge test` has never been executed.**
Foundry's installer host is unreachable from the environment this was built in.
The Solidity suites type-check against the compiler but have not run. The
JavaScript harnesses in `tools/` have run, and every number in the README comes
from them.
