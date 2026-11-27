# Static analysis and test notes

This is not an audit. The contract has not been reviewed by an external auditor. This page lists what automated tools report and why each finding is expected, so anyone can check the reasoning.

Every push runs [Slither](https://github.com/crytic/slither) in CI ([workflow](.github/workflows/test.yml), [config](slither.config.json)). The job fails on any high-severity finding that is not explained below.

## Findings

| Detector | Severity | Where | Why it is expected |
|---|---|---|---|
| `arbitrary-send-erc20` | High | `_executeTransfer`: `safeTransferFrom(owner, beneficiary, amount)` | Moving tokens from the owner's wallet is the purpose of the contract. The `from` address is not arbitrary: it is the owner who created the plan and approved the contract. The transfer only runs after the owner's date, only to a beneficiary the owner listed, and only up to that beneficiary's share. The owner can stop it at any time by revoking the approval. This is the one detector excluded in the config; the invariant tests below check these limits. |
| `incorrect-equality` | Medium | `_claimInternal`: `paymentDue == alreadyClaimed` | Compares two internal accounting values, not an external balance that someone could push to a value. The same line also handles `paymentDue < alreadyClaimed`, so a strict-equality bypass is not possible. |
| `calls-loop` | Low | `claimLegacies` loops over up to 10 tokens | Each token is handled independently; a token that misbehaves makes only that transaction fail and cannot affect other plans. The loop length is capped by `MAX_BATCH_TOKENS = 10`. |
| `cyclomatic-complexity` | Informational | `setupLegacies` | Input validation (lengths, duplicates, zero addresses, shares) in one function. Covered by unit and fuzz tests. |

Excluded detectors with no bearing on security: `naming-convention`, `solc-version`, `pragma` (the version is pinned to the deployed compiler, 0.8.24), `timestamp` (the date is meant to be compared with `block.timestamp`; minutes of validator drift do not matter for a date set days or years ahead), `low-level-calls` (used only to forward ETH fees and refunds, with the result checked).

## Tests

`forge test` runs three kinds of tests:

- **Unit tests** (`test/EtherHeirloom.t.sol`, `test/Test01` to `Test17`): specific scenarios, edge cases and earlier review findings.
- **Fuzz tests** (`test/Test18_Fuzz.t.sol`): each rule is checked against random balances, shares, dates, fees and callers. For example: shares are accepted only if they add up to exactly 100%; nothing can be claimed before the date; each heir gets exactly their share rounded down; anyone may trigger delivery but the tokens go to the heir, never to the caller; a revoked approval stops all deliveries; tokens received later are shared by the same percentages; overpaid fees are refunded.
- **Invariant tests** (`test/Test19_Invariants.t.sol`): random sequences of real actions (create or change the plan, move the date, revoke or restore the approval, receive or spend tokens, let time pass, deliver to random heirs from random callers). After every step these must hold:
  - the contract never holds tokens or ETH;
  - a plan allocates either nothing or exactly 100%;
  - nothing is delivered before the date;
  - tokens leave the owner only towards the heir they were claimed for, and the caller never gains anything;
  - the contract's record of delivered amounts matches what heirs actually received.

CI uses a stronger profile (`FOUNDRY_PROFILE=ci`: 5 000 fuzz runs per test, 500 invariant sequences of 500 calls each) and prints a coverage summary for the contract in each run.
