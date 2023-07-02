# SmartOrderStrategy

SmartOrderStrategy is a strategy executor of a generic swap. It should be called by GenericSwap contract and preform any swaps according to provided payload. This contract should not has any balance or token approval since it could perform any arbitary calls. Also the `executeStrategy` function is only allowed to be called by GenericSwap contract.
