// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { ILimitOrderSwap } from "contracts/interfaces/ILimitOrderSwap.sol";
import { getLimitOrderHash } from "contracts/libraries/LimitOrder.sol";

import { LimitOrderSwapTest } from "test/forkMainnet/LimitOrderSwap/Setup.t.sol";

contract CancelOrderTest is LimitOrderSwapTest {
    function testCancelOrder() public {
        vm.expectEmit(true, true, true, true);
        emit ILimitOrderSwap.OrderCanceled(getLimitOrderHash(defaultOrder), maker);

        vm.startPrank(maker);
        limitOrderSwap.cancelOrder(defaultOrder);
        vm.stopPrank();
        vm.snapshotGasLastCall("LimitOrderSwap", "cancelOrder(): testCancelOrder");

        assertEq(limitOrderSwap.isOrderCanceled(getLimitOrderHash(defaultOrder)), true);
    }

    function testCannotCancelOrderIfNotMaker() public {
        vm.startPrank(taker);
        vm.expectRevert(ILimitOrderSwap.NotOrderMaker.selector);
        limitOrderSwap.cancelOrder(defaultOrder);
        vm.stopPrank();
    }

    function testCannotCancelExpiredOrder() public {
        vm.warp(defaultOrder.expiry + 1);

        vm.startPrank(maker);
        vm.expectRevert(ILimitOrderSwap.ExpiredOrder.selector);
        limitOrderSwap.cancelOrder(defaultOrder);
        vm.stopPrank();
    }

    function testCannotCancelFilledOrder() public {
        vm.startPrank(taker);
        limitOrderSwap.fillLimitOrder({ order: defaultOrder, makerSignature: defaultMakerSig, takerParams: defaultTakerParams });
        vm.stopPrank();

        vm.startPrank(maker);
        vm.expectRevert(ILimitOrderSwap.FilledOrder.selector);
        limitOrderSwap.cancelOrder(defaultOrder);
        vm.stopPrank();
    }

    function testCannotCancelCanceledOrder() public {
        vm.startPrank(maker);
        limitOrderSwap.cancelOrder(defaultOrder);
        vm.stopPrank();

        vm.startPrank(maker);
        vm.expectRevert(ILimitOrderSwap.CanceledOrder.selector);
        limitOrderSwap.cancelOrder(defaultOrder);
        vm.stopPrank();
    }
}
