// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "contracts-test/forkMainnet/AMMWrapper/Setup.t.sol";
import "contracts-test/utils/BalanceSnapshot.sol";

contract TestAMMWrapperSubsidize is TestAMMWrapper {
    using SafeERC20 for IERC20;
    using BalanceSnapshot for BalanceSnapshot.Snapshot;

    function testCannotSubsidizeIfSwapFailed() public {
        // Set subsidy factor to 0
        ammWrapper.setSubsidyFactor(0);

        uint256 feeFactor = 5;
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        uint256 expectedOutAmount = ammQuoter.getMakerOutAmount(order.makerAddr, order.takerAssetAddr, order.makerAssetAddr, order.takerAssetAmount);
        // Increase `expectedOutAmount` so received amount is less than `expectedOutAmount` but
        // since subsidy factor is zero, `expectedOutAmount` would be the minimum receive amount requested to AMM
        // and result in failed swap.
        uint256 increasedExpectedOutAmount = (expectedOutAmount * (BPS_MAX + 1)) / BPS_MAX;
        order.makerAssetAmount = increasedExpectedOutAmount;
        bytes memory sig = _signTrade(userPrivateKey, order);
        bytes memory payload = _genTradePayload(order, feeFactor, sig);

        vm.expectRevert("UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT");
        vm.prank(relayer, relayer);
        userProxy.toAMM(payload);
    }

    function testCannotSubsidizeWithoutEnoughBalance() public {
        uint256 feeFactor = 5;
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        uint256 expectedOutAmount = ammQuoter.getMakerOutAmount(order.makerAddr, order.takerAssetAddr, order.makerAssetAddr, order.takerAssetAmount);
        // Increase `expectedOutAmount` so received amount is less than `expectedOutAmount`.
        // The amount difference should be in the subsidy range since `expectedOutAmount`
        // is increased by 1 BPS but subsidy factor is 3 BPS
        uint256 increasedExpectedOutAmount = (expectedOutAmount * (BPS_MAX + 1)) / BPS_MAX;
        order.makerAssetAmount = increasedExpectedOutAmount;
        bytes memory sig = _signTrade(userPrivateKey, order);
        bytes memory payload = _genTradePayload(order, feeFactor, sig);

        vm.expectRevert("AMMWrapper: not enough savings to subsidize");
        vm.prank(relayer, relayer);
        userProxy.toAMM(payload);
    }

    function testCannotSubsidizeExceedMaxSubsidyAmount() public {
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        uint256 expectedOutAmount = ammQuoter.getMakerOutAmount(order.makerAddr, order.takerAssetAddr, order.makerAssetAddr, order.takerAssetAmount);
        // Increase `expectedOutAmount` so received amount is less than `expectedOutAmount`
        uint256 increasedExpectedOutAmount = (expectedOutAmount * (BPS_MAX + 2)) / BPS_MAX;
        order.makerAssetAmount = increasedExpectedOutAmount;
        bytes memory sig = _signTrade(userPrivateKey, order);

        // Set fee factor to 0
        uint256 feeFactor = 0;
        vm.expectRevert("AMMWrapper: amount difference larger than subsidy amount");
        vm.prank(relayer, relayer);
        bytes memory payload = _genTradePayload(order, feeFactor, sig);
        userProxy.toAMM(payload);

        // Set fee factor to 1
        feeFactor = 1;
        vm.expectRevert("AMMWrapper: amount difference larger than subsidy amount");
        vm.prank(relayer, relayer);
        payload = _genTradePayload(order, feeFactor, sig);
        userProxy.toAMM(payload);
    }

    function testCannotSubsidizeByNotRelayer() public {
        uint256 feeFactor = 5;
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        uint256 expectedOutAmount = ammQuoter.getMakerOutAmount(order.makerAddr, order.takerAssetAddr, order.makerAssetAddr, order.takerAssetAmount);
        // Increase `expectedOutAmount` so received amount is less than `expectedOutAmount`
        uint256 increasedExpectedOutAmount = (expectedOutAmount * (BPS_MAX + 2)) / BPS_MAX;
        order.makerAssetAmount = increasedExpectedOutAmount;
        bytes memory sig = _signTrade(userPrivateKey, order);
        bytes memory payload = _genTradePayload(order, feeFactor, sig);

        vm.expectRevert("UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT");
        userProxy.toAMM(payload);
    }

    function testSubsidize() public {
        uint256 feeFactor = 5;
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        uint256 expectedOutAmount = ammQuoter.getMakerOutAmount(order.makerAddr, order.takerAssetAddr, order.makerAssetAddr, order.takerAssetAmount);
        // Increase `expectedOutAmount` so received amount is less than `expectedOutAmount`
        uint256 increasedExpectedOutAmount = (expectedOutAmount * (BPS_MAX + 2)) / BPS_MAX;
        order.makerAssetAmount = increasedExpectedOutAmount;
        bytes memory sig = _signTrade(userPrivateKey, order);
        bytes memory payload = _genTradePayload(order, feeFactor, sig);

        // Supply AMMWrapper with maker token so it can subsidize
        vm.prank(user);
        IERC20(order.makerAssetAddr).safeTransfer(address(ammWrapper), order.makerAssetAmount);
        BalanceSnapshot.Snapshot memory ammWrapperMakerAsset = BalanceSnapshot.take(address(ammWrapper), order.makerAssetAddr);

        vm.prank(relayer, relayer);
        userProxy.toAMM(payload);

        ammWrapperMakerAsset.assertChangeGt(-int256(0));
    }
}
