// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IERC20 } from "@openzeppelin/contracts@v5.0.2/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts@v5.0.2/token/ERC20/utils/SafeERC20.sol";
import { Address } from "@openzeppelin/contracts@v5.0.2/utils/Address.sol";

import { ILimitOrderSwap } from "contracts/interfaces/ILimitOrderSwap.sol";
import { Constant } from "contracts/libraries/Constant.sol";
import { LimitOrder, getLimitOrderHash } from "contracts/libraries/LimitOrder.sol";

import { LimitOrderSwapTest } from "test/forkMainnet/LimitOrderSwap/Setup.t.sol";
import { MockStrategy } from "test/mocks/MockStrategy.sol";
import { BalanceSnapshot, Snapshot } from "test/utils/BalanceSnapshot.sol";
import { UniswapV2Library } from "test/utils/UniswapV2Library.sol";

contract FillTest is LimitOrderSwapTest {
    using BalanceSnapshot for Snapshot;
    using SafeERC20 for IERC20;

    address[] defaultAMMPath = [DAI_ADDRESS, USDT_ADDRESS];
    MockStrategy mockStrategy;

    function setUp() public override {
        super.setUp();

        mockStrategy = new MockStrategy();
        deal(address(mockStrategy), 100 ether);
        setTokenBalanceAndApprove(address(mockStrategy), address(limitOrderSwap), tokens, 100000);
    }

    function testFullyFillLimitOrder() public {
        Snapshot memory takerTakerToken = BalanceSnapshot.take({ owner: taker, token: defaultOrder.takerToken });
        Snapshot memory takerMakerToken = BalanceSnapshot.take({ owner: taker, token: defaultOrder.makerToken });
        Snapshot memory makerTakerToken = BalanceSnapshot.take({ owner: defaultOrder.maker, token: defaultOrder.takerToken });
        Snapshot memory makerMakerToken = BalanceSnapshot.take({ owner: defaultOrder.maker, token: defaultOrder.makerToken });
        Snapshot memory recTakerToken = BalanceSnapshot.take({ owner: recipient, token: defaultOrder.takerToken });
        Snapshot memory recMakerToken = BalanceSnapshot.take({ owner: recipient, token: defaultOrder.makerToken });
        Snapshot memory fcMakerToken = BalanceSnapshot.take({ owner: feeCollector, token: defaultOrder.makerToken });

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

        vm.startPrank(taker);
        limitOrderSwap.fillLimitOrder({ order: defaultOrder, makerSignature: defaultMakerSig, takerParams: defaultTakerParams });
        vm.stopPrank();
        vm.snapshotGasLastCall("LimitOrderSwap", "fillLimitOrder(): testFullyFillLimitOrder");

        takerTakerToken.assertChange(-int256(defaultOrder.takerTokenAmount));
        takerMakerToken.assertChange(int256(0));
        makerTakerToken.assertChange(int256(defaultOrder.takerTokenAmount));
        makerMakerToken.assertChange(-int256(defaultOrder.makerTokenAmount));
        recTakerToken.assertChange(int256(0));
        recMakerToken.assertChange(int256(defaultOrder.makerTokenAmount - fee));
        fcMakerToken.assertChange(int256(fee));
    }

    function testFullyFillLimitOrderUsingAMM() public {
        Snapshot memory takerTakerToken = BalanceSnapshot.take({ owner: address(mockLimitOrderTaker), token: defaultOrder.takerToken });
        Snapshot memory takerMakerToken = BalanceSnapshot.take({ owner: address(mockLimitOrderTaker), token: defaultOrder.makerToken });
        Snapshot memory makerTakerToken = BalanceSnapshot.take({ owner: defaultOrder.maker, token: defaultOrder.takerToken });
        Snapshot memory makerMakerToken = BalanceSnapshot.take({ owner: defaultOrder.maker, token: defaultOrder.makerToken });
        Snapshot memory fcMakerToken = BalanceSnapshot.take({ owner: feeCollector, token: defaultOrder.makerToken });

        LimitOrder memory order = defaultOrder;
        uint256 fee = (order.makerTokenAmount * defaultFeeFactor) / Constant.BPS_MAX;
        {
            // update order takerTokenAmount by AMM quote
            uint256[] memory amounts = UniswapV2Library.getAmountsOut(defaultOrder.makerTokenAmount - fee, defaultAMMPath);
            order.takerTokenAmount = amounts[amounts.length - 1];
        }

        bytes memory makerSig = signLimitOrder(makerPrivateKey, order, address(limitOrderSwap));

        bytes memory extraAction;
        {
            bytes memory makerSpecificData = abi.encode(defaultAMMPath);
            bytes memory strategyData = abi.encode(UNISWAP_SWAP_ROUTER_02_ADDRESS, order.makerToken, order.makerTokenAmount - fee, makerSpecificData);
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

        vm.startPrank(address(mockLimitOrderTaker));
        limitOrderSwap.fillLimitOrder({
            order: order,
            makerSignature: makerSig,
            takerParams: ILimitOrderSwap.TakerParams({
                takerTokenAmount: order.takerTokenAmount,
                makerTokenAmount: order.makerTokenAmount,
                recipient: address(mockLimitOrderTaker),
                extraAction: extraAction,
                takerTokenPermit: directApprovePermit
            })
        });
        vm.stopPrank();
        vm.snapshotGasLastCall("LimitOrderSwap", "fillLimitOrder(): testFullyFillLimitOrderUsingAMM");

        // taker should not have token balance changes
        takerTakerToken.assertChange(int256(0));
        takerMakerToken.assertChange(int256(0));
        makerTakerToken.assertChange(int256(order.takerTokenAmount));
        makerMakerToken.assertChange(-int256(order.makerTokenAmount));
        fcMakerToken.assertChange(int256(fee));
    }

    function testPartiallyFillLimitOrder() public {
        Snapshot memory takerTakerToken = BalanceSnapshot.take({ owner: taker, token: defaultOrder.takerToken });
        Snapshot memory takerMakerToken = BalanceSnapshot.take({ owner: taker, token: defaultOrder.makerToken });
        Snapshot memory makerTakerToken = BalanceSnapshot.take({ owner: defaultOrder.maker, token: defaultOrder.takerToken });
        Snapshot memory makerMakerToken = BalanceSnapshot.take({ owner: defaultOrder.maker, token: defaultOrder.makerToken });
        Snapshot memory recTakerToken = BalanceSnapshot.take({ owner: recipient, token: defaultOrder.takerToken });
        Snapshot memory recMakerToken = BalanceSnapshot.take({ owner: recipient, token: defaultOrder.makerToken });
        Snapshot memory fcMakerToken = BalanceSnapshot.take({ owner: feeCollector, token: defaultOrder.makerToken });

        uint256 takingAmount = defaultOrder.takerTokenAmount / 2;
        uint256 makingAmount = defaultOrder.makerTokenAmount / 2;
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

        vm.startPrank(taker);
        limitOrderSwap.fillLimitOrder({ order: defaultOrder, makerSignature: defaultMakerSig, takerParams: takerParams });
        vm.stopPrank();
        vm.snapshotGasLastCall("LimitOrderSwap", "fillLimitOrder(): testPartiallyFillLimitOrder");

        takerTakerToken.assertChange(-int256(takingAmount));
        takerMakerToken.assertChange(int256(0));
        makerTakerToken.assertChange(int256(takingAmount));
        makerMakerToken.assertChange(-int256(makingAmount));
        recTakerToken.assertChange(int256(0));
        recMakerToken.assertChange(int256(makingAmount - fee));
        fcMakerToken.assertChange(int256(fee));
    }

    function testFillLimitOrderWithETH() public {
        // read token from constant & defaultOrder to avoid stack too deep error
        Snapshot memory takerTakerToken = BalanceSnapshot.take({ owner: taker, token: Constant.ETH_ADDRESS });
        Snapshot memory takerMakerToken = BalanceSnapshot.take({ owner: taker, token: defaultOrder.makerToken });
        Snapshot memory makerTakerToken = BalanceSnapshot.take({ owner: defaultOrder.maker, token: Constant.ETH_ADDRESS });
        Snapshot memory makerMakerToken = BalanceSnapshot.take({ owner: defaultOrder.maker, token: defaultOrder.makerToken });
        Snapshot memory recTakerToken = BalanceSnapshot.take({ owner: recipient, token: Constant.ETH_ADDRESS });
        Snapshot memory recMakerToken = BalanceSnapshot.take({ owner: recipient, token: defaultOrder.makerToken });
        Snapshot memory fcMakerToken = BalanceSnapshot.take({ owner: feeCollector, token: defaultOrder.makerToken });

        LimitOrder memory order = defaultOrder;
        order.takerToken = Constant.ETH_ADDRESS;
        order.takerTokenAmount = 1 ether;

        bytes memory makerSig = signLimitOrder(makerPrivateKey, order, address(limitOrderSwap));

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

        vm.startPrank(taker);
        limitOrderSwap.fillLimitOrder{ value: order.takerTokenAmount }({
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
        vm.stopPrank();
        vm.snapshotGasLastCall("LimitOrderSwap", "fillLimitOrder(): testFillLimitOrderWithETH");

        takerTakerToken.assertChange(-int256(order.takerTokenAmount));
        takerMakerToken.assertChange(int256(0));
        makerTakerToken.assertChange(int256(order.takerTokenAmount));
        makerMakerToken.assertChange(-int256(order.makerTokenAmount));
        recTakerToken.assertChange(int256(0));
        recMakerToken.assertChange(int256(order.makerTokenAmount - fee));
        fcMakerToken.assertChange(int256(fee));
    }

    function testFillWithBetterTakingAmount() public {
        Snapshot memory takerTakerToken = BalanceSnapshot.take({ owner: taker, token: defaultOrder.takerToken });
        Snapshot memory takerMakerToken = BalanceSnapshot.take({ owner: taker, token: defaultOrder.makerToken });
        Snapshot memory makerTakerToken = BalanceSnapshot.take({ owner: defaultOrder.maker, token: defaultOrder.takerToken });
        Snapshot memory makerMakerToken = BalanceSnapshot.take({ owner: defaultOrder.maker, token: defaultOrder.makerToken });
        Snapshot memory recTakerToken = BalanceSnapshot.take({ owner: recipient, token: defaultOrder.takerToken });
        Snapshot memory recMakerToken = BalanceSnapshot.take({ owner: recipient, token: defaultOrder.makerToken });
        Snapshot memory fcMakerToken = BalanceSnapshot.take({ owner: feeCollector, token: defaultOrder.makerToken });

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

        vm.startPrank(taker);
        limitOrderSwap.fillLimitOrder({ order: defaultOrder, makerSignature: defaultMakerSig, takerParams: takerParams });
        vm.stopPrank();
        vm.snapshotGasLastCall("LimitOrderSwap", "fillLimitOrder(): testFillWithBetterTakingAmount");

        takerTakerToken.assertChange(-int256(actualTokenAmount));
        takerMakerToken.assertChange(int256(0));
        makerTakerToken.assertChange(int256(actualTokenAmount));
        makerMakerToken.assertChange(-int256(defaultOrder.makerTokenAmount));
        recTakerToken.assertChange(int256(0));
        recMakerToken.assertChange(int256(defaultOrder.makerTokenAmount - fee));
        fcMakerToken.assertChange(int256(fee));
    }

    function testFillWithLargerVolumeAndSettleAsManyAsPossible() public {
        Snapshot memory takerTakerToken = BalanceSnapshot.take({ owner: taker, token: defaultOrder.takerToken });
        Snapshot memory takerMakerToken = BalanceSnapshot.take({ owner: taker, token: defaultOrder.makerToken });
        Snapshot memory makerTakerToken = BalanceSnapshot.take({ owner: defaultOrder.maker, token: defaultOrder.takerToken });
        Snapshot memory makerMakerToken = BalanceSnapshot.take({ owner: defaultOrder.maker, token: defaultOrder.makerToken });
        Snapshot memory recTakerToken = BalanceSnapshot.take({ owner: recipient, token: defaultOrder.takerToken });
        Snapshot memory recMakerToken = BalanceSnapshot.take({ owner: recipient, token: defaultOrder.makerToken });
        Snapshot memory fcMakerToken = BalanceSnapshot.take({ owner: feeCollector, token: defaultOrder.makerToken });

        // trying to fill with 2x volume of the order but only settle the original volume
        uint256 traderMakingAmount = defaultOrder.makerTokenAmount * 2;
        uint256 traderTakingAmount = defaultOrder.takerTokenAmount * 2;
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

        vm.startPrank(taker);
        limitOrderSwap.fillLimitOrder({
            order: defaultOrder,
            makerSignature: defaultMakerSig,
            takerParams: ILimitOrderSwap.TakerParams({
                takerTokenAmount: traderTakingAmount,
                makerTokenAmount: traderMakingAmount,
                recipient: recipient,
                extraAction: bytes(""),
                takerTokenPermit: defaultTakerPermit
            })
        });
        vm.stopPrank();
        vm.snapshotGasLastCall("LimitOrderSwap", "fillLimitOrder(): testFillWithLargerVolumeAndSettleAsManyAsPossible");

        takerTakerToken.assertChange(-int256(defaultOrder.takerTokenAmount));
        takerMakerToken.assertChange(int256(0));
        makerTakerToken.assertChange(int256(defaultOrder.takerTokenAmount));
        makerMakerToken.assertChange(-int256(defaultOrder.makerTokenAmount));
        recTakerToken.assertChange(int256(0));
        recMakerToken.assertChange(int256(defaultOrder.makerTokenAmount - fee));
        fcMakerToken.assertChange(int256(fee));
    }

    function testFillWithBetterTakingAmountButGetAdjusted() public {
        // fill with better price but the order doesn't have enough for the requested
        // so the makingAmount == order's available amount
        // takingAmount should be adjusted to keep the original price that taker provided
        Snapshot memory takerTakerToken = BalanceSnapshot.take({ owner: taker, token: defaultOrder.takerToken });
        Snapshot memory takerMakerToken = BalanceSnapshot.take({ owner: taker, token: defaultOrder.makerToken });
        Snapshot memory makerTakerToken = BalanceSnapshot.take({ owner: defaultOrder.maker, token: defaultOrder.takerToken });
        Snapshot memory makerMakerToken = BalanceSnapshot.take({ owner: defaultOrder.maker, token: defaultOrder.makerToken });
        Snapshot memory recTakerToken = BalanceSnapshot.take({ owner: recipient, token: defaultOrder.takerToken });
        Snapshot memory recMakerToken = BalanceSnapshot.take({ owner: recipient, token: defaultOrder.makerToken });
        Snapshot memory fcMakerToken = BalanceSnapshot.take({ owner: feeCollector, token: defaultOrder.makerToken });

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

        vm.startPrank(taker);
        limitOrderSwap.fillLimitOrder({ order: defaultOrder, makerSignature: defaultMakerSig, takerParams: takerParams });
        vm.stopPrank();
        vm.snapshotGasLastCall("LimitOrderSwap", "fillLimitOrder(): testFillWithBetterTakingAmountButGetAdjusted");

        takerTakerToken.assertChange(-int256(settleTakingAMount));
        takerMakerToken.assertChange(int256(0));
        makerTakerToken.assertChange(int256(settleTakingAMount));
        makerMakerToken.assertChange(-int256(defaultOrder.makerTokenAmount));
        recTakerToken.assertChange(int256(0));
        recMakerToken.assertChange(int256(defaultOrder.makerTokenAmount - fee));
        fcMakerToken.assertChange(int256(fee));
    }

    function testFillWithETHRefund() public {
        // read token from constant & defaultOrder to avoid stack too deep error
        Snapshot memory takerTakerToken = BalanceSnapshot.take({ owner: taker, token: Constant.ETH_ADDRESS });
        Snapshot memory takerMakerToken = BalanceSnapshot.take({ owner: taker, token: DAI_ADDRESS });
        Snapshot memory makerTakerToken = BalanceSnapshot.take({ owner: defaultOrder.maker, token: Constant.ETH_ADDRESS });
        Snapshot memory makerMakerToken = BalanceSnapshot.take({ owner: defaultOrder.maker, token: DAI_ADDRESS });
        Snapshot memory recTakerToken = BalanceSnapshot.take({ owner: recipient, token: Constant.ETH_ADDRESS });
        Snapshot memory recMakerToken = BalanceSnapshot.take({ owner: recipient, token: DAI_ADDRESS });
        Snapshot memory fcMakerToken = BalanceSnapshot.take({ owner: feeCollector, token: DAI_ADDRESS });

        // order : 1000 DAI -> 1 ETH
        LimitOrder memory order = LimitOrder({
            taker: address(0),
            maker: maker,
            takerToken: Constant.ETH_ADDRESS,
            takerTokenAmount: 1 ether,
            makerToken: DAI_ADDRESS,
            makerTokenAmount: 1000 ether,
            makerTokenPermit: defaultMakerPermit,
            feeFactor: defaultFeeFactor,
            expiry: defaultExpiry,
            salt: defaultSalt
        });
        bytes memory makerSig = signLimitOrder(makerPrivateKey, order, address(limitOrderSwap));

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

        vm.startPrank(taker);
        limitOrderSwap.fillLimitOrder{ value: traderTakingAmount }({
            order: order,
            makerSignature: makerSig,
            takerParams: ILimitOrderSwap.TakerParams({
                takerTokenAmount: traderTakingAmount,
                makerTokenAmount: traderMakingAmount,
                recipient: recipient,
                extraAction: bytes(""),
                takerTokenPermit: defaultTakerPermit
            })
        });
        vm.stopPrank();
        vm.snapshotGasLastCall("LimitOrderSwap", "fillLimitOrder(): testFillWithETHRefund");

        takerTakerToken.assertChange(-int256(order.takerTokenAmount));
        takerMakerToken.assertChange(int256(0));
        makerTakerToken.assertChange(int256(order.takerTokenAmount));
        makerMakerToken.assertChange(-int256(order.makerTokenAmount));
        recTakerToken.assertChange(int256(0));
        recMakerToken.assertChange(int256(order.makerTokenAmount - fee));
        fcMakerToken.assertChange(int256(fee));
    }

    function testFillWithoutMakerSigForVerifiedOrder() public {
        uint256 takingAmount = defaultOrder.takerTokenAmount / 10;
        uint256 makingAmount = defaultOrder.makerTokenAmount / 10;
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

        // fill default order first with 1/10 amount
        vm.startPrank(taker);
        limitOrderSwap.fillLimitOrder({
            order: defaultOrder,
            makerSignature: defaultMakerSig,
            takerParams: ILimitOrderSwap.TakerParams({
                takerTokenAmount: takingAmount,
                makerTokenAmount: makingAmount,
                recipient: recipient,
                extraAction: bytes(""),
                takerTokenPermit: defaultTakerPermit
            })
        });
        vm.stopPrank();
        vm.snapshotGasLastCall("LimitOrderSwap", "fillLimitOrder(): testFillWithoutMakerSigForVerifiedOrder");

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

        // fill default order again without makerSig
        vm.startPrank(taker);
        limitOrderSwap.fillLimitOrder({
            order: defaultOrder,
            makerSignature: bytes(""),
            takerParams: ILimitOrderSwap.TakerParams({
                takerTokenAmount: takingAmount,
                makerTokenAmount: makingAmount,
                recipient: recipient,
                extraAction: bytes(""),
                takerTokenPermit: allowanceTransferPermit
            })
        });
        vm.stopPrank();
        vm.snapshotGasLastCall("LimitOrderSwap", "fillLimitOrder(): testFillWithoutMakerSigForVerifiedOrder(without makerSig)");
    }

    function testCannotFillWithNotEnoughTakingAmount() public {
        // fill with less than required
        uint256 actualTokenAmount = defaultOrder.takerTokenAmount - 100;
        ILimitOrderSwap.TakerParams memory takerParams = defaultTakerParams;
        takerParams.takerTokenAmount = actualTokenAmount;

        vm.startPrank(taker);
        vm.expectRevert(ILimitOrderSwap.InvalidTakingAmount.selector);
        limitOrderSwap.fillLimitOrder({ order: defaultOrder, makerSignature: defaultMakerSig, takerParams: takerParams });
        vm.stopPrank();
    }

    function testCannotFillIfStrategyNotReturnEnoughTakingAmount() public {
        bytes memory extraAction = abi.encode(address(mockStrategy), bytes(""));
        // prank a random EOA taker without any asset so the only way to fill is via external strategy contract
        address randomTaker = makeAddr("randomTaker");

        // make strategy contract return less than order required
        mockStrategy.setOutputAmountAndRecipient(defaultOrder.takerTokenAmount - 1, payable(randomTaker));

        vm.startPrank(randomTaker);
        IERC20(defaultOrder.takerToken).forceApprove(address(limitOrderSwap), type(uint256).max);

        // the final step transferFrom will fail since taker doesn't have enough balance to fill
        vm.expectRevert(Address.FailedInnerCall.selector);
        limitOrderSwap.fillLimitOrder({
            order: defaultOrder,
            makerSignature: defaultMakerSig,
            takerParams: ILimitOrderSwap.TakerParams({
                takerTokenAmount: defaultOrder.takerTokenAmount,
                makerTokenAmount: defaultOrder.makerTokenAmount,
                recipient: randomTaker,
                extraAction: extraAction,
                takerTokenPermit: directApprovePermit
            })
        });
        vm.stopPrank();
    }

    function testCannotFillExpiredOrder() public {
        vm.warp(defaultOrder.expiry + 1);

        vm.startPrank(taker);
        vm.expectRevert(ILimitOrderSwap.ExpiredOrder.selector);
        limitOrderSwap.fillLimitOrder({ order: defaultOrder, makerSignature: defaultMakerSig, takerParams: defaultTakerParams });
        vm.stopPrank();
    }

    function testCannotFillByNotSpecifiedTaker() public {
        LimitOrder memory order = defaultOrder;
        order.taker = makeAddr("specialTaker");
        bytes memory makerSig = signLimitOrder(makerPrivateKey, order, address(limitOrderSwap));

        vm.startPrank(makeAddr("randomTaker"));
        vm.expectRevert(ILimitOrderSwap.InvalidTaker.selector);
        limitOrderSwap.fillLimitOrder({ order: order, makerSignature: makerSig, takerParams: defaultTakerParams });
        vm.stopPrank();
    }

    function testCannotFillCanceledOrder() public {
        vm.startPrank(maker);
        limitOrderSwap.cancelOrder(defaultOrder);
        vm.stopPrank();

        vm.startPrank(taker);
        vm.expectRevert(ILimitOrderSwap.CanceledOrder.selector);
        limitOrderSwap.fillLimitOrder({ order: defaultOrder, makerSignature: defaultMakerSig, takerParams: defaultTakerParams });
        vm.stopPrank();
    }

    function testCannotFillWithIncorrectMakerSig() public {
        uint256 randomPrivateKey = 5677;
        bytes memory makerSig = signLimitOrder(randomPrivateKey, defaultOrder, address(limitOrderSwap));

        vm.startPrank(taker);
        vm.expectRevert(ILimitOrderSwap.InvalidSignature.selector);
        limitOrderSwap.fillLimitOrder({ order: defaultOrder, makerSignature: makerSig, takerParams: defaultTakerParams });
        vm.stopPrank();
    }

    function testCannotTradeFilledOrder() public {
        vm.startPrank(taker);
        limitOrderSwap.fillLimitOrder({ order: defaultOrder, makerSignature: defaultMakerSig, takerParams: defaultTakerParams });
        vm.stopPrank();

        vm.startPrank(taker);
        vm.expectRevert(ILimitOrderSwap.FilledOrder.selector);
        limitOrderSwap.fillLimitOrder({ order: defaultOrder, makerSignature: defaultMakerSig, takerParams: defaultTakerParams });
        vm.stopPrank();
    }

    function testCannotFillWithIncorrectMsgValue() public {
        // case1 : takerToken is not ETH but msg.value != 0
        vm.startPrank(taker);
        vm.expectRevert(ILimitOrderSwap.InvalidMsgValue.selector);
        limitOrderSwap.fillLimitOrder{ value: 100 }({ order: defaultOrder, makerSignature: defaultMakerSig, takerParams: defaultTakerParams });
        vm.stopPrank();

        LimitOrder memory order = defaultOrder;
        order.takerToken = Constant.ETH_ADDRESS;
        bytes memory makerSig = signLimitOrder(makerPrivateKey, order, address(limitOrderSwap));

        // case2 : takerToken is ETH but msg.value > takingAmount
        vm.startPrank(taker);
        vm.expectRevert(ILimitOrderSwap.InvalidMsgValue.selector);
        limitOrderSwap.fillLimitOrder{ value: defaultTakerParams.takerTokenAmount + 1 }({
            order: order,
            makerSignature: makerSig,
            takerParams: defaultTakerParams
        });
        vm.stopPrank();

        // case3 : takerToken is ETH but msg.value < takingAmount
        vm.startPrank(taker);
        vm.expectRevert(ILimitOrderSwap.InvalidMsgValue.selector);
        limitOrderSwap.fillLimitOrder{ value: defaultTakerParams.takerTokenAmount - 1 }({
            order: order,
            makerSignature: makerSig,
            takerParams: defaultTakerParams
        });
        vm.stopPrank();
    }

    function testCannotFillWithZeroRecipient() public {
        ILimitOrderSwap.TakerParams memory takerParams = defaultTakerParams;
        takerParams.recipient = address(0);

        vm.startPrank(taker);
        vm.expectRevert(ILimitOrderSwap.ZeroAddress.selector);
        limitOrderSwap.fillLimitOrder({ order: defaultOrder, makerSignature: defaultMakerSig, takerParams: takerParams });
        vm.stopPrank();
    }
}
