// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import "contracts-test/forkMainnet/AMMWrapperWithPath/Setup.t.sol";
import "contracts-test/utils/BalanceSnapshot.sol";
import "contracts-test/utils/AMMUtil.sol"; // Using the Encode Data function
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TestAMMWrapperWithPathTradeBalancerV2 is TestAMMWrapperWithPath {
    using BalanceSnapshot for BalanceSnapshot.Snapshot;

    function testCannotTradeBalancerV2NoSwapSteps() public {
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        order.makerAddr = BALANCER_V2_ADDRESS;
        bytes memory sig = _signTrade(userPrivateKey, order);
        address[] memory path = new address[](2);
        path[0] = order.takerAssetAddr;
        path[1] = order.makerAssetAddr;
        IBalancerV2Vault.BatchSwapStep[] memory swapSteps = new IBalancerV2Vault.BatchSwapStep[](0); // Empty SwapSteps
        bytes memory payload = _genTradePayload(order, DEFAULT_FEE_FACTOR, sig, _encodeBalancerData(swapSteps), path);

        vm.expectRevert("AMMWrapper: BalancerV2 requires at least one swap step");
        userProxy.toAMM(payload);
    }

    function testCannotTradeBalancerV2NoPath() public {
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        order.makerAddr = BALANCER_V2_ADDRESS;
        bytes memory sig = _signTrade(userPrivateKey, order);
        address[] memory path = new address[](0); // Empty path
        IBalancerV2Vault.BatchSwapStep[] memory swapSteps = new IBalancerV2Vault.BatchSwapStep[](1);
        swapSteps[0] = IBalancerV2Vault.BatchSwapStep(
            BALANCER_DAI_USDT_USDC_POOL, // poolId
            0, // assetInIndex
            1, // assetOutIndex
            order.takerAssetAmount, // amount
            new bytes(0) // userData
        );
        bytes memory payload = _genTradePayload(order, DEFAULT_FEE_FACTOR, sig, _encodeBalancerData(swapSteps), path);

        vm.expectRevert("AMMWrapper: path length must be at least two");
        userProxy.toAMM(payload);
    }

    function testCannotTradeBalancerV2MismatchAsset() public {
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        order.makerAddr = BALANCER_V2_ADDRESS;
        bytes memory sig = _signTrade(userPrivateKey, order);
        address[] memory path = new address[](3);
        path[0] = order.takerAssetAddr;
        path[1] = address(weth);
        path[2] = order.makerAssetAddr;
        IBalancerV2Vault.BatchSwapStep[] memory swapSteps = new IBalancerV2Vault.BatchSwapStep[](1);
        // AssetIn in first SwapStep (weth) is not taker asset
        swapSteps[0] = IBalancerV2Vault.BatchSwapStep(
            BALANCER_WETH_USDC_POOL, // poolId
            1, // assetInIndex
            2, // assetOutIndex
            order.takerAssetAmount, // amount
            new bytes(0) // userData
        );
        bytes memory payload = _genTradePayload(order, DEFAULT_FEE_FACTOR, sig, _encodeBalancerData(swapSteps), path);

        vm.expectRevert("AMMWrapper: BalancerV2 first step asset in should match taker asset");
        userProxy.toAMM(payload);

        // AssetOut in first SwapStep (weth) is not maker asset
        swapSteps[0].poolId = BALANCER_WETH_DAI_POOL;
        swapSteps[0].assetInIndex = 0;
        swapSteps[0].assetOutIndex = 1;
        payload = _genTradePayload(order, DEFAULT_FEE_FACTOR, sig, _encodeBalancerData(swapSteps), path);

        vm.expectRevert("AMMWrapper: BalancerV2 last step asset out should match maker asset");
        userProxy.toAMM(payload);
    }

    function testTradeBalancerV2SingleHop() public {
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        order.makerAddr = BALANCER_V2_ADDRESS;
        bytes memory sig = _signTrade(userPrivateKey, order);
        address[] memory path = new address[](2);
        path[0] = order.takerAssetAddr;
        path[1] = order.makerAssetAddr;
        IBalancerV2Vault.BatchSwapStep[] memory swapSteps = new IBalancerV2Vault.BatchSwapStep[](1);
        swapSteps[0] = IBalancerV2Vault.BatchSwapStep(
            BALANCER_DAI_USDT_USDC_POOL, // poolId
            0, // assetInIndex
            1, // assetOutIndex
            order.takerAssetAmount, // amount
            new bytes(0) // userData
        );
        bytes memory payload = _genTradePayload(order, DEFAULT_FEE_FACTOR, sig, _encodeBalancerData(swapSteps), path);

        uint256 expectedOutAmount = ammQuoter.getMakerOutAmountWithPath(
            order.makerAddr,
            order.takerAssetAddr,
            order.makerAssetAddr,
            order.takerAssetAmount,
            path,
            _encodeBalancerData(swapSteps)
        );
        uint256 actualFee = (expectedOutAmount * DEFAULT_FEE_FACTOR) / LibConstant.BPS_MAX;
        uint256 settleAmount = expectedOutAmount - actualFee;

        BalanceSnapshot.Snapshot memory userTakerAsset = BalanceSnapshot.take(user, order.takerAssetAddr);
        BalanceSnapshot.Snapshot memory userMakerAsset = BalanceSnapshot.take(user, order.makerAssetAddr);
        BalanceSnapshot.Snapshot memory feeCollectorMakerAsset = BalanceSnapshot.take(feeCollector, order.makerAssetAddr);

        userProxy.toAMM(payload);

        userTakerAsset.assertChange(-int256(order.takerAssetAmount));
        userMakerAsset.assertChange(int256(settleAmount));
        feeCollectorMakerAsset.assertChange(int256(actualFee));
    }

    function testCannotTradeBalancerV2InvalidAmountInSwapSteps() public {
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        order.makerAddr = BALANCER_V2_ADDRESS;
        bytes memory sig = _signTrade(userPrivateKey, order);
        address[] memory path = DEFAULT_MULTI_HOP_PATH;
        IBalancerV2Vault.BatchSwapStep[] memory swapSteps = new IBalancerV2Vault.BatchSwapStep[](2);
        uint256 invalidFirstSwapStepAssetInAmount = order.takerAssetAmount + 1;
        swapSteps[0] = IBalancerV2Vault.BatchSwapStep(
            BALANCER_WETH_USDC_POOL, // poolId
            0, // assetInIndex
            1, // assetOutIndex
            invalidFirstSwapStepAssetInAmount, // amount
            new bytes(0) // userData
        );
        swapSteps[1] = IBalancerV2Vault.BatchSwapStep(
            BALANCER_WETH_DAI_POOL, // poolId
            1, // assetInIndex
            2, // assetOutIndex
            0, // amount
            new bytes(0) // userData
        );
        bytes memory payload = _genTradePayload(order, DEFAULT_FEE_FACTOR, sig, _encodeBalancerData(swapSteps), path);

        vm.expectRevert("AMMWrapper: BalancerV2 cannot swap more than taker asset amount");
        userProxy.toAMM(payload);

        uint256 invalidOtherSwapStepAssetInAmount = 999; // Amount of other SwapSteps must be zero
        swapSteps[0].amount = order.takerAssetAmount; // Restore amount of first SwapStep
        swapSteps[1].amount = invalidOtherSwapStepAssetInAmount;
        payload = _genTradePayload(order, DEFAULT_FEE_FACTOR, sig, _encodeBalancerData(swapSteps), path);

        vm.expectRevert("AMMWrapper: BalancerV2 can only specify amount at first step");
        userProxy.toAMM(payload);
    }

    function testTradeBalancerV2MultiHop() public {
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        order.makerAddr = BALANCER_V2_ADDRESS;
        bytes memory sig = _signTrade(userPrivateKey, order);
        address[] memory path = DEFAULT_MULTI_HOP_PATH;
        IBalancerV2Vault.BatchSwapStep[] memory swapSteps = new IBalancerV2Vault.BatchSwapStep[](2);
        swapSteps[0] = IBalancerV2Vault.BatchSwapStep(
            BALANCER_WETH_USDC_POOL, // poolId
            0, // assetInIndex
            1, // assetOutIndex
            order.takerAssetAmount, // amount
            new bytes(0) // userData
        );
        swapSteps[1] = IBalancerV2Vault.BatchSwapStep(
            BALANCER_WETH_DAI_POOL, // poolId
            1, // assetInIndex
            2, // assetOutIndex
            0, // amount
            new bytes(0) // userData
        );
        bytes memory payload = _genTradePayload(order, DEFAULT_FEE_FACTOR, sig, _encodeBalancerData(swapSteps), path);

        uint256 expectedOutAmount = ammQuoter.getMakerOutAmountWithPath(
            order.makerAddr,
            order.takerAssetAddr,
            order.makerAssetAddr,
            order.takerAssetAmount,
            path,
            _encodeBalancerData(swapSteps)
        );
        uint256 actualFee = (expectedOutAmount * DEFAULT_FEE_FACTOR) / LibConstant.BPS_MAX;
        uint256 settleAmount = expectedOutAmount - actualFee;

        BalanceSnapshot.Snapshot memory userTakerAsset = BalanceSnapshot.take(user, order.takerAssetAddr);
        BalanceSnapshot.Snapshot memory userMakerAsset = BalanceSnapshot.take(user, order.makerAssetAddr);
        BalanceSnapshot.Snapshot memory feeCollectorMakerAsset = BalanceSnapshot.take(feeCollector, order.makerAssetAddr);

        userProxy.toAMM(payload);

        userTakerAsset.assertChange(-int256(order.takerAssetAmount));
        userMakerAsset.assertChange(int256(settleAmount));
        feeCollectorMakerAsset.assertChange(int256(actualFee));
    }

    function testCannotTradeBalancerV2UnsupportedMakerAsset() public {
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        // give an unsurpoted MakerAsset
        // use LON address to test
        order.makerAssetAddr = LON_ADDRESS;
        order.makerAddr = BALANCER_V2_ADDRESS;
        bytes memory sig = _signTrade(userPrivateKey, order);
        address[] memory path = new address[](2);
        path[0] = order.takerAssetAddr;
        path[1] = order.makerAssetAddr;
        IBalancerV2Vault.BatchSwapStep[] memory swapSteps = new IBalancerV2Vault.BatchSwapStep[](1);
        swapSteps[0] = IBalancerV2Vault.BatchSwapStep(
            BALANCER_DAI_USDT_USDC_POOL, // poolId
            0, // assetInIndex
            1, // assetOutIndex
            order.takerAssetAmount, // amount
            new bytes(0) // userData
        );
        bytes memory payload = _genTradePayload(order, DEFAULT_FEE_FACTOR, sig, _encodeBalancerData(swapSteps), path);

        // Balancer shoud revert with BAL#521, which means Token is not register
        vm.expectRevert("BAL#521");
        userProxy.toAMM(payload);
    }

    function testCannotTradeBalancerV2UnsupportedTakerAsset() public {
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        // give an unsurpoted TakerAsset
        // use LON address to test
        order.takerAssetAddr = LON_ADDRESS;
        order.makerAddr = BALANCER_V2_ADDRESS;
        bytes memory sig = _signTrade(userPrivateKey, order);
        address[] memory path = new address[](2);
        path[0] = order.takerAssetAddr;
        path[1] = order.makerAssetAddr;
        IBalancerV2Vault.BatchSwapStep[] memory swapSteps = new IBalancerV2Vault.BatchSwapStep[](1);
        swapSteps[0] = IBalancerV2Vault.BatchSwapStep(
            BALANCER_DAI_USDT_USDC_POOL, // poolId
            0, // assetInIndex
            1, // assetOutIndex
            order.takerAssetAmount, // amount
            new bytes(0) // userData
        );
        bytes memory payload = _genTradePayload(order, DEFAULT_FEE_FACTOR, sig, _encodeBalancerData(swapSteps), path);

        // Balancer shoud revert with BAL#521, which means Token is not register
        vm.expectRevert("BAL#521");
        userProxy.toAMM(payload);
    }

    function testTradeBalanerV2EmitSwappedeventSingleHop() public {
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        order.makerAddr = BALANCER_V2_ADDRESS;
        address[] memory path = new address[](2);
        path[0] = order.takerAssetAddr;
        path[1] = order.makerAssetAddr;
        IBalancerV2Vault.BatchSwapStep[] memory swapSteps = new IBalancerV2Vault.BatchSwapStep[](1);
        swapSteps[0] = IBalancerV2Vault.BatchSwapStep(
            BALANCER_DAI_USDT_USDC_POOL, // poolId
            0, // assetInIndex
            1, // assetOutIndex
            order.takerAssetAmount, // amount
            new bytes(0) // userData
        );
        bytes memory payload = _genTradePayload(order, DEFAULT_FEE_FACTOR, _signTrade(userPrivateKey, order), _encodeBalancerData(swapSteps), path);
        {
            uint256 expectedOutAmount = ammQuoter.getMakerOutAmountWithPath(
                order.makerAddr,
                order.takerAssetAddr,
                order.makerAssetAddr,
                order.takerAssetAmount,
                path,
                _encodeBalancerData(swapSteps)
            );
            uint256 actualFee = (expectedOutAmount * DEFAULT_FEE_FACTOR) / LibConstant.BPS_MAX;
            uint256 settleAmount = expectedOutAmount - actualFee;
            vm.expectEmit(true, true, true, true);
            emit Swapped(
                "Balancer V2",
                AMMLibEIP712._getOrderHash(order),
                order.userAddr,
                true, // relayed
                order.takerAssetAddr,
                order.takerAssetAmount,
                order.makerAddr,
                order.makerAssetAddr,
                order.makerAssetAmount,
                order.receiverAddr,
                settleAmount,
                DEFAULT_FEE_FACTOR
            );
        }
        vm.prank(relayer, relayer);
        userProxy.toAMM(payload);
    }

    function testTradeBalanerV2EmitSwappedeventMultiHop() public {
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        order.makerAddr = BALANCER_V2_ADDRESS;
        address[] memory path = DEFAULT_MULTI_HOP_PATH;
        IBalancerV2Vault.BatchSwapStep[] memory swapSteps = new IBalancerV2Vault.BatchSwapStep[](2);
        swapSteps[0] = IBalancerV2Vault.BatchSwapStep(
            BALANCER_WETH_USDC_POOL, // poolId
            0, // assetInIndex
            1, // assetOutIndex
            order.takerAssetAmount, // amount
            new bytes(0) // userData
        );
        swapSteps[1] = IBalancerV2Vault.BatchSwapStep(
            BALANCER_WETH_DAI_POOL, // poolId
            1, // assetInIndex
            2, // assetOutIndex
            0, // amount
            new bytes(0) // userData
        );
        bytes memory payload = _genTradePayload(order, DEFAULT_FEE_FACTOR, _signTrade(userPrivateKey, order), _encodeBalancerData(swapSteps), path);
        {
            uint256 expectedOutAmount = ammQuoter.getMakerOutAmountWithPath(
                order.makerAddr,
                order.takerAssetAddr,
                order.makerAssetAddr,
                order.takerAssetAmount,
                path,
                _encodeBalancerData(swapSteps)
            );
            uint256 actualFee = (expectedOutAmount * DEFAULT_FEE_FACTOR) / LibConstant.BPS_MAX;
            uint256 settleAmount = expectedOutAmount - actualFee;
            vm.expectEmit(true, true, true, true);
            emit Swapped(
                "Balancer V2",
                AMMLibEIP712._getOrderHash(order),
                order.userAddr,
                true, // relayed
                order.takerAssetAddr,
                order.takerAssetAmount,
                order.makerAddr,
                order.makerAssetAddr,
                order.makerAssetAmount,
                order.receiverAddr,
                settleAmount,
                DEFAULT_FEE_FACTOR
            );
        }
        vm.prank(relayer, relayer);
        userProxy.toAMM(payload);
    }
}
