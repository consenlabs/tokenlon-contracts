// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "contracts-test/forkMainnet/AMMWrapper/Setup.t.sol";
import "contracts-test/utils/BalanceSnapshot.sol";

contract TestAMMWrapperTradeUniswapV2 is TestAMMWrapper {
    using BalanceSnapshot for BalanceSnapshot.Snapshot;

    function testCannotTradeWithInvalidSignature() public {
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        bytes memory sig = _signTrade(otherPrivateKey, order);
        bytes memory payload = _genTradePayload(order, DEFAULT_FEE_FACTOR, sig);

        vm.expectRevert("AMMWrapper: invalid user signature");
        userProxy.toAMM(payload);
    }

    function testCannotTradeWhenPayloadSeenBefore() public {
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        bytes memory sig = _signTrade(userPrivateKey, order);
        bytes memory payload = _genTradePayload(order, DEFAULT_FEE_FACTOR, sig);

        userProxy.toAMM(payload);

        vm.expectRevert("PermanentStorage: transaction seen before");
        userProxy.toAMM(payload);
    }

    function testTradeWithOldEIP712Signature() public {
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        order.takerAssetAddr = ETH_ADDRESS;
        order.takerAssetAmount = 0.1 ether;
        bytes memory sig = _signTradeWithOldEIP712Method(userPrivateKey, order);
        bytes memory payload = _genTradePayload(order, DEFAULT_FEE_FACTOR, sig);

        uint256 expectedOutAmount = ammQuoter.getMakerOutAmount(order.makerAddr, order.takerAssetAddr, order.makerAssetAddr, order.takerAssetAmount);
        uint256 actualFee = (expectedOutAmount * DEFAULT_FEE_FACTOR) / LibConstant.BPS_MAX;
        uint256 settleAmount = expectedOutAmount - actualFee;

        BalanceSnapshot.Snapshot memory userTakerAsset = BalanceSnapshot.take(user, order.takerAssetAddr);
        BalanceSnapshot.Snapshot memory userMakerAsset = BalanceSnapshot.take(user, order.makerAssetAddr);
        BalanceSnapshot.Snapshot memory feeCollectorMakerAsset = BalanceSnapshot.take(feeCollector, order.makerAssetAddr);

        vm.prank(user);
        userProxy.toAMM{ value: order.takerAssetAmount }(payload);

        userTakerAsset.assertChange(-int256(order.takerAssetAmount));
        userMakerAsset.assertChange(int256(settleAmount));
        feeCollectorMakerAsset.assertChange(int256(actualFee));
    }

    function testTradeUniswapV2() public {
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        order.takerAssetAddr = ETH_ADDRESS;
        order.takerAssetAmount = 0.1 ether;
        bytes memory sig = _signTrade(userPrivateKey, order);
        bytes memory payload = _genTradePayload(order, DEFAULT_FEE_FACTOR, sig);

        uint256 expectedOutAmount = ammQuoter.getMakerOutAmount(order.makerAddr, order.takerAssetAddr, order.makerAssetAddr, order.takerAssetAmount);
        uint256 actualFee = (expectedOutAmount * DEFAULT_FEE_FACTOR) / LibConstant.BPS_MAX;
        uint256 settleAmount = expectedOutAmount - actualFee;

        BalanceSnapshot.Snapshot memory userTakerAsset = BalanceSnapshot.take(user, order.takerAssetAddr);
        BalanceSnapshot.Snapshot memory userMakerAsset = BalanceSnapshot.take(user, order.makerAssetAddr);
        BalanceSnapshot.Snapshot memory feeCollectorMakerAsset = BalanceSnapshot.take(feeCollector, order.makerAssetAddr);

        vm.prank(user);
        userProxy.toAMM{ value: order.takerAssetAmount }(payload);

        userTakerAsset.assertChange(-int256(order.takerAssetAmount));
        userMakerAsset.assertChange(int256(settleAmount));
        feeCollectorMakerAsset.assertChange(int256(actualFee));
    }

    function testEmitSwappedEvent() public {
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        bytes memory sig = _signTrade(userPrivateKey, order);
        bytes memory payload = _genTradePayload(order, DEFAULT_FEE_FACTOR, sig);

        uint256 expectedOutAmount = ammQuoter.getMakerOutAmount(order.makerAddr, order.takerAssetAddr, order.makerAssetAddr, order.takerAssetAmount);
        uint256 actualFee = (expectedOutAmount * DEFAULT_FEE_FACTOR) / LibConstant.BPS_MAX;
        uint256 settleAmount = expectedOutAmount - actualFee;

        vm.expectEmit(true, true, true, true);
        emit Swapped(
            "Uniswap V2",
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
        vm.prank(relayer, relayer);
        userProxy.toAMM(payload);
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
