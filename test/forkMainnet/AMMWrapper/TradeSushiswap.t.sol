// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "test/forkMainnet/AMMWrapper/Setup.t.sol";
import "test/utils/BalanceSnapshot.sol";

contract TestAMMWrapperTradeSushiswap is TestAMMWrapper {
    using BalanceSnapshot for BalanceSnapshot.Snapshot;

    function testTradeSushiswap() public {
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        order.makerAddr = SUSHISWAP_ADDRESS;
        order.makerAssetAddr = ETH_ADDRESS;
        order.makerAssetAmount = 0.001 ether;
        bytes memory sig = _signTrade(userPrivateKey, order);
        bytes memory payload = _genTradePayload(order, DEFAULT_FEE_FACTOR, sig);

        uint256 expectedOutAmount = ammQuoter.getMakerOutAmount(order.makerAddr, order.takerAssetAddr, order.makerAssetAddr, order.takerAssetAmount);
        uint256 actualFee = (expectedOutAmount * DEFAULT_FEE_FACTOR) / LibConstant.BPS_MAX;
        uint256 settleAmount = expectedOutAmount - actualFee;

        BalanceSnapshot.Snapshot memory userTakerAsset = BalanceSnapshot.take(user, order.takerAssetAddr);
        BalanceSnapshot.Snapshot memory userMakerAsset = BalanceSnapshot.take(user, order.makerAssetAddr);
        // Collect fee in WETH directly
        BalanceSnapshot.Snapshot memory feeCollectorMakerAsset = BalanceSnapshot.take(feeCollector, WETH_ADDRESS);

        userProxy.toAMM(payload);

        userTakerAsset.assertChange(-int256(order.takerAssetAmount));
        userMakerAsset.assertChange(int256(settleAmount));
        feeCollectorMakerAsset.assertChange(int256(actualFee));
    }
}
