// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { LimitOrderSwapTest } from "./Setup.t.sol";
import { ILimitOrderSwap } from "contracts/interfaces/ILimitOrderSwap.sol";
import { LimitOrder } from "contracts/libraries/LimitOrder.sol";

contract ValidationTest is LimitOrderSwapTest {
    function testCannotFillLimitOrderWithZeroTakerTokenAmount() public {
        LimitOrder memory order = defaultOrder;
        order.takerTokenAmount = 0;

        bytes memory makerSig = signLimitOrder(makerPrivateKey, order, address(limitOrderSwap));

        vm.expectRevert(ILimitOrderSwap.ZeroTakerTokenAmount.selector);
        limitOrderSwap.fillLimitOrder({
            order: order,
            makerSignature: makerSig,
            takerParams: ILimitOrderSwap.TakerParams({
                takerTokenAmount: order.takerTokenAmount,
                makerTokenAmount: order.makerTokenAmount,
                recipient: recipient,
                extraAction: bytes(""),
                takerTokenPermit: defaultTakerPermit
            })
        });
    }

    function testCannotFillLimitOrderWithZeroMakerTokenAmount() public {
        LimitOrder memory order = defaultOrder;
        order.makerTokenAmount = 0;

        bytes memory makerSig = signLimitOrder(makerPrivateKey, order, address(limitOrderSwap));

        vm.expectRevert(ILimitOrderSwap.ZeroMakerTokenAmount.selector);
        limitOrderSwap.fillLimitOrder({
            order: order,
            makerSignature: makerSig,
            takerParams: ILimitOrderSwap.TakerParams({
                takerTokenAmount: order.takerTokenAmount,
                makerTokenAmount: order.makerTokenAmount,
                recipient: recipient,
                extraAction: bytes(""),
                takerTokenPermit: defaultTakerPermit
            })
        });
    }

    function testCannotFillLimitOrderWithZeroTakerSpendingAmount() public {
        vm.expectRevert(ILimitOrderSwap.ZeroTakerSpendingAmount.selector);
        limitOrderSwap.fillLimitOrder({
            order: defaultOrder,
            makerSignature: defaultMakerSig,
            takerParams: ILimitOrderSwap.TakerParams({
                takerTokenAmount: 0,
                makerTokenAmount: defaultOrder.makerTokenAmount,
                recipient: recipient,
                extraAction: bytes(""),
                takerTokenPermit: defaultTakerPermit
            })
        });
    }

    function testCannotFillLimitOrderWithZeroTakerSpendingAmountWhenRecalculation() public {
        // this case tests if _takerTokenAmount is zero due to re-calculation.
        vm.expectRevert(ILimitOrderSwap.ZeroTakerSpendingAmount.selector);
        vm.prank(taker);
        limitOrderSwap.fillLimitOrder({
            order: defaultOrder,
            makerSignature: defaultMakerSig,
            takerParams: ILimitOrderSwap.TakerParams({
                takerTokenAmount: 1,
                makerTokenAmount: 1000 ether,
                recipient: recipient,
                extraAction: bytes(""),
                takerTokenPermit: defaultTakerPermit
            })
        });
    }

    function testCannotFillLimitOrderWithZeroMakerSpendingAmount() public {
        vm.expectRevert(ILimitOrderSwap.ZeroMakerSpendingAmount.selector);
        limitOrderSwap.fillLimitOrder({
            order: defaultOrder,
            makerSignature: defaultMakerSig,
            takerParams: ILimitOrderSwap.TakerParams({
                takerTokenAmount: defaultOrder.takerTokenAmount,
                makerTokenAmount: 0,
                recipient: recipient,
                extraAction: bytes(""),
                takerTokenPermit: defaultTakerPermit
            })
        });
    }

    function testCannotFillLimitOrderGroupWithInvalidParams() public {
        LimitOrder[] memory orders = new LimitOrder[](1);
        bytes[] memory makerSigs = new bytes[](2);
        uint256[] memory makerTokenAmounts = new uint256[](3);
        address[] memory profitTokens = new address[](1);

        vm.expectRevert(ILimitOrderSwap.InvalidParams.selector);
        limitOrderSwap.fillLimitOrderGroup({ orders: orders, makerSignatures: makerSigs, makerTokenAmounts: makerTokenAmounts, profitTokens: profitTokens });
    }

    function testCannotFillLimitOrderGroupWithNotEnoughForFill() public {
        LimitOrder[] memory orders = new LimitOrder[](1);
        bytes[] memory makerSigs = new bytes[](1);
        uint256[] memory makerTokenAmounts = new uint256[](1);
        address[] memory profitTokens = new address[](1);

        // order 10 DAI -> 10 USDT
        orders[0] = LimitOrder({
            taker: address(0),
            maker: maker,
            takerToken: USDT_ADDRESS,
            takerTokenAmount: 10 * 1e6,
            makerToken: DAI_ADDRESS,
            makerTokenAmount: 10 ether,
            makerTokenPermit: defaultMakerPermit,
            feeFactor: 0,
            expiry: defaultExpiry,
            salt: defaultSalt
        });
        makerSigs[0] = signLimitOrder(makerPrivateKey, orders[0], address(limitOrderSwap));
        makerTokenAmounts[0] = orders[0].makerTokenAmount + 1;

        vm.expectRevert(ILimitOrderSwap.NotEnoughForFill.selector);
        limitOrderSwap.fillLimitOrderGroup({ orders: orders, makerSignatures: makerSigs, makerTokenAmounts: makerTokenAmounts, profitTokens: profitTokens });
    }

    function testCannotFillLimitOrderGroupWithZeroMakerSpendingAmount() public {
        LimitOrder[] memory orders = new LimitOrder[](1);
        bytes[] memory makerSigs = new bytes[](1);
        uint256[] memory makerTokenAmounts = new uint256[](1);
        address[] memory profitTokens = new address[](1);

        // order 10 DAI -> 10 USDT
        orders[0] = LimitOrder({
            taker: address(0),
            maker: maker,
            takerToken: USDT_ADDRESS,
            takerTokenAmount: 10 * 10e6,
            makerToken: DAI_ADDRESS,
            makerTokenAmount: 10 ether,
            makerTokenPermit: defaultMakerPermit,
            feeFactor: 0,
            expiry: defaultExpiry,
            salt: defaultSalt
        });
        makerSigs[0] = signLimitOrder(makerPrivateKey, orders[0], address(limitOrderSwap));
        makerTokenAmounts[0] = 0;

        vm.expectRevert(ILimitOrderSwap.ZeroMakerSpendingAmount.selector);
        limitOrderSwap.fillLimitOrderGroup({ orders: orders, makerSignatures: makerSigs, makerTokenAmounts: makerTokenAmounts, profitTokens: profitTokens });
    }
}
