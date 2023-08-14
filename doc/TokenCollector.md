# TokenCollector

In Tokenlon V6, multiple schemes of token approval is supported. TokenCollector is an abstract contract that handles different ways of token transfering. When interacting with Tokenlon, user can choose one of supported approving scheme and prepare the corresponded Tokenlon permit parameter (in bytes). The first byte of the permit indicate the type and the rest are encoded data with type specific structure.

```
// ***********************************
// | 1 byte |        n bytes         |
// -----------------------------------
// |  type  |      encoded data      |
// ***********************************
```

Supported scheme:

1. Direct approve Tokenlon's contract
2. ERC-2612 permit
3. Tokenlon AllowanceTarget
4. Uniswap Permit2
