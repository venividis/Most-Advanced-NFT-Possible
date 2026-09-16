/* Deployment funding must include fees that eth_gasPrice cannot see. OP Stack
   and Arbitrum-family chains charge an additional L1 data fee for transaction
   calldata. A full deployment measured 0.0214 ETH on Base Sepolia, so reserve
   more than twice that observed total rather than pretending execution gas is
   the whole bill. Keep this deliberately simple and auditable: it is a funding
   floor, not a quote. */
const ROLLUP_CHAIN_IDS = new Set([
  10, 11155420,          // Optimism, Optimism Sepolia
  130, 1301,             // Unichain, Unichain Sepolia
  4663, 46630,           // Robinhood Chain, Robinhood testnet
  8453, 84532,           // Base, Base Sepolia
  42161, 421614,         // Arbitrum One, Arbitrum Sepolia
]);

export const ROLLUP_L1_FEE_ALLOWANCE = 5n * 10n ** 16n; // 0.05 ETH

export function deploymentBudget(chainId, gasPrice, deploymentGas = 180_000_000n) {
  const execution = (deploymentGas * BigInt(gasPrice) * 15n) / 10n;
  const l1Data = ROLLUP_CHAIN_IDS.has(Number(chainId)) ? ROLLUP_L1_FEE_ALLOWANCE : 0n;
  const seedMints = 2n * 10n ** 14n;
  return { execution, l1Data, seedMints, total: execution + l1Data + seedMints };
}
