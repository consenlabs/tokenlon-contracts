// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import "contracts-test/forkMainnet/AMMWrapperWithPath/Setup.t.sol";
import "contracts-test/utils/BalanceSnapshot.sol";
import "contracts-test/utils/AMMUtil.sol"; // Using the Encode Data function
import "contracts/interfaces/IAMMWrapper.sol";
import "contracts/AMMQuoter.sol";

contract TestAMMWrapperWithPathTradeUniswapV3 is TestAMMWrapperWithPath {
    using BalanceSnapshot for BalanceSnapshot.Snapshot;
    uint24 constant INVALID_ZERO_FEE = 0;
    uint24 constant INVALID_OVER_FEE = type(uint24).max;

    function testCannotTradeWithInvalidSignature() public {
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        bytes memory sig = _signTrade(otherPrivateKey, order);
        address[] memory path = new address[](0);
        bytes memory makerSpecificData = bytes("");
        bytes memory payload = _genTradePayload(order, DEFAULT_FEE_FACTOR, sig, makerSpecificData, path);

        vm.expectRevert("AMMWrapper: invalid user signature");
        userProxy.toAMM(payload);
    }

    function testCannotTradeSinglePoolWithInvalidSwapType() public {
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        bytes memory sig = _signTrade(userPrivateKey, order);
        address[] memory path = new address[](0);
        bytes memory makerSpecificData = _encodeUniswapSinglePoolData(UNSUPPORTED_SWAP_TYPE, FEE_MEDIUM);
        bytes memory payload = _genTradePayload(order, DEFAULT_FEE_FACTOR, sig, makerSpecificData, path);

        vm.expectRevert("AMMWrapper: unsupported UniswapV3 swap type");
        userProxy.toAMM(payload);

        makerSpecificData = _encodeUniswapSinglePoolData(INVALID_SWAP_TYPE, FEE_MEDIUM);
        payload = _genTradePayload(order, DEFAULT_FEE_FACTOR, sig, makerSpecificData, path);

        // No revert string as it violates SwapType enum's sanity check
        vm.expectRevert();
        userProxy.toAMM(payload);
    }

    function testCannotTradeSinglePoolWithInvalidPoolFee() public {
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        bytes memory sig = _signTrade(userPrivateKey, order);
        address[] memory path = new address[](0);
        bytes memory makerSpecificData = _encodeUniswapSinglePoolData(SINGLE_POOL_SWAP_TYPE, INVALID_ZERO_FEE);
        bytes memory payload = _genTradePayload(order, DEFAULT_FEE_FACTOR, sig, makerSpecificData, path);

        // No revert string for invalid pool fee
        vm.expectRevert();
        userProxy.toAMM(payload);

        makerSpecificData = _encodeUniswapSinglePoolData(SINGLE_POOL_SWAP_TYPE, INVALID_OVER_FEE);
        payload = _genTradePayload(order, DEFAULT_FEE_FACTOR, sig, makerSpecificData, path);

        // No revert string for invalid pool fee
        vm.expectRevert();
        userProxy.toAMM(payload);
    }

    function testCannotTradeMultiPoolWithInvalidPathFormat() public {
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        bytes memory sig = _signTrade(userPrivateKey, order);
        address[] memory path = DEFAULT_MULTI_HOP_PATH;
        bytes memory garbageData = new bytes(0);
        bytes memory makerSpecificData = abi.encode(MULTI_POOL_SWAP_TYPE, garbageData);
        bytes memory payload = _genTradePayload(order, DEFAULT_FEE_FACTOR, sig, makerSpecificData, path);

        vm.expectRevert("toAddress_outOfBounds");
        userProxy.toAMM(payload);

        garbageData = new bytes(2);
        garbageData[0] = "5";
        garbageData[1] = "5";
        makerSpecificData = abi.encode(MULTI_POOL_SWAP_TYPE, garbageData); // Update the path variable
        payload = _genTradePayload(order, DEFAULT_FEE_FACTOR, sig, makerSpecificData, path);

        vm.expectRevert("toAddress_outOfBounds");
        userProxy.toAMM(payload);
    }

    function testCannotTradeMultiPoolWithInvalidFeeFormat() public {
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        bytes memory sig = _signTrade(userPrivateKey, order);
        address[] memory path = new address[](1);
        path[0] = order.takerAssetAddr;
        uint24[] memory fees = new uint24[](0); // No fees specified
        bytes memory makerSpecificData = _encodeUniswapMultiPoolData(MULTI_POOL_SWAP_TYPE, path, fees);
        bytes memory payload = _genTradePayload(order, DEFAULT_FEE_FACTOR, sig, makerSpecificData, path);

        vm.expectRevert("toUint24_outOfBounds");
        userProxy.toAMM(payload);
    }

    function testCannotTradeMultiPoolWithMismatchAsset() public {
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        bytes memory sig = _signTrade(userPrivateKey, order);
        address[] memory path = DEFAULT_MULTI_HOP_PATH;
        path[0] = user;
        uint24[] memory fees = DEFAULT_MULTI_HOP_POOL_FEES;
        bytes memory makerSpecificData = _encodeUniswapMultiPoolData(MULTI_POOL_SWAP_TYPE, path, fees);
        bytes memory payload = _genTradePayload(order, DEFAULT_FEE_FACTOR, sig, makerSpecificData, path);

        vm.expectRevert("UniswapV3: first element of path must match token in");
        userProxy.toAMM(payload);

        path = DEFAULT_MULTI_HOP_PATH;
        path[2] = user;
        makerSpecificData = _encodeUniswapMultiPoolData(MULTI_POOL_SWAP_TYPE, path, fees); // Update the path variable
        payload = _genTradePayload(order, DEFAULT_FEE_FACTOR, sig, makerSpecificData, path);
        vm.expectRevert("UniswapV3: last element of path must match token out");
        userProxy.toAMM(payload);
    }

    function testCannotTradeWhenPayloadSeenBefore() public {
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        bytes memory sig = _signTrade(userPrivateKey, order);
        address[] memory path = new address[](0);
        bytes memory makerSpecificData = _encodeUniswapSinglePoolData(SINGLE_POOL_SWAP_TYPE, FEE_MEDIUM);
        bytes memory payload = _genTradePayload(order, DEFAULT_FEE_FACTOR, sig, makerSpecificData, path);

        userProxy.toAMM(payload);

        vm.expectRevert("PermanentStorage: transaction seen before");
        userProxy.toAMM(payload);
    }

    function testTradeWithSingleExactInput() public {
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        order.makerAssetAddr = ETH_ADDRESS;
        order.makerAssetAmount = 0.001 ether;
        bytes memory sig = _signTrade(userPrivateKey, order);
        address[] memory path = new address[](0);
        bytes memory makerSpecificData = _encodeUniswapSinglePoolData(SINGLE_POOL_SWAP_TYPE, FEE_MEDIUM);
        bytes memory payload = _genTradePayload(order, DEFAULT_FEE_FACTOR, sig, makerSpecificData, path);

        uint256 expectedOutAmount = ammQuoter.getMakerOutAmountWithPath(
            order.makerAddr,
            order.takerAssetAddr,
            order.makerAssetAddr,
            order.takerAssetAmount,
            path,
            makerSpecificData
        );
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

    function testTradeWithSingleHop() public {
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        bytes memory sig = _signTrade(userPrivateKey, order);
        address[] memory path = new address[](0);
        bytes memory makerSpecificData = _encodeUniswapSinglePoolData(SINGLE_POOL_SWAP_TYPE, FEE_MEDIUM);
        bytes memory payload = _genTradePayload(order, DEFAULT_FEE_FACTOR, sig, makerSpecificData, path);

        uint256 expectedOutAmount = ammQuoter.getMakerOutAmountWithPath(
            order.makerAddr,
            order.takerAssetAddr,
            order.makerAssetAddr,
            order.takerAssetAmount,
            path,
            makerSpecificData
        );
        uint256 actualFee = (expectedOutAmount * DEFAULT_FEE_FACTOR) / LibConstant.BPS_MAX;
        uint256 settleAmount = expectedOutAmount - actualFee;

        BalanceSnapshot.Snapshot memory userTakerAsset = BalanceSnapshot.take(user, order.takerAssetAddr);
        BalanceSnapshot.Snapshot memory userMakerAsset = BalanceSnapshot.take(user, order.makerAssetAddr);
        BalanceSnapshot.Snapshot memory feeCollectorMakerAsset = BalanceSnapshot.take(feeCollector, order.makerAssetAddr);

        vm.prank(relayer, relayer);
        userProxy.toAMM(payload);

        userTakerAsset.assertChange(-int256(order.takerAssetAmount));
        userMakerAsset.assertChange(int256(settleAmount));
        feeCollectorMakerAsset.assertChange(int256(actualFee));
    }

    function testTradeWithMultiHop() public {
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        bytes memory sig = _signTrade(userPrivateKey, order);
        address[] memory path = DEFAULT_MULTI_HOP_PATH;
        uint24[] memory fees = DEFAULT_MULTI_HOP_POOL_FEES;
        bytes memory makerSpecificData = _encodeUniswapMultiPoolData(MULTI_POOL_SWAP_TYPE, path, fees);
        bytes memory payload = _genTradePayload(order, DEFAULT_FEE_FACTOR, sig, makerSpecificData, path);

        uint256 expectedOutAmount = ammQuoter.getMakerOutAmountWithPath(
            order.makerAddr,
            order.takerAssetAddr,
            order.makerAssetAddr,
            order.takerAssetAmount,
            path,
            makerSpecificData
        );
        uint256 actualFee = (expectedOutAmount * DEFAULT_FEE_FACTOR) / LibConstant.BPS_MAX;
        uint256 settleAmount = expectedOutAmount - actualFee;

        BalanceSnapshot.Snapshot memory userTakerAsset = BalanceSnapshot.take(user, order.takerAssetAddr);
        BalanceSnapshot.Snapshot memory userMakerAsset = BalanceSnapshot.take(user, order.makerAssetAddr);
        BalanceSnapshot.Snapshot memory feeCollectorMakerAsset = BalanceSnapshot.take(feeCollector, order.makerAssetAddr);

        vm.prank(relayer, relayer);
        userProxy.toAMM(payload);

        userTakerAsset.assertChange(-int256(order.takerAssetAmount));
        userMakerAsset.assertChange(int256(settleAmount));
        feeCollectorMakerAsset.assertChange(int256(actualFee));
    }

    function testEmitSwappedEvent() public {
        // this one was make compact in order to avoid stack too deep
        // focusing on event fileds in this case
        uint256 feeFactor = 0;
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        bytes memory makerSpecificData = _encodeUniswapMultiPoolData(MULTI_POOL_SWAP_TYPE, DEFAULT_MULTI_HOP_PATH, DEFAULT_MULTI_HOP_POOL_FEES);
        bytes memory payload = _genTradePayload(order, feeFactor, _signTrade(userPrivateKey, order), makerSpecificData, DEFAULT_MULTI_HOP_PATH);

        {
            uint256 expectedOutAmount = ammQuoter.getMakerOutAmountWithPath(
                order.makerAddr,
                order.takerAssetAddr,
                order.makerAssetAddr,
                order.takerAssetAmount,
                DEFAULT_MULTI_HOP_PATH,
                makerSpecificData
            );
            vm.expectEmit(false, false, false, true);
            emit Swapped(
                "Uniswap V3",
                AMMLibEIP712._getOrderHash(order),
                order.userAddr,
                true, // relayed
                order.takerAssetAddr,
                order.takerAssetAmount,
                order.makerAddr,
                order.makerAssetAddr,
                order.makerAssetAmount,
                order.receiverAddr,
                expectedOutAmount, // No fee so settled amount is the same as received amount
                uint16(feeFactor) // Fee factor: 0
            );
        }
        vm.prank(relayer, relayer);
        userProxy.toAMM(payload);
    }
}
