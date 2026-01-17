# EtherHeirloom Smart Contract

A Solidity smart contract project built with Foundry.

## Prerequisites

- [Foundry](https://getfoundry.sh/) - Modern Ethereum development framework
- [Node.js](https://nodejs.org/) - For managing dependencies
- [Python 3.8+](https://www.python.org/) - For Slither analysis

## Installation

### 1. Install dependencies

```bash
npm install
```

### 2. Install Foundry libraries

```bash
forge install
```

## Project Structure

```
.
├── contracts/           # Smart contract source files
│   └── EtherHeirloom.sol
├── test/               # Test files
│   └── EtherHeirloom.t.sol
├── lib/                # External libraries (managed by Forge)
├── foundry.toml        # Foundry configuration
├── package.json        # NPM dependencies
└── README.md          # This file
```

## Available Commands

### Building

```bash
# Build contracts
forge build

# Clean build artifacts
forge clean
```

### Testing

```bash
# Run all tests
forge test

# Run tests with verbose output
forge test -vv

# Run specific test file
forge test --match-path test/EtherHeirloom.t.sol

# Run tests with gas reporting
forge test --gas-report
```

### Code Analysis & Security

#### Slither (Static Analysis)

```bash
# Run Slither analysis
slither contracts/EtherHeirloom.sol \
  --solc-args "--via-ir --optimize --optimize-runs 200" \
  --solc-remaps "@openzeppelin/=$(pwd)/node_modules/@openzeppelin/" \
  --json slither_results.json
```

#### Aderyn (Static Analysis)

```bash
# Run Aderyn analysis
aderyn --src=contracts/
```

### Code Formatting

```bash
# Format contracts
forge fmt

# Check formatting without changes
forge fmt --check
```

## Configuration

### Foundry Configuration (`foundry.toml`)

- **Solidity Version**: 0.8.24
- **Optimizer**: Enabled with 200 runs
- **EVM Version**: Cancun
- **Via IR**: Enabled for production builds

### Test Settings

- Fuzz runs: 10000 (CI profile)
- Invariant runs: 1000 (CI profile)

## Dependencies

- **@openzeppelin/contracts** - OpenZeppelin token and security libraries
- **forge-std** - Standard library for Foundry tests

## Development Workflow

1. **Write contracts** in `contracts/`
2. **Write tests** in `test/` using Foundry syntax
3. **Run tests**: `forge test`
4. **Analyze code**: `slither contracts/` and `aderyn --src=contracts/`
5. **Format code**: `forge fmt`
6. **Deploy** (when ready)

## Security Best Practices

- Always run tests before deployment
- Use Slither for vulnerability detection
- Review security implications of external dependencies
- Follow OpenZeppelin best practices
- Use ReentrancyGuard for functions that make external calls and modify state
