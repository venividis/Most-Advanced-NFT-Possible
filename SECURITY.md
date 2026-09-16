# Security policy

IPSEITY contracts are intended to become immutable, and defects in deployed
bytecode cannot be patched. Please do not disclose a suspected vulnerability in
a public issue, discussion, or pull request before it has been investigated.

## Reporting a vulnerability

Use GitHub's **Security** tab and select **Report a vulnerability** to open a
private vulnerability report. Include, when possible:

- the affected contract, function, chain, and deployment address;
- the security property that can be violated and its practical impact;
- the smallest reproducible transaction sequence or test case;
- whether exploitation has been observed; and
- a safe way to contact you for follow-up.

Do not include private keys, seed phrases, or credentials. A test-only key that
reproduces a report should hold no assets outside the reproduction.

A maintainer should acknowledge a report within seven days. Validation,
remediation, and disclosure timing depend on the affected deployment's
immutability and the risk of publishing exploitation details. If GitHub private
reporting is unavailable, do not publish the report; contact a maintainer through
the address listed on their GitHub profile and ask for a private reporting
channel.

## Scope

The Solidity contracts, the on-chain renderer and site, and the build,
verification, and deployment tools in this repository are in scope. Public RPC
providers, wallets, browsers, block explorers, LayerZero infrastructure, and
other third-party services are outside this repository's control, though reports
showing an unsafe interaction with them are welcome.

Deployment records identify what is live. A finding against source that differs
from deployed bytecode should clearly identify which version was tested.
