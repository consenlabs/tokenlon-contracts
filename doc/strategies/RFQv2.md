# RFQv2

The RFQv2 is a contract that settles a trade between two parties. Normally it requires an off-chain quoting system which provides quotes and signatures from certain makers. A user may request for a quote of a specific trading pair and size. Upon receiving the request, any maker willing to trade can respond with a quote to the user. If the user accepts it, then both parties will sign the trading details and submit the order with signatures to the RFQv2 contract. After verifying signatures, the RFQv2 contract will transfer tokens between user and maker accordingly.

## Token allowance

The main difference between RFQv2 and previous RFQ is how token allownace is managed. The RFQv2 now supports multiple forms of token allownace in order to cover different security assumptions at the same time. A RFQv2 trade should be submitted with sufficient allownace info to specify how tokens should be transfered between two sides.

### List of supported allowance form

-   Approval on Tokenlon's Allowance Target
-   Approval on RFQv2 contract
-   Approval on Uniswap Permit2
-   Native token permit

## Offer Format

| Field            |  Type   | Description                                                                        |
| ---------------- | :-----: | ---------------------------------------------------------------------------------- |
| taker            | address | The address of the taker of an offer. An offer can be filled only by this address. |
| maker            | address | The address of the maker of an offer.                                              |
| takerToken       | address | The address of taker token.                                                        |
| takerTokenAmount | uint256 | The amount of taker token.                                                         |
| makerToken       | address | The address of maker token.                                                        |
| makerTokenAmount | uint256 | The amount of maker token.                                                         |
| expiry           | uint256 | The timestamp of the expiry.                                                       |
| salt             | uint256 | A random number included in an offer to avoid replay attack.                       |

## Signature

The maker of an offer should provide signature of the `Offer` struct to authorize the maker side of the trade. While the taker should sign the `RFQOrder` struct which is the `Offer` struct plus `recipient` and `feeFactor`.

## Fee & Relayer

Some portion of maker token of an offer will be deducted as protocol fee. The fee will be transfered to `feeCollector` during the settlement. Each offer may have different fee factor which is provided by Tokenlon's quoting system. Only those trades with proper `feeFactor` will be accepted by Tokenlon's relayers. A user could submit the trade without relayer and therefore the `feeFactor` is zero in such case.

## WETH

If the `makerToken` or `takerToken` of an offer is WETH, then RFQv2 contract will unwrap it and send ETH instead.

## Avoid replay attack

An offer can only be filled once. Therefore, the hash of a filled offer will be recorded on chain to prevent replay attack.
