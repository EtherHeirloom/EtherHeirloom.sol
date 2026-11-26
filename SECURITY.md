# Security Policy

EtherHeirloom is an open-source, non-custodial contract. We welcome reports from security researchers and treat them seriously.

## Scope

- The deployed contract on Ethereum mainnet: [`0x0E0A916f469200318c9c6442038D45857ff41AE0`](https://etherscan.io/address/0x0e0a916f469200318c9c6442038d45857ff41ae0#code)
- The source in this repository that matches it

Out of scope: the website's look and wording, third-party tokens and wallets, issues that need the owner's own private key, and findings already listed as known limitations below.

## How to report

Report privately through GitHub: **Security → Report a vulnerability** in this repository ([direct link](https://github.com/EtherHeirloom/EtherHeirloom.sol/security/advisories/new)). If you cannot use GitHub, email **Ether-Heirloom@proton.me**.

Please do not open a public issue or pull request for a vulnerability, and do not test against other people's plans on mainnet. A local fork or Sepolia (`0x2Db72e99E83005cA87CCd93F6FC1aa0C97a7Eb83`) is enough to show impact.

A good report has:
- the affected function and a short description;
- the impact: funds at risk, funds stuck, or a wrong amount;
- steps or a Foundry test that reproduces it.

We aim to acknowledge reports within a few days and keep you updated until the issue is resolved.

## Rewards

We reward valid, previously unreported findings at our discretion. The amount depends on severity and impact, with the greatest weight on anything that lets tokens reach anyone other than the listed heirs. With your permission we credit you once the issue is resolved.

## Known limitations (by design)

- The owner keeps full control: they can replace the plan, move the date or revoke an approval at any time, so a plan pays only what the owner still allows.
- After the date anyone may call `claimLegacies`; tokens still go only to the listed heir.
- Tokens with fees on transfer, rebasing or pausing can deliver less than expected.
