# FeeDiscountHook (Uniswap v4) — Fee Discount Hook

A Uniswap v4 **Hook** built with **Foundry** that applies a **discounted swap fee** for whitelisted users.

## Features

- ✅ Whitelisted users get a **lower fee override** (0.1% in this implementation)
- ✅ Non-whitelisted users pay the **normal pool fee**
- ✅ Includes Foundry tests using Uniswap v4 core test utilities (`Deployers`, `PoolSwapTest`, `HookMiner`)

## What this hook does

This hook implements the **beforeSwap hook** and dynamically returns a fee override:

- If `tx.origin` is whitelisted → `feeOverride = DISCOUNTED_FEE`
- Otherwise → `feeOverride = 0` (no override, default pool fee applies)

> ⚠️ Note: using `tx.origin` is intentional here to support router-based swaps in tests.
> In production systems you might want to use `msg.sender`, signed payloads, or more robust user identity checks.

## Files

### Hook Contract
- `src/feeDiscount.sol`

Key elements:
- `FeeDiscountHook` inherits `BaseHook`
- owner-controlled `setWhitelist`
- implements `_beforeSwap(...)`
- returns `BeforeSwapDeltaLibrary.ZERO_DELTA` and a fee override

### Tests
- `test/feeDiscount.t.sol`

Tests include:
- only owner can whitelist users
- whitelisted swaps pay less than non-whitelisted swaps
- revoked whitelist pays full fee again
- zero amount swap reverts (`SwapAmountCannotBeZero`)

## Tech Stack

- **Solidity** `^0.8.24`
- **Foundry**
- **Uniswap v4 core + periphery**
- `HookMiner` for deterministic hook deployment with correct permissions flags

## Setup

### Prerequisites

- Install Foundry

```sh
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

### Installation

```sh
# Install dependencies
forge install

# Build
forge build

# Test
forge test -vv

# Format
forge fmt
```

## How it works (high level)

1. **Hook permissions**

   The hook declares only beforeSwap as enabled:

   ```solidity
   beforeSwap: true
   ```

2. **Hook deployed using HookMiner**

   Uniswap v4 hooks must be deployed at an address that matches the hook permissions flags.

   The tests use:

   ```solidity
   HookMiner.find(...)
   new FeeDiscountHook{salt: salt}(manager)
   ```

   so that the hook address matches the required flags.

3. **Discount fee override**

   The hook applies:

   ```solidity
   uint24 public constant DISCOUNTED_FEE = 1000; // 0.1%
   ```

   Then in `_beforeSwap`:

   ```solidity
   uint24 feeOverride = whitelist[tx.origin] ? DISCOUNTED_FEE : 0;
   ```

## Example expected output (tests)

When running:

```sh
forge test -vv
```

You should see logs like:

```
Whitelisted user input paid < Non-whitelisted input paid
Savings shown in wei
```

## Security Notes

This is a learning project.

- Access control is owner-based and simple.
- Using `tx.origin` is generally discouraged in production but useful in router-based swaps & testing.

## Contributing

Contributions are welcome! Please open an issue or submit a pull request.

## License

[MIT License](LICENSE)