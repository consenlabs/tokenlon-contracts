// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IConditionalSwap } from "contracts/interfaces/IConditionalSwap.sol";
import { ConOrder, getConOrderHash } from "contracts/libraries/ConditionalOrder.sol";
import { ConditionalOrderSwapTest } from "test/forkMainnet/ConditionalSwap/Setup.t.sol";
import { BalanceSnapshot, Snapshot } from "test/utils/BalanceSnapshot.sol";

contract ConFillTest is ConditionalOrderSwapTest {
    using BalanceSnapshot for Snapshot;

    function setUp() public override {
        super.setUp();
    }

    function testFullyFillBestBuyOrder() external {
        ConOrder memory order = defaultOrder;

        Snapshot memory takerTakerToken = BalanceSnapshot.take({ owner: order.taker, token: order.takerToken });
        Snapshot memory takerMakerToken = BalanceSnapshot.take({ owner: order.taker, token: order.makerToken });
        Snapshot memory makerTakerToken = BalanceSnapshot.take({ owner: order.maker, token: order.takerToken });
        Snapshot memory makerMakerToken = BalanceSnapshot.take({ owner: order.maker, token: order.makerToken });
        Snapshot memory recTakerToken = BalanceSnapshot.take({ owner: order.recipient, token: order.takerToken });
        Snapshot memory recMakerToken = BalanceSnapshot.take({ owner: order.recipient, token: order.makerToken });

        // craft the `flagAndPeriod` of the order for BestBuy case
        uint256 flags = FLG_PARTIAL_FILL_MASK;
        order.flagsAndPeriod = flags;

        takerSig = signConOrder(takerPrivateKey, order, address(conditionalSwap));

        vm.expectEmit(true, true, true, true);
        emit ConditionalOrderFilled(
            getConOrderHash(order),
            order.taker,
            order.maker,
            order.takerToken,
            order.takerTokenAmount,
            order.makerToken,
            order.makerTokenAmount,
            order.recipient
        );

        vm.startPrank(order.maker);
        conditionalSwap.fillConOrder(order, takerSig, order.takerTokenAmount, order.makerTokenAmount, defaultSettlementData);
        vm.stopPrank();

        takerTakerToken.assertChange(-int256(order.takerTokenAmount));
        takerMakerToken.assertChange(int256(0));
        makerTakerToken.assertChange(int256(order.takerTokenAmount));
        makerMakerToken.assertChange(-int256(order.makerTokenAmount));
        recTakerToken.assertChange(int256(0));
        recMakerToken.assertChange(int256(order.makerTokenAmount));
    }

    function testPartialFillBestBuyOrder() external {
        ConOrder memory order = defaultOrder;

        Snapshot memory takerTakerToken = BalanceSnapshot.take({ owner: order.taker, token: order.takerToken });
        Snapshot memory takerMakerToken = BalanceSnapshot.take({ owner: order.taker, token: order.makerToken });
        Snapshot memory makerTakerToken = BalanceSnapshot.take({ owner: order.maker, token: order.takerToken });
        Snapshot memory makerMakerToken = BalanceSnapshot.take({ owner: order.maker, token: order.makerToken });
        Snapshot memory recTakerToken = BalanceSnapshot.take({ owner: order.recipient, token: order.takerToken });
        Snapshot memory recMakerToken = BalanceSnapshot.take({ owner: order.recipient, token: order.makerToken });

        // craft the `flagAndPeriod` of the defaultOrder for BestBuy case
        uint256 flags = FLG_PARTIAL_FILL_MASK;
        order.flagsAndPeriod = flags;

        uint256 partialTakerTokenAmount = 5 * 1e6;
        uint256 partialMakerTokenAmount = 5 ether;

        takerSig = signConOrder(takerPrivateKey, order, address(conditionalSwap));

        vm.expectEmit(true, true, true, true);
        emit ConditionalOrderFilled(
            getConOrderHash(order),
            order.taker,
            order.maker,
            order.takerToken,
            partialTakerTokenAmount,
            order.makerToken,
            partialMakerTokenAmount,
            order.recipient
        );

        vm.startPrank(order.maker);
        conditionalSwap.fillConOrder(order, takerSig, partialTakerTokenAmount, partialMakerTokenAmount, defaultSettlementData);
        vm.stopPrank();

        takerTakerToken.assertChange(-int256(partialTakerTokenAmount));
        takerMakerToken.assertChange(int256(0));
        makerTakerToken.assertChange(int256(partialTakerTokenAmount));
        makerMakerToken.assertChange(-int256(partialMakerTokenAmount));
        recTakerToken.assertChange(int256(0));
        recMakerToken.assertChange(int256(partialMakerTokenAmount));
    }

    function testFullyFillRepaymentOrDCAOrder() external {
        ConOrder memory order = defaultOrder;

        Snapshot memory takerTakerToken = BalanceSnapshot.take({ owner: order.taker, token: order.takerToken });
        Snapshot memory takerMakerToken = BalanceSnapshot.take({ owner: order.taker, token: order.makerToken });
        Snapshot memory makerTakerToken = BalanceSnapshot.take({ owner: order.maker, token: order.takerToken });
        Snapshot memory makerMakerToken = BalanceSnapshot.take({ owner: order.maker, token: order.makerToken });
        Snapshot memory recTakerToken = BalanceSnapshot.take({ owner: order.recipient, token: order.takerToken });
        Snapshot memory recMakerToken = BalanceSnapshot.take({ owner: order.recipient, token: order.makerToken });

        // craft the `flagAndPeriod` of the order for BestBuy case
        uint256 flags = FLG_SINGLE_AMOUNT_CAP_MASK | FLG_PERIODIC_MASK | FLG_PARTIAL_FILL_MASK;
        uint256 period = 12 hours;
        order.flagsAndPeriod = flags | period;

        uint256 numberOfCycles = (defaultExpiry - block.timestamp) / period;

        takerSig = signConOrder(takerPrivateKey, order, address(conditionalSwap));

        vm.expectEmit(true, true, true, true);
        emit ConditionalOrderFilled(
            getConOrderHash(order),
            order.taker,
            order.maker,
            order.takerToken,
            order.takerTokenAmount,
            order.makerToken,
            order.makerTokenAmount,
            recipient
        );

        vm.startPrank(order.maker);
        for (uint256 i; i < numberOfCycles; ++i) {
            conditionalSwap.fillConOrder(order, takerSig, order.takerTokenAmount, order.makerTokenAmount, defaultSettlementData);
            vm.warp(block.timestamp + period);
        }
        vm.stopPrank();

        takerTakerToken.assertChange(-int256(order.takerTokenAmount) * int256(numberOfCycles));
        takerMakerToken.assertChange(int256(0));
        makerTakerToken.assertChange(int256(order.takerTokenAmount) * int256(numberOfCycles));
        makerMakerToken.assertChange(-int256(order.makerTokenAmount) * int256(numberOfCycles));
        recTakerToken.assertChange(int256(0));
        recMakerToken.assertChange(int256(order.makerTokenAmount) * int256(numberOfCycles));
    }

    function testPartialFillRepaymentOrDCAOrder() external {
        ConOrder memory order = defaultOrder;

        Snapshot memory takerTakerToken = BalanceSnapshot.take({ owner: order.taker, token: order.takerToken });
        Snapshot memory takerMakerToken = BalanceSnapshot.take({ owner: order.taker, token: order.makerToken });
        Snapshot memory makerTakerToken = BalanceSnapshot.take({ owner: order.maker, token: order.takerToken });
        Snapshot memory makerMakerToken = BalanceSnapshot.take({ owner: order.maker, token: order.makerToken });
        Snapshot memory recTakerToken = BalanceSnapshot.take({ owner: order.recipient, token: order.takerToken });
        Snapshot memory recMakerToken = BalanceSnapshot.take({ owner: order.recipient, token: order.makerToken });

        // craft the `flagAndPeriod` of the order for BestBuy case
        uint256 flags = FLG_SINGLE_AMOUNT_CAP_MASK | FLG_PERIODIC_MASK | FLG_PARTIAL_FILL_MASK;
        uint256 period = 12 hours;
        order.flagsAndPeriod = flags | period;

        uint256 numberOfCycles = (defaultExpiry - block.timestamp) / period;

        uint256 partialTakerTokenAmount = 5 * 1e6;
        uint256 partialMakerTokenAmount = 5 ether;

        takerSig = signConOrder(takerPrivateKey, order, address(conditionalSwap));

        vm.expectEmit(true, true, true, true);
        emit ConditionalOrderFilled(
            getConOrderHash(order),
            order.taker,
            order.maker,
            order.takerToken,
            partialTakerTokenAmount,
            order.makerToken,
            partialMakerTokenAmount,
            recipient
        );

        vm.startPrank(order.maker);
        for (uint256 i; i < numberOfCycles; ++i) {
            conditionalSwap.fillConOrder(order, takerSig, partialTakerTokenAmount, partialMakerTokenAmount, defaultSettlementData);
            vm.warp(block.timestamp + period);
        }
        vm.stopPrank();

        takerTakerToken.assertChange(-int256(partialTakerTokenAmount) * int256(numberOfCycles));
        takerMakerToken.assertChange(int256(0));
        makerTakerToken.assertChange(int256(partialTakerTokenAmount) * int256(numberOfCycles));
        makerMakerToken.assertChange(-int256(partialMakerTokenAmount) * int256(numberOfCycles));
        recTakerToken.assertChange(int256(0));
        recMakerToken.assertChange(int256(partialMakerTokenAmount) * int256(numberOfCycles));
    }

    function testExecuteOrderWithRelayer() external {
        ConOrder memory order = defaultOrder;

        Snapshot memory takerTakerToken = BalanceSnapshot.take({ owner: order.taker, token: order.takerToken });
        Snapshot memory takerMakerToken = BalanceSnapshot.take({ owner: order.taker, token: order.makerToken });
        Snapshot memory makerTakerToken = BalanceSnapshot.take({ owner: order.maker, token: order.takerToken });
        Snapshot memory makerMakerToken = BalanceSnapshot.take({ owner: order.maker, token: order.makerToken });
        Snapshot memory recTakerToken = BalanceSnapshot.take({ owner: order.recipient, token: order.takerToken });
        Snapshot memory recMakerToken = BalanceSnapshot.take({ owner: order.recipient, token: order.makerToken });
        Snapshot memory relayerTakerToken = BalanceSnapshot.take({ owner: relayer, token: order.takerToken });
        Snapshot memory relayerMakerToken = BalanceSnapshot.take({ owner: relayer, token: order.makerToken });

        // craft the `flagAndPeriod` of the order for BestBuy case
        uint256 flags = FLG_PARTIAL_FILL_MASK;
        order.flagsAndPeriod = flags;

        // add relayer
        vm.startPrank(order.maker);
        address[] memory relayers = new address[](1);
        relayers[0] = relayer;
        conditionalSwap.addRelayers(relayers);
        vm.stopPrank();

        takerSig = signConOrder(takerPrivateKey, order, address(conditionalSwap));

        vm.expectEmit(true, true, true, true);
        emit ConditionalOrderFilled(
            getConOrderHash(order),
            order.taker,
            order.maker,
            order.takerToken,
            order.takerTokenAmount,
            order.makerToken,
            order.makerTokenAmount,
            recipient
        );

        vm.startPrank(relayer);
        conditionalSwap.fillConOrder(order, takerSig, order.takerTokenAmount, order.makerTokenAmount, defaultSettlementData);
        vm.stopPrank();

        takerTakerToken.assertChange(-int256(order.takerTokenAmount));
        takerMakerToken.assertChange(int256(0));
        makerTakerToken.assertChange(0);
        makerMakerToken.assertChange(0);
        recTakerToken.assertChange(int256(0));
        recMakerToken.assertChange(int256(order.makerTokenAmount));
        relayerTakerToken.assertChange(int256(order.takerTokenAmount));
        relayerMakerToken.assertChange(-int256(order.makerTokenAmount));
    }

    function testCannotFillExpiredOrder() public {
        vm.warp(defaultOrder.expiry + 1);

        vm.expectRevert(IConditionalSwap.ExpiredOrder.selector);
        vm.startPrank(defaultOrder.maker);
        conditionalSwap.fillConOrder(defaultOrder, takerSig, defaultOrder.takerTokenAmount, defaultOrder.makerTokenAmount, defaultSettlementData);
        vm.stopPrank();
    }

    function testCannotFillOrderByInvalidOderMaker() public {
        address invalidOrderMaker = makeAddr("invalidOrderMaker");

        vm.expectRevert(IConditionalSwap.NotOrderExecutor.selector);
        vm.startPrank(invalidOrderMaker);
        conditionalSwap.fillConOrder(defaultOrder, takerSig, defaultOrder.takerTokenAmount, defaultOrder.makerTokenAmount, defaultSettlementData);
        vm.stopPrank();
    }

    function testCannotFillOrderWithZeroTakerTokenAmount() public {
        vm.expectRevert(IConditionalSwap.ZeroTokenAmount.selector);
        vm.startPrank(defaultOrder.maker);
        conditionalSwap.fillConOrder(defaultOrder, takerSig, 0, defaultOrder.makerTokenAmount, defaultSettlementData);
        vm.stopPrank();
    }

    function testCannotFillOrderWithInvalidTotalTakerTokenAmount() public {
        ConOrder memory order = defaultOrder;

        // craft the `flagAndPeriod` of the order for BestBuy case
        uint256 flags = FLG_PARTIAL_FILL_MASK;
        order.flagsAndPeriod = flags;

        takerSig = signConOrder(takerPrivateKey, order, address(conditionalSwap));

        vm.startPrank(order.maker);
        // the first fill with full takerTokenAmount
        conditionalSwap.fillConOrder(order, takerSig, order.takerTokenAmount, order.makerTokenAmount, defaultSettlementData);

        vm.expectRevert(IConditionalSwap.InvalidTakingAmount.selector);
        // The second fill with 1 takerTokenAmount would exceed the total cap this time.
        conditionalSwap.fillConOrder(order, takerSig, 1, order.makerTokenAmount, defaultSettlementData);
        vm.stopPrank();
    }

    function testCannotFillOrderWithInvalidSingleTakerTokenAmount() public {
        ConOrder memory order = defaultOrder;

        // craft the `flagAndPeriod` of the order for BestBuy case
        uint256 flags = FLG_SINGLE_AMOUNT_CAP_MASK | FLG_PERIODIC_MASK | FLG_PARTIAL_FILL_MASK;
        uint256 period = 12 hours;
        order.flagsAndPeriod = flags | period;

        takerSig = signConOrder(takerPrivateKey, order, address(conditionalSwap));

        vm.expectRevert(IConditionalSwap.InvalidTakingAmount.selector);
        vm.startPrank(order.maker);
        conditionalSwap.fillConOrder(order, takerSig, order.takerTokenAmount + 1, order.makerTokenAmount, defaultSettlementData);
        vm.stopPrank();
    }

    function testCannotFillOrderWithZeroRecipient() public {
        ConOrder memory order = defaultOrder;
        order.recipient = payable(address(0));

        takerSig = signConOrder(takerPrivateKey, order, address(conditionalSwap));

        vm.expectRevert(IConditionalSwap.InvalidRecipient.selector);
        vm.startPrank(order.maker);
        conditionalSwap.fillConOrder(order, takerSig, order.takerTokenAmount, order.makerTokenAmount, defaultSettlementData);
        vm.stopPrank();
    }

    function testCannotFillOrderWithIncorrectSignature() public {
        uint256 randomPrivateKey = 1234;
        bytes memory randomEOASig = signConOrder(randomPrivateKey, defaultOrder, address(conditionalSwap));

        vm.expectRevert(IConditionalSwap.InvalidSignature.selector);
        vm.startPrank(defaultOrder.maker);
        conditionalSwap.fillConOrder(defaultOrder, randomEOASig, defaultOrder.takerTokenAmount, defaultOrder.makerTokenAmount, defaultSettlementData);
        vm.stopPrank();
    }

    function testCannotFillOrderWithinSamePeriod() public {
        ConOrder memory order = defaultOrder;
        // craft the `flagAndPeriod` of the order for BestBuy case
        uint256 flags = FLG_SINGLE_AMOUNT_CAP_MASK | FLG_PERIODIC_MASK | FLG_PARTIAL_FILL_MASK;
        uint256 period = 12 hours;
        order.flagsAndPeriod = flags | period;

        takerSig = signConOrder(takerPrivateKey, order, address(conditionalSwap));

        vm.startPrank(order.maker);
        conditionalSwap.fillConOrder(order, takerSig, order.takerTokenAmount, order.makerTokenAmount, defaultSettlementData);
        vm.warp(block.timestamp + 1);
        vm.expectRevert(IConditionalSwap.InsufficientTimePassed.selector);
        conditionalSwap.fillConOrder(order, takerSig, order.takerTokenAmount, order.makerTokenAmount, defaultSettlementData);
        vm.stopPrank();
    }

    function testCannotFillOrderWithInvalidSettlementType() public {
        bytes memory settlementData = hex"02";

        takerSig = signConOrder(takerPrivateKey, defaultOrder, address(conditionalSwap));

        vm.expectRevert(IConditionalSwap.InvalidSettlementType.selector);
        vm.startPrank(defaultOrder.maker);
        conditionalSwap.fillConOrder(defaultOrder, takerSig, defaultOrder.takerTokenAmount, defaultOrder.makerTokenAmount, settlementData);
        vm.stopPrank();
    }

    function testCannotFillOrderWithInvalidMakingAmount() public {
        takerSig = signConOrder(takerPrivateKey, defaultOrder, address(conditionalSwap));

        vm.expectRevert(IConditionalSwap.InvalidMakingAmount.selector);
        vm.startPrank(defaultOrder.maker);
        conditionalSwap.fillConOrder(defaultOrder, takerSig, defaultOrder.takerTokenAmount, defaultOrder.makerTokenAmount - 1, defaultSettlementData);
        vm.stopPrank();
    }

    function testCannotFillOrderWithRemovedRelayer() public {
        // add relayer
        vm.startPrank(defaultOrder.maker);
        address[] memory relayers = new address[](1);
        relayers[0] = relayer;
        conditionalSwap.addRelayers(relayers);
        conditionalSwap.removeRelayers(relayers);
        vm.stopPrank();

        vm.expectRevert(IConditionalSwap.NotOrderExecutor.selector);
        vm.startPrank(relayer);
        conditionalSwap.fillConOrder(defaultOrder, takerSig, defaultOrder.takerTokenAmount, defaultOrder.makerTokenAmount, defaultSettlementData);
        vm.stopPrank();
    }
}
