# EtherHeirloom

[![Tests](https://github.com/EtherHeirloom/EtherHeirloom.sol/actions/workflows/test.yml/badge.svg)](https://github.com/EtherHeirloom/EtherHeirloom.sol/actions/workflows/test.yml)

Non-custodial inheritance for ERC-20 tokens on Ethereum.

Tokens stay in the owner's wallet. The owner sets beneficiaries with shares (basis points, total 10 000) and a deadline, and gives the contract an ERC-20 allowance. After the deadline the contract can move each beneficiary's share with `transferFrom`, only from the owner to the addresses the owner listed. Anyone may trigger a claim; tokens always go to the listed beneficiary.

- Website: https://ether-heirloom.github.io/
- Mainnet contract: [`0x0E0A916f469200318c9c6442038D45857ff41AE0`](https://etherscan.io/address/0x0e0a916f469200318c9c6442038d45857ff41ae0#code) (verified source)
- Sepolia testnet contract: [`0x2Db72e99E83005cA87CCd93F6FC1aa0C97a7Eb83`](https://sepolia.etherscan.io/address/0x2Db72e99E83005cA87CCd93F6FC1aa0C97a7Eb83)
- Works inside [Safe](https://app.safe.global) as a custom Safe App: add `https://ether-heirloom.github.io/` under Apps → My custom apps.
- Security reports: see [SECURITY.md](SECURITY.md).

## Contract facts

- No owner or admin functions, no pause, no upgrade proxy.
- Fees are `immutable` and set in the constructor; they cannot change after deployment.
- The only mutable protocol setting is `protocolFeeRecipient`, changeable only by the current recipient.
- Up to 10 beneficiaries and up to 10 tokens per claim transaction.

## Build and test

Requirements: [Foundry](https://getfoundry.sh/), Node.js.

```bash
git clone --recurse-submodules https://github.com/EtherHeirloom/EtherHeirloom.sol
cd EtherHeirloom.sol
npm ci          # OpenZeppelin Contracts
forge build
forge test
```

Compiler settings match the mainnet deployment: Solidity 0.8.24, optimizer enabled with 500 runs, EVM `cancun`, no via-IR.

## License

Business Source License 1.1, see [LICENSE](LICENSE).
