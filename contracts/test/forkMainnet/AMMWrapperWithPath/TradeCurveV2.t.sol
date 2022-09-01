// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import "contracts-test/forkMainnet/AMMWrapperWithPath/Setup.t.sol";
import "contracts-test/utils/BalanceSnapshot.sol";
import "contracts-test/utils/AMMUtil.sol"; // Using the Encode Data function

contract TestAMMWrapperWithPathTradeCurveV2 is TestAMMWrapperWithPath {
    using BalanceSnapshot for BalanceSnapshot.Snapshot;

    function testTradeCurveVersion2() public {
        uint256 feeFactor = 0;
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        order.makerAddr = CURVE_TRICRYPTO2_POOL_ADDRESS;
        order.takerAssetAddr = address(usdt);
        order.takerAssetAmount = 100 * 1e6;
        order.makerAssetAddr = address(wbtc);
        order.makerAssetAmount = 0.001 * 1e8;
        bytes memory sig = _signTrade(userPrivateKey, order);
        bytes memory payload = _genTradePayload(order, feeFactor, sig, _encodeCurveData(2), new address[](0));

        BalanceSnapshot.Snapshot memory userTakerAsset = BalanceSnapshot.take(user, order.takerAssetAddr);
        BalanceSnapshot.Snapshot memory userMakerAsset = BalanceSnapshot.take(user, order.makerAssetAddr);

        userProxy.toAMM(payload);

        userTakerAsset.assertChange(-int256(order.takerAssetAmount));
        userMakerAsset.assertChangeGt(int256(order.makerAssetAmount));
    }

    function testCannotTradeCurveWithMismatchVersion_Version1PoolAndSpecifyVersion2() public {
        uint256 feeFactor = 0;
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        order.makerAddr = CURVE_USDT_POOL_ADDRESS;
        bytes memory sig = _signTrade(userPrivateKey, order);
        // Curve USDT pool is version 1 but we input version 2
        bytes memory payload = _genTradePayload(order, feeFactor, sig, _encodeCurveData(2), new address[](0));

        vm.expectRevert("AMMWrapper: Curve v2 no underlying");
        userProxy.toAMM(payload);
    }
}
