// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IUniswapRouterV2 } from "contracts/interfaces/IUniswapRouterV2.sol";
import { ILimitOrderSwap } from "contracts/interfaces/ILimitOrderSwap.sol";
import { Constant } from "contracts/libraries/Constant.sol";
import { LimitOrder, getLimitOrderHash } from "contracts/libraries/LimitOrder.sol";
import { BalanceSnapshot, Snapshot } from "test/utils/BalanceSnapshot.sol";
import { LimitOrderSwapTest } from "test/forkMainnet/LimitOrderSwap/Setup.t.sol";

contract FillTest is LimitOrderSwapTest {
    using BalanceSnapshot for Snapshot;

    address[] defaultAMMPath = [DAI_ADDRESS, USDT_ADDRESS];

    function testFullyFillLimitOrder() public {
        Snapshot memory takerTakerToken = BalanceSnapshot.take({ owner: taker, token: defaultOrder.takerToken });
        Snapshot memory takerMakerToken = BalanceSnapshot.take({ owner: taker, token: defaultOrder.makerToken });
        Snapshot memory makerTakerToken = BalanceSnapshot.take({ owner: defaultOrder.maker, token: defaultOrder.takerToken });
        Snapshot memory makerMakerToken = BalanceSnapshot.take({ owner: defaultOrder.maker, token: defaultOrder.makerToken });
        Snapshot memory recTakerToken = BalanceSnapshot.take({ owner: recipient, token: defaultOrder.takerToken });
        Snapshot memory recMakerToken = BalanceSnapshot.take({ owner: recipient, token: defaultOrder.makerToken });
        Snapshot memory feeCollectorBal = BalanceSnapshot.take({ owner: feeCollector, token: defaultOrder.makerToken });

        uint256 fee = (defaultOrder.makerTokenAmount * defaultFeeFactor) / Constant.BPS_MAX;

        vm.expectEmit(true, true, true, true);
        emit LimitOrderFilled(
            getLimitOrderHash(defaultOrder),
            taker,
            defaultOrder.maker,
            defaultOrder.takerToken,
            defaultOrder.takerTokenAmount,
            defaultOrder.makerToken,
            defaultOrder.makerTokenAmount - fee,
            fee,
            recipient
        );

        vm.prank(taker);
        limitOrderSwap.fillLimitOrder({ order: defaultOrder, makerSignature: defaultMakerSig, takerParams: defaultTakerParams });

        takerTakerToken.assertChange(-int256(defaultOrder.takerTokenAmount));
        takerMakerToken.assertChange(int256(0));
        makerTakerToken.assertChange(int256(defaultOrder.takerTokenAmount));
        makerMakerToken.assertChange(-int256(defaultOrder.makerTokenAmount));
        recTakerToken.assertChange(int256(0));
        recMakerToken.assertChange(int256(defaultOrder.makerTokenAmount - fee));
        feeCollectorBal.assertChange(int256(fee));
    }

    function testFullyFillLimitOrderUsingAMM() public {
        Snapshot memory takerTakerToken = BalanceSnapshot.take({ owner: address(mockLimitOrderTaker), token: defaultOrder.takerToken });
        Snapshot memory takerMakerToken = BalanceSnapshot.take({ owner: address(mockLimitOrderTaker), token: defaultOrder.makerToken });
        Snapshot memory makerTakerToken = BalanceSnapshot.take({ owner: defaultOrder.maker, token: defaultOrder.takerToken });
        Snapshot memory makerMakerToken = BalanceSnapshot.take({ owner: defaultOrder.maker, token: defaultOrder.makerToken });
        Snapshot memory feeCollectorBal = BalanceSnapshot.take({ owner: feeCollector, token: defaultOrder.makerToken });

        LimitOrder memory order = defaultOrder;
        uint256 fee = (order.makerTokenAmount * defaultFeeFactor) / Constant.BPS_MAX;
        {
            // update order takerTokenAmount by AMM quote
            IUniswapRouterV2 router = IUniswapRouterV2(UNISWAP_V2_ADDRESS);
            uint256[] memory amounts = router.getAmountsOut(defaultOrder.makerTokenAmount - fee, defaultAMMPath);
            order.takerTokenAmount = amounts[amounts.length - 1];
        }

        bytes memory makerSig = _signLimitOrder(makerPrivateKey, order);

        bytes memory extraAction;
        {
            bytes memory makerSpecificData = abi.encode(defaultExpiry, defaultAMMPath);
            bytes memory strategyData = abi.encode(UNISWAP_V2_ADDRESS, makerSpecificData);
            extraAction = abi.encode(address(mockLimitOrderTaker), strategyData);
        }

        vm.expectEmit(true, true, true, true);
        emit LimitOrderFilled(
            getLimitOrderHash(order),
            address(mockLimitOrderTaker),
            order.maker,
            order.takerToken,
            order.takerTokenAmount,
            order.makerToken,
            order.makerTokenAmount - fee,
            fee,
            address(mockLimitOrderTaker)
        );

        vm.prank(address(mockLimitOrderTaker));
        limitOrderSwap.fillLimitOrder({
            order: order,
            makerSignature: makerSig,
            takerParams: ILimitOrderSwap.TakerParams({
                takerTokenAmount: order.takerTokenAmount,
                makerTokenAmount: order.makerTokenAmount,
                recipient: address(mockLimitOrderTaker),
                extraAction: extraAction,
                takerTokenPermit: defaultPermit
            })
        });

        // taker should not have token balance changes
        takerTakerToken.assertChange(int256(0));
        takerMakerToken.assertChange(int256(0));
        makerTakerToken.assertChange(int256(order.takerTokenAmount));
        makerMakerToken.assertChange(-int256(order.makerTokenAmount));
        feeCollectorBal.assertChange(int256(fee));
    }

    function testPartiallyFillLimitOrder() public {
        Snapshot memory takerTakerToken = BalanceSnapshot.take({ owner: taker, token: defaultOrder.takerToken });
        Snapshot memory takerMakerToken = BalanceSnapshot.take({ owner: taker, token: defaultOrder.makerToken });
        Snapshot memory makerTakerToken = BalanceSnapshot.take({ owner: defaultOrder.maker, token: defaultOrder.takerToken });
        Snapshot memory makerMakerToken = BalanceSnapshot.take({ owner: defaultOrder.maker, token: defaultOrder.makerToken });
        Snapshot memory recTakerToken = BalanceSnapshot.take({ owner: recipient, token: defaultOrder.takerToken });
        Snapshot memory recMakerToken = BalanceSnapshot.take({ owner: recipient, token: defaultOrder.makerToken });
        Snapshot memory feeCollectorBal = BalanceSnapshot.take({ owner: feeCollector, token: defaultOrder.makerToken });

        uint256 takingAmount = defaultOrder.takerTokenAmount / 2;
        uint256 makingAmount = defaultOrder.takerTokenAmount / 2;
        uint256 fee = (makingAmount * defaultFeeFactor) / Constant.BPS_MAX;

        vm.expectEmit(true, true, true, true);
        emit LimitOrderFilled(
            getLimitOrderHash(defaultOrder),
            taker,
            defaultOrder.maker,
            defaultOrder.takerToken,
            takingAmount,
            defaultOrder.makerToken,
            makingAmount - fee,
            fee,
            recipient
        );
        ILimitOrderSwap.TakerParams memory takerParams = defaultTakerParams;
        takerParams.takerTokenAmount = takingAmount;
        takerParams.makerTokenAmount = makingAmount;

        vm.prank(taker);
        limitOrderSwap.fillLimitOrder({ order: defaultOrder, makerSignature: defaultMakerSig, takerParams: takerParams });

        takerTakerToken.assertChange(-int256(takingAmount));
        takerMakerToken.assertChange(int256(0));
        makerTakerToken.assertChange(int256(takingAmount));
        makerMakerToken.assertChange(-int256(makingAmount));
        recTakerToken.assertChange(int256(0));
        recMakerToken.assertChange(int256(makingAmount - fee));
        feeCollectorBal.assertChange(int256(fee));
    }

    function testFillLimitOrderWithETH() public {
        // read token from constant & defaultOrder to avoid stack too deep error
        Snapshot memory takerTakerToken = BalanceSnapshot.take({ owner: taker, token: Constant.ETH_ADDRESS });
        Snapshot memory takerMakerToken = BalanceSnapshot.take({ owner: taker, token: defaultOrder.makerToken });
        Snapshot memory makerTakerToken = BalanceSnapshot.take({ owner: defaultOrder.maker, token: Constant.ETH_ADDRESS });
        Snapshot memory makerMakerToken = BalanceSnapshot.take({ owner: defaultOrder.maker, token: defaultOrder.makerToken });
        Snapshot memory recTakerToken = BalanceSnapshot.take({ owner: recipient, token: Constant.ETH_ADDRESS });
        Snapshot memory recMakerToken = BalanceSnapshot.take({ owner: recipient, token: defaultOrder.makerToken });
        Snapshot memory feeCollectorBal = BalanceSnapshot.take({ owner: feeCollector, token: defaultOrder.makerToken });

        LimitOrder memory order = defaultOrder;
        order.takerToken = Constant.ETH_ADDRESS;
        order.takerTokenAmount = 1 ether;

        bytes memory makerSig = _signLimitOrder(makerPrivateKey, order);

        uint256 fee = (order.makerTokenAmount * defaultFeeFactor) / Constant.BPS_MAX;

        vm.expectEmit(true, true, true, true);
        emit LimitOrderFilled(
            getLimitOrderHash(order),
            taker,
            order.maker,
            order.takerToken,
            order.takerTokenAmount,
            order.makerToken,
            order.makerTokenAmount - fee,
            fee,
            recipient
        );

        vm.prank(taker);
        limitOrderSwap.fillLimitOrder{ value: order.takerTokenAmount }({
            order: order,
            makerSignature: makerSig,
            takerParams: ILimitOrderSwap.TakerParams({
                takerTokenAmount: order.takerTokenAmount,
                makerTokenAmount: order.makerTokenAmount,
                recipient: recipient,
                extraAction: bytes(""),
                takerTokenPermit: defaultPermit
            })
        });

        takerTakerToken.assertChange(-int256(order.takerTokenAmount));
        takerMakerToken.assertChange(int256(0));
        makerTakerToken.assertChange(int256(order.takerTokenAmount));
        makerMakerToken.assertChange(-int256(order.makerTokenAmount));
        recTakerToken.assertChange(int256(0));
        recMakerToken.assertChange(int256(order.makerTokenAmount - fee));
        feeCollectorBal.assertChange(int256(fee));
    }

    function testFillWithBetterTakingAmount() public {
        Snapshot memory takerTakerToken = BalanceSnapshot.take({ owner: taker, token: defaultOrder.takerToken });
        Snapshot memory takerMakerToken = BalanceSnapshot.take({ owner: taker, token: defaultOrder.makerToken });
        Snapshot memory makerTakerToken = BalanceSnapshot.take({ owner: defaultOrder.maker, token: defaultOrder.takerToken });
        Snapshot memory makerMakerToken = BalanceSnapshot.take({ owner: defaultOrder.maker, token: defaultOrder.makerToken });
        Snapshot memory recTakerToken = BalanceSnapshot.take({ owner: recipient, token: defaultOrder.takerToken });
        Snapshot memory recMakerToken = BalanceSnapshot.take({ owner: recipient, token: defaultOrder.makerToken });
        Snapshot memory feeCollectorBal = BalanceSnapshot.take({ owner: feeCollector, token: defaultOrder.makerToken });

        uint256 fee = (defaultOrder.makerTokenAmount * defaultFeeFactor) / Constant.BPS_MAX;
        // fill with more taker token
        uint256 actualTokenAmount = defaultOrder.takerTokenAmount + 100;

        ILimitOrderSwap.TakerParams memory takerParams = defaultTakerParams;
        takerParams.takerTokenAmount = actualTokenAmount;

        vm.expectEmit(true, true, true, true);
        emit LimitOrderFilled(
            getLimitOrderHash(defaultOrder),
            taker,
            defaultOrder.maker,
            defaultOrder.takerToken,
            actualTokenAmount,
            defaultOrder.makerToken,
            defaultOrder.makerTokenAmount - fee,
            fee,
            recipient
        );

        vm.prank(taker);
        limitOrderSwap.fillLimitOrder({ order: defaultOrder, makerSignature: defaultMakerSig, takerParams: takerParams });

        takerTakerToken.assertChange(-int256(actualTokenAmount));
        takerMakerToken.assertChange(int256(0));
        makerTakerToken.assertChange(int256(actualTokenAmount));
        makerMakerToken.assertChange(-int256(defaultOrder.makerTokenAmount));
        recTakerToken.assertChange(int256(0));
        recMakerToken.assertChange(int256(defaultOrder.makerTokenAmount - fee));
        feeCollectorBal.assertChange(int256(fee));
    }

    function testFillWithBetterTakingAmountButGetAdjusted() public {
        // fill with better price but the order doesn't have enough for the requested
        // so the makingAmount == order's avaliable amount
        // takingAmount should be adjusted to keep the original price that taker provided
        Snapshot memory takerTakerToken = BalanceSnapshot.take({ owner: taker, token: defaultOrder.takerToken });
        Snapshot memory takerMakerToken = BalanceSnapshot.take({ owner: taker, token: defaultOrder.makerToken });
        Snapshot memory makerTakerToken = BalanceSnapshot.take({ owner: defaultOrder.maker, token: defaultOrder.takerToken });
        Snapshot memory makerMakerToken = BalanceSnapshot.take({ owner: defaultOrder.maker, token: defaultOrder.makerToken });
        Snapshot memory recTakerToken = BalanceSnapshot.take({ owner: recipient, token: defaultOrder.takerToken });
        Snapshot memory recMakerToken = BalanceSnapshot.take({ owner: recipient, token: defaultOrder.makerToken });
        Snapshot memory feeCollectorBal = BalanceSnapshot.take({ owner: feeCollector, token: defaultOrder.makerToken });

        // fill with more taker token
        // original : 10 DAI -> 10 USDT
        // taker provide : 30 USDT -> 20 DAI
        uint256 traderMakingAmount = defaultOrder.makerTokenAmount * 2; // 20 DAI
        uint256 traderTakingAmount = defaultOrder.takerTokenAmount * 3; // 30 USDT
        // should be 15 USDT
        uint256 settleTakingAMount = (traderTakingAmount * defaultOrder.makerTokenAmount) / traderMakingAmount;

        ILimitOrderSwap.TakerParams memory takerParams = defaultTakerParams;
        takerParams.takerTokenAmount = traderTakingAmount;
        takerParams.makerTokenAmount = traderMakingAmount;

        // fee is calculated by the actual settlement makerTokenAmount which is the order full amount in this case
        uint256 fee = (defaultOrder.makerTokenAmount * defaultFeeFactor) / Constant.BPS_MAX;

        vm.expectEmit(true, true, true, true);
        emit LimitOrderFilled(
            getLimitOrderHash(defaultOrder),
            taker,
            defaultOrder.maker,
            defaultOrder.takerToken,
            settleTakingAMount,
            defaultOrder.makerToken,
            defaultOrder.makerTokenAmount - fee,
            fee,
            recipient
        );

        vm.prank(taker);
        limitOrderSwap.fillLimitOrder({ order: defaultOrder, makerSignature: defaultMakerSig, takerParams: takerParams });

        takerTakerToken.assertChange(-int256(settleTakingAMount));
        takerMakerToken.assertChange(int256(0));
        makerTakerToken.assertChange(int256(settleTakingAMount));
        makerMakerToken.assertChange(-int256(defaultOrder.makerTokenAmount));
        recTakerToken.assertChange(int256(0));
        recMakerToken.assertChange(int256(defaultOrder.makerTokenAmount - fee));
        feeCollectorBal.assertChange(int256(fee));
    }

    function testFillWithETHRefund() public {
        // read token from constant & defaultOrder to avoid stack too deep error
        Snapshot memory takerTakerToken = BalanceSnapshot.take({ owner: taker, token: Constant.ETH_ADDRESS });
        Snapshot memory takerMakerToken = BalanceSnapshot.take({ owner: taker, token: DAI_ADDRESS });
        Snapshot memory makerTakerToken = BalanceSnapshot.take({ owner: defaultOrder.maker, token: Constant.ETH_ADDRESS });
        Snapshot memory makerMakerToken = BalanceSnapshot.take({ owner: defaultOrder.maker, token: DAI_ADDRESS });
        Snapshot memory recTakerToken = BalanceSnapshot.take({ owner: recipient, token: Constant.ETH_ADDRESS });
        Snapshot memory recMakerToken = BalanceSnapshot.take({ owner: recipient, token: DAI_ADDRESS });
        Snapshot memory feeCollectorBal = BalanceSnapshot.take({ owner: feeCollector, token: DAI_ADDRESS });

        // order : 1000 DAI -> 1 ETH
        LimitOrder memory order = LimitOrder({
            taker: address(0),
            maker: maker,
            takerToken: Constant.ETH_ADDRESS,
            takerTokenAmount: 1 ether,
            makerToken: DAI_ADDRESS,
            makerTokenAmount: 1000 ether,
            makerTokenPermit: defaultPermit,
            feeFactor: defaultFeeFactor,
            expiry: defaultExpiry,
            salt: defaultSalt
        });
        bytes memory makerSig = _signLimitOrder(makerPrivateKey, order);

        // keep the same ratio but double the amount
        uint256 traderMakingAmount = order.makerTokenAmount * 2;
        uint256 traderTakingAmount = order.takerTokenAmount * 2;

        uint256 fee = (order.makerTokenAmount * defaultFeeFactor) / Constant.BPS_MAX;

        vm.expectEmit(true, true, true, true);
        emit LimitOrderFilled(
            getLimitOrderHash(order),
            taker,
            order.maker,
            order.takerToken,
            order.takerTokenAmount,
            order.makerToken,
            order.makerTokenAmount - fee,
            fee,
            recipient
        );

        vm.prank(taker);
        limitOrderSwap.fillLimitOrder{ value: traderTakingAmount }({
            order: order,
            makerSignature: makerSig,
            takerParams: ILimitOrderSwap.TakerParams({
                takerTokenAmount: traderTakingAmount,
                makerTokenAmount: traderMakingAmount,
                recipient: recipient,
                extraAction: bytes(""),
                takerTokenPermit: defaultPermit
            })
        });

        takerTakerToken.assertChange(-int256(order.takerTokenAmount));
        takerMakerToken.assertChange(int256(0));
        makerTakerToken.assertChange(int256(order.takerTokenAmount));
        makerMakerToken.assertChange(-int256(order.makerTokenAmount));
        recTakerToken.assertChange(int256(0));
        recMakerToken.assertChange(int256(order.makerTokenAmount - fee));
        feeCollectorBal.assertChange(int256(fee));
    }

    function testFillWithoutMakerSigForVerifiedOrder() public {
        // fill default order first with 1/10 amount
        vm.prank(taker);
        limitOrderSwap.fillLimitOrder({
            order: defaultOrder,
            makerSignature: defaultMakerSig,
            takerParams: ILimitOrderSwap.TakerParams({
                takerTokenAmount: defaultOrder.takerTokenAmount / 10,
                makerTokenAmount: defaultOrder.makerTokenAmount / 10,
                recipient: recipient,
                extraAction: bytes(""),
                takerTokenPermit: defaultPermit
            })
        });

        // fill default order again without makerSig
        vm.prank(taker);
        limitOrderSwap.fillLimitOrder({
            order: defaultOrder,
            makerSignature: bytes(""),
            takerParams: ILimitOrderSwap.TakerParams({
                takerTokenAmount: defaultOrder.takerTokenAmount / 10,
                makerTokenAmount: defaultOrder.makerTokenAmount / 10,
                recipient: recipient,
                extraAction: bytes(""),
                takerTokenPermit: defaultPermit
            })
        });
    }

    function testCannotFillWithNotEnoughTakingAmount() public {
        // fill with less than required
        uint256 actualTokenAmount = defaultOrder.takerTokenAmount - 100;
        ILimitOrderSwap.TakerParams memory takerParams = defaultTakerParams;
        takerParams.takerTokenAmount = actualTokenAmount;

        vm.expectRevert(ILimitOrderSwap.InvalidTakingAmount.selector);
        vm.prank(taker);
        limitOrderSwap.fillLimitOrder({ order: defaultOrder, makerSignature: defaultMakerSig, takerParams: takerParams });
    }

    function testCannotFillExpiredOrder() public {
        vm.warp(defaultOrder.expiry + 1);

        vm.expectRevert(ILimitOrderSwap.ExpiredOrder.selector);
        vm.prank(taker);
        limitOrderSwap.fillLimitOrder({ order: defaultOrder, makerSignature: defaultMakerSig, takerParams: defaultTakerParams });
    }

    function testCannotFillByNotSpecifiedTaker() public {
        LimitOrder memory order = defaultOrder;
        order.taker = makeAddr("specialTaker");
        bytes memory makerSig = _signLimitOrder(makerPrivateKey, order);

        vm.expectRevert(ILimitOrderSwap.InvalidTaker.selector);
        vm.prank(makeAddr("randomTaker"));
        limitOrderSwap.fillLimitOrder({ order: order, makerSignature: makerSig, takerParams: defaultTakerParams });
    }

    function testCannotFillCanceledOrder() public {
        vm.prank(maker);
        limitOrderSwap.cancelOder(defaultOrder);

        vm.expectRevert(ILimitOrderSwap.CanceledOrder.selector);
        vm.prank(taker);
        limitOrderSwap.fillLimitOrder({ order: defaultOrder, makerSignature: defaultMakerSig, takerParams: defaultTakerParams });
    }

    function testCannotFillWithIncorrectMakerSig() public {
        uint256 randomPrivateKey = 5677;
        bytes memory makerSig = _signLimitOrder(randomPrivateKey, defaultOrder);

        vm.expectRevert(ILimitOrderSwap.InvalidSignature.selector);
        vm.prank(taker);
        limitOrderSwap.fillLimitOrder({ order: defaultOrder, makerSignature: makerSig, takerParams: defaultTakerParams });
    }

    function testCannotTradeFilledOrder() public {
        vm.prank(taker);
        limitOrderSwap.fillLimitOrder({ order: defaultOrder, makerSignature: defaultMakerSig, takerParams: defaultTakerParams });

        vm.expectRevert(ILimitOrderSwap.FilledOrder.selector);
        vm.prank(taker);
        limitOrderSwap.fillLimitOrder({ order: defaultOrder, makerSignature: defaultMakerSig, takerParams: defaultTakerParams });
    }

    function testCannotFillWithIncorrectMsgValue() public {
        // case1 : takerToken is not ETH but msg.value != 0
        vm.expectRevert(ILimitOrderSwap.InvalidMsgValue.selector);
        vm.prank(taker);
        limitOrderSwap.fillLimitOrder{ value: 100 }({ order: defaultOrder, makerSignature: defaultMakerSig, takerParams: defaultTakerParams });

        LimitOrder memory order = defaultOrder;
        order.takerToken = Constant.ETH_ADDRESS;
        bytes memory makerSig = _signLimitOrder(makerPrivateKey, order);

        // case2 : takerToken is ETH but msg.value > takingAmount
        vm.expectRevert(ILimitOrderSwap.InvalidMsgValue.selector);
        vm.prank(taker);
        limitOrderSwap.fillLimitOrder{ value: defaultTakerParams.takerTokenAmount + 1 }({
            order: order,
            makerSignature: makerSig,
            takerParams: defaultTakerParams
        });

        // case3 : takerToken is ETH but msg.value < takingAmount
        vm.expectRevert(ILimitOrderSwap.InvalidMsgValue.selector);
        vm.prank(taker);
        limitOrderSwap.fillLimitOrder{ value: defaultTakerParams.takerTokenAmount - 1 }({
            order: order,
            makerSignature: makerSig,
            takerParams: defaultTakerParams
        });
    }
}
