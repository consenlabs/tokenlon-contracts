# TokenCollector

`TokenCollector` is an abstract contract designed to handle various token collection mechanisms. It supports different methods of token transfer, allowing flexibility in interacting with Tokenlon and other token standards.

When interacting with Tokenlon, users can select one of the supported approval schemes and provide the corresponding parameters in the data field (encoded in bytes). The first byte of this data indicates the type of the scheme, followed by the encoded data specific to that type.

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
