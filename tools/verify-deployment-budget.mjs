#!/usr/bin/env node
import { strict as assert } from "node:assert";
import { deploymentBudget, ROLLUP_L1_FEE_ALLOWANCE } from "./deployment-budget.mjs";

const gasPrice = 6_000_000n; // the Base Sepolia price that badly underquoted the live run
const execution = 180_000_000n * gasPrice * 15n / 10n;

for (const chainId of [10, 130, 4663, 8453, 84532, 42161]) {
  const budget = deploymentBudget(chainId, gasPrice);
  assert.equal(budget.l1Data, ROLLUP_L1_FEE_ALLOWANCE, `chain ${chainId} reserves L1 data fees`);
  assert.equal(budget.total, execution + ROLLUP_L1_FEE_ALLOWANCE + 200_000_000_000_000n);
}

const ethereum = deploymentBudget(1, gasPrice);
assert.equal(ethereum.l1Data, 0n, "L1 chains do not get a rollup fee reserve");
assert.equal(ethereum.total, execution + 200_000_000_000_000n);

console.log("  ✓ deployment budgets reserve rollup L1 data fees");
