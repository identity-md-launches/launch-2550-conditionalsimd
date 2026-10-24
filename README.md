# ConditionalsIMD (CONDITIONAL)

A fixed-supply ERC-20 token implemented with vendored OpenZeppelin Contracts v5.1.0.

## Token and deployment parameters

| Parameter | Value |
| --- | --- |
| Solidity contract | `ConditionalsIMD` |
| Source | `src/ConditionalsIMD.sol` |
| Token name | `ConditionalsIMD` |
| Symbol | `CONDITIONAL` |
| Decimals | `18` |
| Whole-token supply | `1,000,000,000` |
| Supply in smallest units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None (`[]`) |
| Constructor value | `0` ETH |
| Initial recipient | Immediate deployer (`msg.sender`) |
| Launch chain | Ethereum, chain ID `1` |
| Compiler | Solidity `0.8.26` |
| EVM target | Cancun |
| Optimizer | Enabled, 200 runs |
| Metadata bytecode hash | `none` |

The constructor calls `_mint` exactly once. When the launch factory creates the token, the factory receives the entire supply; the transaction sender is not substituted for the factory. Creation requires no external calls, supplied addresses, libraries to link, or initialization step. Deploy the compiled creation bytecode for `src/ConditionalsIMD.sol:ConditionalsIMD` directly, without a proxy. The artifact is `out/ConditionalsIMD.sol/ConditionalsIMD.json`.

`INITIAL_SUPPLY` is the fixed supply constant in smallest units. There are no application contracts or additional configurable parameters. The token does not encode distribution recipients, pool parameters, or launch economics: the launch factory distributes the tokens after creation. The separate launch process supplies its manifest; this repository does not supply a `launch.json`.

## Behavior and assumptions

The brief specifies a standard token with no additional conditional transfer rules. Transfers are permissionless, deliver the exact amount, and charge no token fee. There are no transfer limits, taxes, burns, rebases, vesting, or exemptions. Zero-value transfers and self-transfers are supported. Transfers to the zero address and approvals of the zero address revert with OpenZeppelin's ERC-6093 custom errors. Insufficient balances or allowances also revert, with all state changes rolled back.

The only operations that move balances are a holder's `transfer` and an approved spender's `transferFrom`. Finite allowances decrease when spent; `type(uint256).max` is the standard unlimited allowance and does not decrease. `approve` replaces an allowance and emits `Approval`; `transferFrom` emits `Transfer` but does not emit an additional `Approval` when spending allowance, following OpenZeppelin v5. A holder using `transferFrom` on their own balance also needs an allowance; `transfer` needs none.

There is no owner, administrator, mint entry point, burn entry point, pause, blacklist, seizure, upgrade, or recovery function. The deployer retains no special authority after deployment. The total supply remains constant for the lifetime of the deployed token. There are no calls to recipients or other external contracts during token operations, and no oracle or off-chain service is needed.

## Build and check

Foundry and Solidity `0.8.26` must be installed by the build environment. Solidity dependencies and their licenses are committed as ordinary files in `lib/`; building and testing need no network once the compiler is installed. Versions and archive checksums are recorded in [DEPENDENCIES.md](DEPENDENCIES.md). Do not run `forge install`.

```sh
forge build
FOUNDRY_FUZZ_SEED=0x223581886e51c4260af1e869b5bbf48c57d4dd85c9cf3969ac3ee3cb545d3476 forge test
forge fmt --check
```

The test suite covers metadata, constructor mint events, direct and factory/CREATE2 deployment, transfers and approvals, smallest and maximum amounts, zero and self-transfers, insufficient funds and authorization, failure rollback, unsupported administration calls, and exact launch distribution and claim transfers. The four fuzz tests each use 1,024 cases. The stateful invariant test uses 128 sequences of 64 operations and compares balances and allowances against an independent ledger, including failed spending attempts and unlimited allowances. Tests use only local state and do not read environment variables, RPC endpoints, or files.

The local launch-flow test models token transfers between factory, distributor, pool settlement, requester, and trader accounts. It does not deploy Uniswap or demonstrate an actual swap. The supplied protected tests are reference inputs for the network's separate factory/PoolManager integration checks; they depend on external harness code and launch configuration and are not part of this standalone suite.

## After launch and responsibilities

No owner settings or follow-up initialization calls are needed. IMD's launch process is responsible for deployment through its factory, the manifest, distribution, pool initialization, and source verification. As specified in the assignment, the factory allocates 10% of the supply to its distributor, 80% to the pool, and the remaining 10% to the requester's specified recipient; the token itself mints all 100% to the factory first. These responsibilities remain outside the token.

Holders control their balances and spender approvals. Use bounded approvals appropriate to the intended operation, revoke unused approvals, and account for transaction ordering when replacing an existing allowance (set it to zero and confirm before granting a new allowance). A transaction already executed before revocation cannot be undone. Sending tokens to an inaccessible address, to this token's own address, or to a contract without a withdrawal mechanism can lock them permanently. Ordinary native-ETH transfers revert, and there is no recovery mechanism for forced ETH or other assets sent to the token.

The contributor's validation is compilation, unit tests, fuzz tests, stateful invariants, formatting, and source review against the supplied security reference. Slither and Mythril were not run. These checks are not an independent security audit; the launch process retains responsibility for its independent adversarial review before release. No deployment or broadcast is performed by this project.
