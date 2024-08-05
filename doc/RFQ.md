# RFQ

The RFQ (Request For Quote) contract facilitates the settlement of trades between two parties: a market maker and an user. We provide an off-chain quoting system that handles the quoting process. Users can request quotes for specific trading pairs and sizes. Upon receiving a request, any interested maker can provide a quote to the user. If the user accepts the quote, both parties will sign the trading order and submit it ot the RFQ contract along with their signatures. The RFQ contract verifies the signatures and executes the token transfers between the user and the market maker.

## Order option flags

The maker of an RFQ offer can specify certain options using a `uint256` field in the offer, referred to as option flags:

-   `FLG_ALLOW_CONTRACT_SENDER` : Determines whether the RFQ offer can be filled by a contract.
-   `FLG_ALLOW_PARTIAL_FILL` : Whether a RFQ offer can be filled partially or not (but once).
-   `FLG_MAKER_RECEIVES_WETH` : Specifies whether a market maker is willing to receive WETH from a RFQ offer.

## Relayer

The RFQ contract allows for trade submissions by a relayer with user's signatures. To prevent replay attacks, the hash of the relayed trade is recorded.

## Fee

A portion of the maker's asset in the order will be deducted as a protocol fee. This fee is transferred to the feeCollector during settlement.

The fee factor is composed of two parts:

1. Protocol Fee
2. Gas Fee

If a relayer submits the trade on-chain, the gas fee will be adjusted according to the on-chain conditions at the time of the transaction.
