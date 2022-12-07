# LimitOrder

The `LimitOrder` contract provides order book style trading functionalities which is similar to what centralized exchange does. Orders can be queried from the off-chain order book system and then be filled on chain. Also, it supports order cancelling and partially fill. The `LimitOrder` contract shares the benefit from the infrastructure of Tokenlon which allow users to create an order without depositing tokens first. Tokens are transferred between taker and maker only when the order gets filled on chain. This design provides the certainty of price for maker while maintaining filling flexibilities for taker at the same time.

Besides the traditional taker scenario, an order can also be satisfied by liquidity from a supported AMM protocol. It relies on relayer(EOA) to match the price of AMM protocols and the opened orders. In order to incentivize relayers to participate, the difference of the price is considered as the profit of a relayer.

To avoid multiple filling transactions for the same order at the same time and some of them failed due to insufficient amount, the coordinator design is introduced. The idea is that every fill should be signed by a coordinator so all the fills can be executed successfully.

## Order Format

| Field            |  Type   | Description                                                                     |
| ---------------- | :-----: | ------------------------------------------------------------------------------- |
| makerToken       | address | The address of the maker token.                                                 |
| takerToken       | address | The address of the taker token.                                                 |
| makerTokenAmount | uint256 | The amount of the maker token.                                                  |
| takerTokenAmount | uint256 | The amount of the taker token.                                                  |
| maker            | address | The address of the maker.                                                       |
| taker            | address | The address of the taker. Set to zero address if no specific taker is assigned. |
| salt             | uint256 | A random number included in an order to avoid replay attack.                    |
| expiry           | uint64  | The timestamp of the expiry.                                                    |

## Order Cancelling

If a maker wants to cancel an opened order, a special signature is required. More specifically, the maker should modify the original order with `takerTokenAmount` set to zero and sign it. By submitting cancelling signature to the contract, the original order is marked as canceled which can not be filled anymore.

## Fee

There are totally three different fee factors in `LimitOrder` contract. For `fillByTrader` scenario, `makerFeeFactor` and `takerFeeFactor` are applied to calculate two kinds of fees. For `fillByProtocol` case, the `takerFeeFactor` is applied to the taker asset as well. However, there's another `profitFeeFactor` is applied to the profit of the relayer. All of the fees will be transferred to `feeCollector` during the settlement.
