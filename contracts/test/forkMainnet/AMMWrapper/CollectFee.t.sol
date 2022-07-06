// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "contracts-test/forkMainnet/AMMWrapper/Setup.t.sol";
import "contracts-test/utils/BalanceSnapshot.sol";

contract TestAMMWrapperCollectFee is TestAMMWrapper {
    using BalanceSnapshot for BalanceSnapshot.Snapshot;

    // Received same amount as expected min amount
    function testCollectFeeIfReceivedSameAsMinOut() public {
        uint256 feeFactor = 5;
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        uint256 expectedOutAmount = ammQuoter.getMakerOutAmount(order.makerAddr, order.takerAssetAddr, order.makerAssetAddr, order.takerAssetAmount);
        order.makerAssetAmount = expectedOutAmount;
        bytes memory sig = _signTrade(userPrivateKey, order);
        bytes memory payload = _genTradePayload(order, feeFactor, sig);

        BalanceSnapshot.Snapshot memory ammWrapperMakerAsset = BalanceSnapshot.take(address(ammWrapper), order.makerAssetAddr);

        userProxy.toAMM(payload);

        ammWrapperMakerAsset.assertChange(int256(0));
    }

    // Received more than expected min amount
    function testCollectFeeIfReceivedMoreThanMinOut() public {
        uint256 feeFactor = 5;
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        uint256 expectedOutAmount = ammQuoter.getMakerOutAmount(order.makerAddr, order.takerAssetAddr, order.makerAssetAddr, order.takerAssetAmount);
        // Reduce `expectedOutAmount` so received amount is more than `expectedOutAmount` and
        // the amount difference is enough for us to collect fee
        uint256 reducedExpectedOutAmount = (expectedOutAmount * (BPS_MAX - 2 * feeFactor)) / BPS_MAX;
        order.makerAssetAmount = reducedExpectedOutAmount;
        bytes memory sig = _signTrade(userPrivateKey, order);
        bytes memory payload = _genTradePayload(order, feeFactor, sig);

        BalanceSnapshot.Snapshot memory ammWrapperMakerAsset = BalanceSnapshot.take(address(ammWrapper), order.makerAssetAddr);

        userProxy.toAMM(payload);

        ammWrapperMakerAsset.assertChangeGt(int256(0));
    }

    // Received more than expected min amount but not enough
    function testCollectFeeIfReceivedMoreThanMinOutButNotEnough() public {
        uint256 feeFactor = 5;
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        uint256 expectedOutAmount = ammQuoter.getMakerOutAmount(order.makerAddr, order.takerAssetAddr, order.makerAssetAddr, order.takerAssetAmount);
        // Reduce `expectedOutAmount` so received amount is more than `expectedOutAmount` but
        // the amount difference is not enough for us to collect fee
        uint256 reducedExpectedOutAmount = (expectedOutAmount * (BPS_MAX - feeFactor + 1)) / BPS_MAX;
        order.makerAssetAmount = reducedExpectedOutAmount;
        bytes memory sig = _signTrade(userPrivateKey, order);
        bytes memory payload = _genTradePayload(order, feeFactor, sig);

        BalanceSnapshot.Snapshot memory ammWrapperMakerAsset = BalanceSnapshot.take(address(ammWrapper), order.makerAssetAddr);

        userProxy.toAMM(payload);

        ammWrapperMakerAsset.assertChangeGt(int256(0));
    }
}
