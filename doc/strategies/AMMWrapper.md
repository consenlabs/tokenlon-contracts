# AMMWrapper

The `AMMWrapper` contract is a portal for user to interact with multiple AMM protocols. A user can specify any pair in any size with a suppported AMM protocol address as an order and submit it to Tokenlon. The first step is transferring tokens from user in order to swap with AMM. After the swap, the result is then compared with the original order. If the result does not meet the requirement specified in the order, then the transaction is reverted. The `AMMWrapperWithPath` is a newer version of `AMMWrapper` which allows user to speicfy swapping path.

Currently `AMMWrapperWithPath` supports following AMM protocols:

-   Uniswap v2/v3
-   Sushiswap
-   Balancer v2
-   Curve v1/v2 (only part of the pools)

## Order Format

| Field            |  Type   | Description                                                         |
| ---------------- | :-----: | ------------------------------------------------------------------- |
| makerAddr        | address | The address of the AMM protocol.                                    |
| takerAssetAddr   | address | The address of taker token.                                         |
| makerAssetAddr   | address | The address of maker token.                                         |
| takerAssetAmount | uint256 | The amount of taker token.                                          |
| makerAssetAmount | uint256 | The amount of maker token.                                          |
| userAddr         | address | The address of the user.                                            |
| receiverAddr     | address | The address of the token receiver. It may differ from user address. |
| salt             | uint256 | A random number included in an order to avoid replay attack.        |
| deadline         | uint256 | The timestamp of the expiry.                                        |

## Relayer

Tokenlon provides a relaying service for `AMMWrapper` and `AMMWrapperWithPath` transaction. A user can also choose submitting trasanction by themselves. However, official relayers can adjust fee factor dynamically in order to reflect the network congestion but normal users can't.

## Fee

Some portion of the output from AMM will be deducted as protocol fee. The fee will be transfered to `feeCollector` during the settlement. The dynamic fee factor is obtained by `_feeFactor` parameter but for those self-submitted transactions, it will be replaced by the `defaultFeeFactor` of the contract.

## Raw ETH

Each AMM protocol may support either WETH or ETH. The `AMMWrapperWithPath` contract provides flexibilities when it comes to an order with taker asset or maker asset is ETH or WETH. A user can choose whether ETH or WETH as the input and ouptut for such order. It should be specified in the order and the `AMMWrapperWithPath` contract will handle WETH wrap/unwrap if needed.

# AMMQuoter

The `AMMQuoter` contract is a read-only contract providing quotes from different AMM protocols. An reference quote is required when creating an order since AMM swap is always successful but the price varies. By integrating supported AMM protocols, the `AMMQuoter` can provide quotes in a single contract call which simplify the complexity of order creation and reduce the number of RPC call as well.
