# L2Deposit

The `L2Deposit` is a utility contract that helps users to bridge their assets from L1 to supported L2. Users can onboard different L2 without approving tokens to each L2 gateway contract separately.

Currently `L2Deposit` supports following L2 networks:

-   Arbitrum
-   Optimism

## Parameters

| Field              |  Type   | Description                                                                                |
| ------------------ | :-----: | ------------------------------------------------------------------------------------------ |
| L2Identifier       |  enum   | The identifier of L2 network.                                                              |
| l1TokenAddr        | address | The address of token on L1.                                                                |
| l2TokenAddr        | address | The address of token on L2.                                                                |
| sender             | address | The address of sender on L1.                                                               |
| recipient          | address | The address of recipient on L2.                                                            |
| arbitrumRefundAddr | address | The address for arbitrum refund (if the eventual gas cost is less than the pre-paid gas).  |
| amount             | uint256 | The amount of asset that is being bridged.                                                 |
| salt               | uint256 | A random number to avoid replay attack.                                                    |
| expiry             | uint256 | The timestamp of the expiry.                                                               |
| data               |  bytes  | The abi-encoded meta data. Differnt L2 network may have different data schema.             |
