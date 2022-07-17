// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "contracts/AMMWrapper.sol";
import "contracts-test/forkMainnet/AMMWrapper/Setup.t.sol";
import "contracts-test/utils/BalanceSnapshot.sol";

contract TestAMMWrapperCollectFee is TestAMMWrapper {
    using BalanceSnapshot for BalanceSnapshot.Snapshot;

    function testFailedIfMakerAssetAmountNotDeductFee() public {
        // should fail if order.makerAssetAmount = expectedOutAmount for non-zero fee factor case
        // in this case, AMMWrapper will use higher expected amount(plus fee) which will cause revert
        uint256 feeFactor = 100;
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        uint256 expectedOutAmount = ammQuoter.getMakerOutAmount(order.makerAddr, order.takerAssetAddr, order.makerAssetAddr, order.takerAssetAmount);
        order.makerAssetAmount = expectedOutAmount;
        bytes memory sig = _signTrade(userPrivateKey, order);
        bytes memory payload = _genTradePayload(order, feeFactor, sig);

        vm.expectRevert("AMMWrapper: not the operator");
        vm.prank(relayer, relayer);
        userProxy.toAMM(payload);
    }

    function testCollectFeeForSwap() public {
        uint256 feeFactor = 100;
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        uint256 expectedOutAmount = ammQuoter.getMakerOutAmount(order.makerAddr, order.takerAssetAddr, order.makerAssetAddr, order.takerAssetAmount);
        // order should align with user's perspective
        // therefore it should deduct fee from expectedOutAmount as the makerAssetAmount in order
        uint256 fee = (expectedOutAmount * feeFactor) / BPS_MAX;
        order.makerAssetAmount = expectedOutAmount - fee;
        bytes memory sig = _signTrade(userPrivateKey, order);
        bytes memory payload = _genTradePayload(order, feeFactor, sig);

        BalanceSnapshot.Snapshot memory ammWrapperMakerAsset = BalanceSnapshot.take(address(ammWrapper), order.makerAssetAddr);

        vm.prank(relayer, relayer);
        userProxy.toAMM(payload);

        ammWrapperMakerAsset.assertChange(int256(fee));
    }

    function testFeeFactorOverwrittenWithDefault() public {
        // set local feeFactor higher than default one to avoid insufficient output from AMM
        uint256 feeFactor = ammWrapper.defaultFeeFactor() + 1000;
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        uint256 expectedOutAmount = ammQuoter.getMakerOutAmount(order.makerAddr, order.takerAssetAddr, order.makerAssetAddr, order.takerAssetAmount);
        uint256 fee = (expectedOutAmount * feeFactor) / BPS_MAX;
        order.makerAssetAmount = expectedOutAmount - fee;
        bytes memory sig = _signTrade(userPrivateKey, order);
        bytes memory payload = _genTradePayload(order, feeFactor, sig);

        BalanceSnapshot.Snapshot memory ammWrapperMakerAsset = BalanceSnapshot.take(address(ammWrapper), order.makerAssetAddr);

        userProxy.toAMM(payload);

        uint256 actualFee = (expectedOutAmount * ammWrapper.defaultFeeFactor()) / BPS_MAX;
        ammWrapperMakerAsset.assertChange(int256(actualFee));
    }
}
