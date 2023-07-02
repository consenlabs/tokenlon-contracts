# GenericSwap

GenericSwap is a general token swapping contract that integrate with different strategy executors. The GS contract is responsible for ensuring the result of a swap is match the order. However, the actual swap is executed by a strategy executor. This design allows fulfilling an order with any combination of swapping protocols. Also, by adjusting payload in off-chain system, it may support new protocol without upgrading contracts.

## Relayer

GS supports submitting a swap by a relayer with user signature. The hash of relayed swap should be recoreded to prevent replay attack.
