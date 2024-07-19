// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { getLimitOrderHash } from "contracts/libraries/LimitOrder.sol";
import { ILimitOrderSwap } from "contracts/interfaces/ILimitOrderSwap.sol";
import { LimitOrderSwapTest } from "test/forkMainnet/LimitOrderSwap/Setup.t.sol";

contract CancelOrderTest is LimitOrderSwapTest {
    event OrderCanceled(bytes32 orderHash, address maker);

    function testCancelOrder() public {
        vm.expectEmit(true, true, true, true);
        emit OrderCanceled(getLimitOrderHash(defaultOrder), maker);

        vm.prank(maker, maker);
        limitOrderSwap.cancelOrder(defaultOrder);
        assertEq(limitOrderSwap.isOrderCanceled(getLimitOrderHash(defaultOrder)), true);
    }

    function testCannotCancelOrderIfNotMaker() public {
        vm.expectRevert(ILimitOrderSwap.NotOrderMaker.selector);
        vm.prank(taker, taker);
        limitOrderSwap.cancelOrder(defaultOrder);
    }

    function testCannotCancelExpiredOrder() public {
        vm.warp(defaultOrder.expiry + 1);

        vm.expectRevert(ILimitOrderSwap.ExpiredOrder.selector);
        vm.prank(maker, maker);
        limitOrderSwap.cancelOrder(defaultOrder);
    }

    function testCannotCancelFilledOrder() public {
        vm.prank(taker);
        limitOrderSwap.fillLimitOrder({ order: defaultOrder, makerSignature: defaultMakerSig, takerParams: defaultTakerParams });

        vm.expectRevert(ILimitOrderSwap.FilledOrder.selector);
        vm.prank(maker, maker);
        limitOrderSwap.cancelOrder(defaultOrder);
    }

    function testCannotCancelCanceledOrder() public {
        vm.prank(maker, maker);
        limitOrderSwap.cancelOrder(defaultOrder);

        vm.expectRevert(ILimitOrderSwap.CanceledOrder.selector);
        vm.prank(maker, maker);
        limitOrderSwap.cancelOrder(defaultOrder);
    }
}
