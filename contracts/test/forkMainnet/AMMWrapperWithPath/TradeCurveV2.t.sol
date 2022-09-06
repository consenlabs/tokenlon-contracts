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

        // verify the makerasset
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        order.makerAddr = CURVE_USDT_POOL_ADDRESS;
        bytes memory sig = _signTrade(userPrivateKey, order);
        // Curve USDT pool is version 1 but we input version 2
        bytes memory payload = _genTradePayload(order, feeFactor, sig, _encodeCurveData(2), new address[](0));

        vm.expectRevert("AMMWrapper: Curve v2 no underlying");
        userProxy.toAMM(payload);

        // verify the takerasset
        order = DEFAULT_ORDER;
        // DAI is not in CURVE_USDT_POOL
        order.takerAssetAddr = DAI_ADDRESS;
        order.makerAddr = CURVE_USDT_POOL_ADDRESS;
        sig = _signTrade(userPrivateKey, order);
        payload = _genTradePayload(order, feeFactor, sig, _encodeCurveData(2), new address[](0));

        vm.expectRevert("AMMWrapper: Curve v2 no underlying");
        userProxy.toAMM(payload);
    }

    function testCannotTradeCurveV1_With_MismatchSwapToken_Version1() public {
        uint256 feeFactor = 0;
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        order.makerAddr = CURVE_USDT_POOL_ADDRESS;
        // give an unpsorted token to swap
        // Eq: CURVE_USDT_POOL does not support USDC
        order.takerAssetAddr = USDC_ADDRESS;
        bytes memory sig = _signTrade(userPrivateKey, order);
        bytes memory payload = _genTradePayload(order, feeFactor, sig, _encodeCurveData(1), new address[](0));

        vm.expectRevert("AMMWrapper: Invalid swapMethod for CurveV1");
        userProxy.toAMM(payload);
    }

    function testCannotTradeCurveWithUnknownVersion() public {
        uint256 feeFactor = 0;
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        order.makerAddr = CURVE_USDT_POOL_ADDRESS;
        bytes memory sig = _signTrade(userPrivateKey, order);
        // curve doesn't has v3
        bytes memory payload = _genTradePayload(order, feeFactor, sig, _encodeCurveData(3), new address[](0));
        vm.expectRevert("AMMWrapper: Invalid Curve version");
        userProxy.toAMM(payload);
    }

    function testCannotTradeCurveWithZeroAmount() public {
        uint256 feeFactor = 0;
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        order.makerAddr = CURVE_TRICRYPTO2_POOL_ADDRESS;
        order.takerAssetAddr = address(usdt);
        order.takerAssetAmount = 0;
        order.makerAssetAddr = address(wbtc);
        order.makerAssetAmount = 0;

        bytes memory sig = _signTrade(userPrivateKey, order);
        bytes memory payload = _genTradePayload(order, feeFactor, sig, _encodeCurveData(2), new address[](0));

        vm.expectRevert(); 
        userProxy.toAMM(payload);
    }

    function testTradeCurveV2EmitSwappedevent() public {
        uint256 feeFactor = 0;
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        order.makerAddr = CURVE_TRICRYPTO2_POOL_ADDRESS;
        order.takerAssetAddr = address(usdt);
        order.takerAssetAmount = 100 * 1e6;
        order.makerAssetAddr = address(wbtc);
        order.makerAssetAmount = 0.001 * 1e8;
        address[] memory path  = new address[](2);


        bytes memory sig = _signTrade(userPrivateKey, order);
        bytes memory payload = _genTradePayload(order, feeFactor, sig, _encodeCurveData(2), new address[](0));

        {
            uint256 expectedOutAmount = ammQuoter.getMakerOutAmountWithPath(
                order.makerAddr, 
                order.takerAssetAddr, 
                order.makerAssetAddr, 
                order.takerAssetAmount, 
                path, 
                _encodeCurveData(2)
            );
            vm.expectEmit(true, true, true, true);
            emit Swapped(
                "Curve",
                AMMLibEIP712._getOrderHash(order),
                order.userAddr,
                true, // relayed
                order.takerAssetAddr,
                order.takerAssetAmount,
                order.makerAddr,
                order.makerAssetAddr,
                order.makerAssetAmount,
                order.receiverAddr,
                expectedOutAmount + 1 , // No fee so settled amount is the same as received amount
                // the difference betwween actualAmount and expectedAmount is 1
                uint16(0) // Fee factor: 0
            );
        }
        vm.prank(relayer, relayer);
        userProxy.toAMM(payload);
    }
}
