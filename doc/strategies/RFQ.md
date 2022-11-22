# RFQ

RFQ (Request For Quote) is a contract that settles a trade between two parties. Normally it requires an off-chain quoting system which provides quotes and signaturates from certain makers. A user may request for a quote of a specific trading pair and size. Upon receving the request, any maker willing to trade can respond with a quote to the user. If the user accept it, then both parties will sign the trading order and submit the order with signatures to the RFQ contract. After verifying signatures, the RFQ contract will transfer tokens between user and maker accordingly.

## Order Format

| Field            |  Type   | Description                                                                        |
| ---------------- | :-----: | ---------------------------------------------------------------------------------- |
| takerAddr        | address | The address of the taker of an order. An order can be filled only by this address. |
| makerAddr        | address | The address of the maker of an order.                                              |
| takerAssetAddr   | address | The address of taker token.                                                        |
| makerAssetAddr   | address | The address of maker token.                                                        |
| takerAssetAmount | uint256 | The amount of taker token.                                                         |
| makerAssetAmount | uint256 | The amount of maker token.                                                         |
| receiverAddr     | address | The address of the token receiver. It may differ from taker address.               |
| salt             | uint256 | A random number included in an order to avoid replay attack.                       |
| deadline         | uint256 | The timestamp of the expiry.                                                       |
| feeFactor        | uint256 | The BPS fee factor. This field should be set by the off-chain system.              |

## Fee

Some portion of maker asset of an order will be deducted as protocol fee. The fee will be transfered to `feeCollector` during the settlement. Each order may have different fee factor, it depends on the characteristic of an order.

## WETH

If the `takerAssetAddr` of an order is WETH, then calling contract with ETH is required from user. The RFQ contract will handle the WETH wrapping first before settlement. If the `makerAssetAddr` of an order is WETH, then RFQ contract will first transfer WETH from maker then unwrap and send ETH to the `receiver`.

## Avoid replay attack

An order can only be filled once. Therefore, the hash of a filled order will be recorded on chain to prevent replay attack.
