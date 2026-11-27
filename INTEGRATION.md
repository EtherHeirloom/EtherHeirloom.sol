# Integration guide

For wallets, Safe tools and other apps that want to offer inheritance for ERC-20 tokens on Ethereum by calling the deployed contract. Everything below works directly against the chain; the website is not required.

## Addresses

| Network | Address |
|---|---|
| Ethereum mainnet | [`0x0E0A916f469200318c9c6442038D45857ff41AE0`](https://etherscan.io/address/0x0e0a916f469200318c9c6442038d45857ff41ae0#code) |
| Sepolia testnet | [`0x2Db72e99E83005cA87CCd93F6FC1aa0C97a7Eb83`](https://sepolia.etherscan.io/address/0x2Db72e99E83005cA87CCd93F6FC1aa0C97a7Eb83) |

The full ABI is in the verified source on Etherscan, or run `forge build` and use `out/EtherHeirloom.sol/EtherHeirloom.json`.

## How a plan works

1. The owner calls `setupLegacies(beneficiaries, shares, delaySeconds)` with `msg.value >= setupFee()`. Shares are basis points and must add up to exactly `10000`. Up to 10 beneficiaries. Calling it again replaces the whole plan.
2. The owner approves the contract for each token that should be inherited (`token.approve(contract, amount)`). Tokens stay in the owner's wallet.
3. The date is `ownerExecutionTimestamp(owner)`. The owner can move it at any time with `resetDeadline(delaySeconds)` and `msg.value >= deadlineExtensionFee()`.
4. After the date anyone may call `claimLegacies(owner, beneficiary, tokens)` with `msg.value >= operationFee()`. Each beneficiary receives their share of the owner's current balance plus what was already delivered, so tokens received after setup are covered too. Up to 10 tokens per call.
5. The owner can stop deliveries of a token at any time by setting its approval to `0`.

Fees are `immutable`. Read them from the contract rather than hard-coding them. Any ETH sent above the fee is refunded in the same transaction.

## Examples (viem)

```ts
import { createPublicClient, createWalletClient, custom, http, parseAbi, erc20Abi, maxUint256 } from "viem";
import { mainnet } from "viem/chains";

const HEIRLOOM = "0x0E0A916f469200318c9c6442038D45857ff41AE0";

const heirloomAbi = parseAbi([
  "function setupFee() view returns (uint256)",
  "function operationFee() view returns (uint256)",
  "function deadlineExtensionFee() view returns (uint256)",
  "function ownerExecutionTimestamp(address owner) view returns (uint256)",
  "function totalAllocatedShares(address owner) view returns (uint256)",
  "function beneficiaryClaims(address owner, address beneficiary, address token) view returns (uint256)",
  "function getHeirloomsByOwner(address owner, uint256 offset, uint256 limit) view returns ((address owner, address beneficiary, uint64 beneficiaryIndex, uint64 ownerIndex, uint16 share, bool isActive)[])",
  "function getHeirloomsForBeneficiary(address beneficiary, uint256 offset, uint256 limit) view returns ((address owner, address beneficiary, uint64 beneficiaryIndex, uint64 ownerIndex, uint16 share, bool isActive)[])",
  "function setupLegacies(address[] beneficiaries, uint16[] shares, uint256 delaySeconds) payable",
  "function resetDeadline(uint256 newDelaySeconds) payable",
  "function claimLegacies(address owner, address beneficiary, address[] tokens) payable",
  "event LegacySetup(address indexed owner, address indexed beneficiary, uint256 indexed executionTimestamp, uint16 share)",
  "event DeadlineReset(address indexed owner, uint256 indexed newExecutionTimestamp)",
  "event LegacyClaimed(address indexed owner, address indexed beneficiary, address indexed token, uint256 amount)",
]);

const publicClient = createPublicClient({ chain: mainnet, transport: http() });
const walletClient = createWalletClient({ chain: mainnet, transport: custom(window.ethereum) });
const [account] = await walletClient.getAddresses();
```

Read a plan:

```ts
const plan = await publicClient.readContract({
  address: HEIRLOOM, abi: heirloomAbi, functionName: "getHeirloomsByOwner", args: [account, 0n, 50n],
});
const date = await publicClient.readContract({
  address: HEIRLOOM, abi: heirloomAbi, functionName: "ownerExecutionTimestamp", args: [account],
});
// plan[i].beneficiary, plan[i].share (basis points); date is a Unix timestamp in seconds
```

Create or replace a plan (two heirs, 60/40, one year from now), then approve a token:

```ts
const setupFee = await publicClient.readContract({ address: HEIRLOOM, abi: heirloomAbi, functionName: "setupFee" });

await walletClient.writeContract({
  account, chain: mainnet, address: HEIRLOOM, abi: heirloomAbi, functionName: "setupLegacies",
  args: [["0xHeirA...", "0xHeirB..."], [6000, 4000], 365n * 24n * 3600n],
  value: setupFee,
});

await walletClient.writeContract({
  account, chain: mainnet, address: TOKEN, abi: erc20Abi, functionName: "approve",
  args: [HEIRLOOM, maxUint256], // or a fixed amount
});
```

Move the date, or stop deliveries of one token:

```ts
const extensionFee = await publicClient.readContract({ address: HEIRLOOM, abi: heirloomAbi, functionName: "deadlineExtensionFee" });
await walletClient.writeContract({
  account, chain: mainnet, address: HEIRLOOM, abi: heirloomAbi, functionName: "resetDeadline",
  args: [2n * 365n * 24n * 3600n], value: extensionFee,
});

await walletClient.writeContract({
  account, chain: mainnet, address: TOKEN, abi: erc20Abi, functionName: "approve", args: [HEIRLOOM, 0n],
});
```

Find plans that name a user as heir, and deliver after the date:

```ts
const plans = await publicClient.readContract({
  address: HEIRLOOM, abi: heirloomAbi, functionName: "getHeirloomsForBeneficiary", args: [heir, 0n, 50n],
});

const operationFee = await publicClient.readContract({ address: HEIRLOOM, abi: heirloomAbi, functionName: "operationFee" });
await walletClient.writeContract({
  account, chain: mainnet, address: HEIRLOOM, abi: heirloomAbi, functionName: "claimLegacies",
  args: [plans[0].owner, heir, [TOKEN_1, TOKEN_2]], value: operationFee,
});
```

`claimLegacies` reverts with `ExecutionTimeNotReached` before the date and with `ClaimFailed` when nothing could be moved (no balance, no approval, or the share was already delivered). Simulate it first (`publicClient.simulateContract`) to show the user a clear message.

## Notes for integrators

- **Native ETH**: the contract handles ERC-20 tokens. Users who want to pass on ETH wrap it to WETH first.
- **Safe and other smart accounts**: the plan belongs to whichever address calls `setupLegacies`. A Safe can own a plan; batch `approve` and `setupLegacies` in one Safe transaction. The website also runs as a Safe App.
- **Always include `chainId`** when you send `eth_sendTransaction` yourself. Some wallet extensions estimate the transaction on the wrong network without it.
- **Indexing**: `LegacySetup`, `DeadlineReset` and `LegacyClaimed` are enough to show plan history and delivery status.
- **Tokens with transfer fees, rebasing or pausing** can deliver less than the share shows; the contract records what the heir actually received.

## Commercial use of the code

The code is under the [Business Source License 1.1](LICENSE) until 2030-01-01. Deploying your own instance of this code in production needs a commercial license until then. For a license, a fee-sharing integration or other partnership questions, write to **Ether-Heirloom@proton.me**.
