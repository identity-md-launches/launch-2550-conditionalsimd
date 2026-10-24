# ConditionalsIMD tests

Run the suite using the verifier's seed:

```sh
forge build
FOUNDRY_FUZZ_SEED=0x223581886e51c4260af1e869b5bbf48c57d4dd85c9cf3969ac3ee3cb545d3476 forge test
```

All imports use the project's existing vendored dependencies. No fork, RPC, FFI,
additional dependency, or configuration change is required.

| File | Coverage |
| --- | --- |
| `ConditionalsIMD.t.sol` | Existing constructor, metadata, mint event, factory deployment, ERC-20 transfers, approvals, failure cases, and absence of administrative entry points. |
| `ConditionalsIMD.properties.t.sol` | Finite versus unlimited approval boundaries, revocation after refilling balances, independent spenders, rollback on rejected calls, self approval, caller authorization, transfer round trips, and split versus combined transfers. |
| `ConditionalsIMD.invariant.t.sol` | Random sequences across four actors with independent balance and allowance accounting, plus a deterministic sequence exercising every handler action. |

The invariant handler targets nine actions: transfer, approve, transferFrom,
revoke, overspend through transferFrom, transfer above the balance, transfer to
zero, approve zero, and transferFrom to zero. Expected failures are caught and
checked against the complete custom error. Unexpected reverts fail the campaign.
The ledger remains unchanged for rejected actions, so the next invariant check
also verifies rollback. Successful actions update the ledger using the requested
amount rather than copying balances or allowances from the token.

After every action, the invariant checks the exact fixed supply, unchanged
metadata, conservation across the four actors, each actor's balance, all sixteen
actor-to-actor allowances, and empty zero-address balances and allowances. The
closed actor set makes the sum exhaustive for this campaign. Transfers to the
token contract and arbitrary recipients are covered separately by ordinary
tests. The handler never fabricates balances with storage writes or token minting.

The invariant settings are inline: 256 runs of 128 calls, with failure on
unexpected reverts. The added stateless properties run 1,024 cases each. Known
boundaries also have deterministic examples: zero, one smallest unit, the entire
supply, one above the balance, and the maximum finite and unlimited approvals.

The existing launch-distribution test checks exact ERC-20 transfers between local
participants. It does not execute a real Uniswap pool or replace the supplied
protected launch checks.
