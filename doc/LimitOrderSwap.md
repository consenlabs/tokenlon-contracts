# LimitOrder

The `LimitOrder` contract provides order book style trading functionalities which is similar to what centralized exchange does. Orders can be queried from the off-chain order book system and then be filled on chain. Also, it supports order cancelling and partially fill. The `LimitOrder` contract shares the benefit from the infrastructure of Tokenlon which allow users to create an order without depositing tokens first. Tokens are transferred between taker and maker only when the order gets filled on chain. This design provides the certainty of price for maker while maintaining filling flexibilities for taker at the same time.

A taker can optionally provide extra action parameter in payload which will be executed after maker token settlement. Given the ability to execute an external call, taker can leverage the liquidity of any AMM protocol to fulfill the order or validate the trade execute by external condition checking.

## FullOrKill

The default `fillLimitOrder` function allows the settled taking amount is less than a taker requested. The reason is that it may not be sufficient for the whole request when a trade is actual executed and the rest available taking amount would be the actual taking amount in that case. If a taker wants a non-adjustable taking amount, then the `fillLimitOrderFullOrKill` function should be called instead.

## GroupFill

If a group of orders can be fulfilled by each other, then no external liquiditiy is needed for settling those orders. A user can spot this kind of group with profits so it would be the incentive of searching and submitting it. In some cases, a user may need to add some external liquidity or create some orders so the group can be formed and settled.

## Fee

Some portion of maker asset of an order will be deducted as protocol fee. The fee will be transfered to `feeCollector` during the settlement. Each order may have different fee factor, it depends on the characteristic of an order.
