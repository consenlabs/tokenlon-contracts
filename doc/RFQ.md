# RFQ

RFQ (Request For Quote) is a contract that settles a trade between two parties. Normally it requires an off-chain quoting system which provides quotes and signatures from certain makers. A user may request for a quote of a specific trading pair and size. Upon receiving the request, any maker willing to trade can respond with a quote to the user. If the user accepts it, then both parties will sign the trading order and submit the order with signatures to the RFQ contract. After verifying signatures, the RFQ contract will transfer tokens between user and maker accordingly.


## Order option flags

There are two options that the maker of a RFQ offer can set. The option flags is a uint256 field in the offer.
- Partial fill : Whether the Offer can be filled partially or not (but once).
- Contract call : Whether the Offer can be filled by a contract or not.

## Relayer

RFQ supports submitting a trade by a relayer with user signature. The hash of relayed trade should be recoreded to prevent replay attack.

## Fee

Some portion of maker asset of an order will be deducted as protocol fee. The fee will be transfered to `feeCollector` during the settlement. Each order may have different fee factor, it depends on the characteristic of an order.
