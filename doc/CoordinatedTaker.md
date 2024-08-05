# CoordinatedTaker

CoordinatedTaker is a conditional taker contract of LimitOrderSwap. It adds a fill permission design on the top of it. A permission of fill is issued by a coordinator with signature. If a user wants to fill an order, he needs to apply for the fill permission and submit the fill with it. The coordinator will manage the available amount of each orders and only issue fill permission when the pending available amount is enough. It helps avoiding fill collision and makes off-chain order canceling possible.
