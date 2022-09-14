// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import "contracts-test/forkMainnet/AMMWrapperWithPath/Setup.t.sol";
import "contracts-test/utils/BalanceSnapshot.sol";

contract TestAMMWrapperWithPathTradeSushiswap is TestAMMWrapperWithPath {
    using BalanceSnapshot for BalanceSnapshot.Snapshot;

    function testTradeWithSingleHop() public {
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        order.makerAddr = SUSHISWAP_ADDRESS;
        order.makerAssetAddr = ETH_ADDRESS;
        order.makerAssetAmount = 0.001 ether;
        bytes memory sig = _signTrade(userPrivateKey, order);
        address[] memory path = new address[](0);
        bytes memory makerSpecificData = bytes("");
        bytes memory payload = _genTradePayload(order, DEFAULT_FEE_FACTOR, sig, makerSpecificData, path);

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

    function testTradeWithSingleHopWithOldEIP712Signature() public {
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        order.makerAddr = SUSHISWAP_ADDRESS;
        order.makerAssetAddr = ETH_ADDRESS;
        order.makerAssetAmount = 0.001 ether;
        bytes memory sig = _signTradeWithOldEIP712Method(userPrivateKey, order);
        address[] memory path = new address[](0);
        bytes memory makerSpecificData = bytes("");
        bytes memory payload = _genTradePayload(order, DEFAULT_FEE_FACTOR, sig, makerSpecificData, path);

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

    function testTradeWithMultiHop() public {
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        order.makerAddr = SUSHISWAP_ADDRESS;
        order.makerAssetAddr = ETH_ADDRESS;
        order.makerAssetAmount = 0.001 ether;
        bytes memory sig = _signTrade(userPrivateKey, order);
        address[] memory path = DEFAULT_MULTI_HOP_PATH;
        path[1] = address(dai);
        path[2] = address(weth);
        bytes memory makerSpecificData = bytes("");
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

    /*********************************
     *          Test Helpers         *
     *********************************/

    function _signTradeWithOldEIP712Method(uint256 privateKey, AMMLibEIP712.Order memory order) internal returns (bytes memory sig) {
        bytes32 orderHash = AMMLibEIP712._getOrderHash(order);
        bytes32 EIP712SignDigest = _getEIP712Hash(orderHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, EIP712SignDigest);
        sig = abi.encodePacked(r, s, v, bytes32(0), uint8(SignatureValidator.SignatureType.EIP712));
    }
}
