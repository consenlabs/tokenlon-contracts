# SmartOrderStrategy

SmartOrderStrategy is a strategy executor of a generic swap. It is designed to be called by the `GenericSwap contract` and performs swaps according to the provided payload. This contract should not hold any significant token balance or require token approvals, as it can execute arbitrary calls. Additionally, the `executeStrategy` function is restricted to being called only by the GenericSwap contract.

## Gas Saving Technical

SmartOrderStrategy retains 1 wei of the maker token at the end of each swap transaction. This practice avoids repeatedly clearing the token balance to zero, as the EVM charges different gas fees for various storage states. By preventing frequent resets to zero, this approach effectively reduces gas consumption.
