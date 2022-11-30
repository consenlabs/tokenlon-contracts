# SignatureValidator

Tokenlon accepts multiple signature types in order to support a wide variety of trading scenarios. The `SignatureValidator` is a utility contract providing signature validating implementation for different signature types and it's inherited by every strategy contract.

## Interface

```
function isValidSignature(address _signerAddress, bytes32 _hash, bytes memory _data, bytes memory _sig) returns (bool);
```

The input of the validating function includes the data and the corresponded hash of it, as well as a signer address and the signature. It will return a boolean representing whether the signature is legitimate or not. The signature is encoded with a type so the proper validating method can be applied accordingly.

## Signature Format

The signature is concatenated with one byte of the type value at the end.

```
// ********************************************
// |           n bytes          |   1 byte   |
// --------------------------------------------
// |        raw signaute        |  sig type  |
// ********************************************
```

## Signature Type

Tokenlon supports following signature type

| Type          | Value | Description                                                                                                            |
| ------------- | :---: | ---------------------------------------------------------------------------------------------------------------------- |
| EIP712        | 0x02  | The standard EIP-712 signature.                                                                                        |
| EthSign       | 0x03  | The standard EIP-191 signature.                                                                                        |
| WalletBytes   | 0x04  | This type is for contract wallet which is similar to EIP-1271 but takes `bytes data` and `bytes sig` as input instead. |
| WalletBytes32 | 0x05  | The standard EIP-1271 signature.                                                                                       |
| Wallet        | 0x06  | (DEPRECATED) This type is similar to EIP-1271 but takes `bytes32 hash`, `address walletAddress` and `bytes sig` as input.    |
