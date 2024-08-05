# GenericSwap

GenericSwap is a general token swapping contract designed to integrate with various strategy executors (e.g. the `SmartOrderSwap` contract). The GenericSwap contract is responsible for ensuring a result of a swap is match the order. However, the actual swap is executed by a strategy executor. This design allows fulfilling an order with any combination of swapping protocols. Also, by adjusting payload in our off-chain system, it may support new protocol without upgrading contracts.

## Gas Saving Technical

GenericSwap retains 1 wei of the maker token at the end of each swap transaction. This practice avoids repeatedly clearing the token balance to zero, as the EVM charges different gas fees for various storage states. By preventing frequent resets to zero, this approach effectively reduces gas consumption.

## Relayer

The GenericSwap contract allows for trade submissions by a relayer with user's signatures. To prevent replay attacks, the hash of the relayed trade is recorded.
