// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "contracts/AMMWrapper.sol";
import "contracts-test/forkMainnet/AMMWrapper/Setup.t.sol";
import "contracts-test/utils/BalanceSnapshot.sol";

contract TestAMMWrapperCollectFee is TestAMMWrapper {
    using BalanceSnapshot for BalanceSnapshot.Snapshot;

    function testAMMOutNotEnoughForOrderPlusFee() public {
        // should fail if order.makerAssetAmount = expectedOutAmount for non-zero fee factor case
        // in this case, AMMWrapper will use higher expected amount(plus fee) which will cause revert
        uint256 feeFactor = 1000;
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        uint256 expectedOutAmount = ammQuoter.getMakerOutAmount(order.makerAddr, order.takerAssetAddr, order.makerAssetAddr, order.takerAssetAmount);
        order.makerAssetAmount = expectedOutAmount;
        bytes memory sig = _signTrade(userPrivateKey, order);
        bytes memory payload = _genTradePayload(order, feeFactor, sig);

        vm.expectRevert("UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT");
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

        BalanceSnapshot.Snapshot memory feeCollectorMakerAsset = BalanceSnapshot.take(feeCollector, order.makerAssetAddr);

        vm.prank(relayer, relayer);
        userProxy.toAMM(payload);

        feeCollectorMakerAsset.assertChange(int256(fee));
    }

    function testCollectFeeWithWETH() public {
        uint256 feeFactor = 100;
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        order.makerAssetAddr = ETH_ADDRESS;
        uint256 expectedOutAmount = ammQuoter.getMakerOutAmount(order.makerAddr, order.takerAssetAddr, order.makerAssetAddr, order.takerAssetAmount);
        // order should align with user's perspective
        // therefore it should deduct fee from expectedOutAmount as the makerAssetAmount in order
        uint256 fee = (expectedOutAmount * feeFactor) / BPS_MAX;
        order.makerAssetAmount = expectedOutAmount - fee;
        bytes memory sig = _signTrade(userPrivateKey, order);
        bytes memory payload = _genTradePayload(order, feeFactor, sig);

        address feeTokenAddress = WETH_ADDRESS; // AMM other than Curve returns WETH instead of ETH
        BalanceSnapshot.Snapshot memory feeCollectorMakerAsset = BalanceSnapshot.take(feeCollector, feeTokenAddress);

        vm.prank(relayer, relayer);
        userProxy.toAMM(payload);

        feeCollectorMakerAsset.assertChange(int256(fee));
    }

    function testCollectFeeWithETH() public {
        uint256 feeFactor = 100;
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        order.makerAddr = CURVE_ANKRETH_POOL_ADDRESS;
        order.takerAssetAddr = ANKRETH_ADDRESS;
        order.takerAssetAmount = 0.01 ether;
        order.makerAssetAddr = ETH_ADDRESS;
        uint256 expectedOutAmount = ammQuoter.getMakerOutAmount(order.makerAddr, order.takerAssetAddr, order.makerAssetAddr, order.takerAssetAmount);
        // order should align with user's perspective
        // therefore it should deduct fee from expectedOutAmount as the makerAssetAmount in order
        uint256 fee = (expectedOutAmount * feeFactor) / BPS_MAX;
        order.makerAssetAmount = expectedOutAmount - fee;
        bytes memory sig = _signTrade(userPrivateKey, order);
        bytes memory payload = _genTradePayload(order, feeFactor, sig);

        address feeTokenAddress = ETH_ADDRESS; // Curve ETH/ANKRETH pool returns ETH instead of WETH
        BalanceSnapshot.Snapshot memory feeCollectorMakerAsset = BalanceSnapshot.take(feeCollector, feeTokenAddress);

        vm.prank(relayer, relayer);
        userProxy.toAMM(payload);

        feeCollectorMakerAsset.assertChange(int256(fee));
    }

    function testFeeFactorOverwrittenWithDefault() public {
        // set local feeFactor higher than default one to avoid insufficient output from AMM
        uint256 feeFactor = ammWrapper.defaultFeeFactor() + 1000;
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        uint256 expectedOutAmount = ammQuoter.getMakerOutAmount(order.makerAddr, order.takerAssetAddr, order.makerAssetAddr, order.takerAssetAmount);
        // set makerAssetAmount = expectedOutAmount - expectedFee
        order.makerAssetAmount = expectedOutAmount - ((expectedOutAmount * feeFactor) / BPS_MAX);
        bytes memory sig = _signTrade(userPrivateKey, order);
        bytes memory payload = _genTradePayload(order, feeFactor, sig);
        uint256 actualFee = (expectedOutAmount * ammWrapper.defaultFeeFactor()) / BPS_MAX;

        BalanceSnapshot.Snapshot memory feeCollectorMakerAsset = BalanceSnapshot.take(feeCollector, order.makerAssetAddr);

        vm.expectEmit(true, true, true, true);
        emit Swapped(
            "Uniswap V2",
            AMMLibEIP712._getOrderHash(order),
            order.userAddr,
            false, // not relayed
            order.takerAssetAddr,
            order.takerAssetAmount,
            order.makerAddr,
            order.makerAssetAddr,
            order.makerAssetAmount,
            order.receiverAddr,
            expectedOutAmount - actualFee,
            ammWrapper.defaultFeeFactor() // default fee factor will be applied
        );
        userProxy.toAMM(payload);

        feeCollectorMakerAsset.assertChange(int256(actualFee));
    }
}
