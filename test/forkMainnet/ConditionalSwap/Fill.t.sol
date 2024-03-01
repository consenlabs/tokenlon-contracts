// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IConditionalSwap } from "contracts/interfaces/IConditionalSwap.sol";
import { getConOrderHash } from "contracts/libraries/ConditionalOrder.sol";
import { ConditionalOrderSwapTest } from "test/forkMainnet/ConditionalSwap/Setup.t.sol";
import { BalanceSnapshot, Snapshot } from "test/utils/BalanceSnapshot.sol";

contract ConFillTest is ConditionalOrderSwapTest {
    using BalanceSnapshot for Snapshot;

    function setUp() public override {
        super.setUp();
    }

    function testBestBuyOrder() external {
        Snapshot memory takerTakerToken = BalanceSnapshot.take({ owner: taker, token: defaultOrder.takerToken });
        Snapshot memory takerMakerToken = BalanceSnapshot.take({ owner: taker, token: defaultOrder.makerToken });
        Snapshot memory makerTakerToken = BalanceSnapshot.take({ owner: maker, token: defaultOrder.takerToken });
        Snapshot memory makerMakerToken = BalanceSnapshot.take({ owner: maker, token: defaultOrder.makerToken });
        Snapshot memory recTakerToken = BalanceSnapshot.take({ owner: recipient, token: defaultOrder.takerToken });
        Snapshot memory recMakerToken = BalanceSnapshot.take({ owner: recipient, token: defaultOrder.makerToken });

        // craft the `flagAndPeriod` of the defaultOrder for BestBuy case
        uint256 flags = FLG_PARTIAL_FILL_MASK;
        defaultOrder.flagsAndPeriod = flags;

        defaultTakerSig = signConOrder(takerPrivateKey, defaultOrder, address(conditionalSwap));

        vm.expectEmit(true, true, true, true);
        emit ConditionalOrderFilled(
            getConOrderHash(defaultOrder),
            defaultOrder.taker,
            defaultOrder.maker,
            defaultOrder.takerToken,
            defaultOrder.takerTokenAmount,
            defaultOrder.makerToken,
            defaultOrder.makerTokenAmount,
            recipient
        );

        vm.startPrank(maker);
        conditionalSwap.fillConOrder(defaultOrder, defaultTakerSig, defaultOrder.takerTokenAmount, defaultOrder.makerTokenAmount, defaultSettlementData);
        vm.stopPrank();

        takerTakerToken.assertChange(-int256(defaultOrder.takerTokenAmount));
        takerMakerToken.assertChange(int256(0));
        makerTakerToken.assertChange(int256(defaultOrder.takerTokenAmount));
        makerMakerToken.assertChange(-int256(defaultOrder.makerTokenAmount));
        recTakerToken.assertChange(int256(0));
        recMakerToken.assertChange(int256(defaultOrder.makerTokenAmount));
    }

    function testRepaymentOrDCAOrder() external {
        Snapshot memory takerTakerToken = BalanceSnapshot.take({ owner: taker, token: defaultOrder.takerToken });
        Snapshot memory takerMakerToken = BalanceSnapshot.take({ owner: taker, token: defaultOrder.makerToken });
        Snapshot memory makerTakerToken = BalanceSnapshot.take({ owner: maker, token: defaultOrder.takerToken });
        Snapshot memory makerMakerToken = BalanceSnapshot.take({ owner: maker, token: defaultOrder.makerToken });
        Snapshot memory recTakerToken = BalanceSnapshot.take({ owner: recipient, token: defaultOrder.takerToken });
        Snapshot memory recMakerToken = BalanceSnapshot.take({ owner: recipient, token: defaultOrder.makerToken });

        // craft the `flagAndPeriod` of the defaultOrder for BestBuy case
        uint256 flags = FLG_SINGLE_AMOUNT_CAP_MASK | FLG_PERIODIC_MASK | FLG_PARTIAL_FILL_MASK;
        uint256 period = 12 hours;
        defaultOrder.flagsAndPeriod = flags | period;

        uint256 numberOfCycles = (defaultExpiry - block.timestamp) / period;

        defaultTakerSig = signConOrder(takerPrivateKey, defaultOrder, address(conditionalSwap));

        vm.expectEmit(true, true, true, true);
        emit ConditionalOrderFilled(
            getConOrderHash(defaultOrder),
            defaultOrder.taker,
            defaultOrder.maker,
            defaultOrder.takerToken,
            defaultOrder.takerTokenAmount,
            defaultOrder.makerToken,
            defaultOrder.makerTokenAmount,
            recipient
        );

        vm.startPrank(maker);
        for (uint256 i; i < numberOfCycles; ++i) {
            conditionalSwap.fillConOrder(defaultOrder, defaultTakerSig, defaultOrder.takerTokenAmount, defaultOrder.makerTokenAmount, defaultSettlementData);
            vm.warp(block.timestamp + period);
        }
        vm.stopPrank();

        takerTakerToken.assertChange(-int256(defaultOrder.takerTokenAmount) * int256(numberOfCycles));
        takerMakerToken.assertChange(int256(0));
        makerTakerToken.assertChange(int256(defaultOrder.takerTokenAmount) * int256(numberOfCycles));
        makerMakerToken.assertChange(-int256(defaultOrder.makerTokenAmount) * int256(numberOfCycles));
        recTakerToken.assertChange(int256(0));
        recMakerToken.assertChange(int256(defaultOrder.makerTokenAmount) * int256(numberOfCycles));
    }

    function testCannotFillExpiredOrder() public {
        vm.warp(defaultOrder.expiry + 1);

        vm.expectRevert(IConditionalSwap.ExpiredOrder.selector);
        vm.startPrank(maker);
        conditionalSwap.fillConOrder(defaultOrder, defaultTakerSig, defaultOrder.takerTokenAmount, defaultOrder.makerTokenAmount, defaultSettlementData);
        vm.stopPrank();
    }

    function testCannotFillOrderByInvalidOderMaker() public {
        address invalidOrderMaker = makeAddr("invalidOrderMaker");

        vm.expectRevert(IConditionalSwap.NotOrderMaker.selector);
        vm.startPrank(invalidOrderMaker);
        conditionalSwap.fillConOrder(defaultOrder, defaultTakerSig, defaultOrder.takerTokenAmount, defaultOrder.makerTokenAmount, defaultSettlementData);
        vm.stopPrank();
    }

    function testCannotFillOrderWithZeroTakerTokenAmount() public {
        vm.expectRevert(IConditionalSwap.ZeroTokenAmount.selector);
        vm.startPrank(maker);
        conditionalSwap.fillConOrder(defaultOrder, defaultTakerSig, 0, defaultOrder.makerTokenAmount, defaultSettlementData);
        vm.stopPrank();
    }

    function testCannotFillOrderWithInvalidTotalTakerTokenAmount() public {
        // craft the `flagAndPeriod` of the defaultOrder for BestBuy case
        uint256 flags = FLG_PARTIAL_FILL_MASK;
        defaultOrder.flagsAndPeriod = flags;

        defaultTakerSig = signConOrder(takerPrivateKey, defaultOrder, address(conditionalSwap));

        vm.startPrank(maker);
        // the first fill with full takerTokenAmount
        conditionalSwap.fillConOrder(defaultOrder, defaultTakerSig, defaultOrder.takerTokenAmount, defaultOrder.makerTokenAmount, defaultSettlementData);

        vm.expectRevert(IConditionalSwap.InvalidTakingAmount.selector);
        // The second fill with 1 takerTokenAmount would exceed the total cap this time.
        conditionalSwap.fillConOrder(defaultOrder, defaultTakerSig, 1, defaultOrder.makerTokenAmount, defaultSettlementData);
        vm.stopPrank();
    }

    function testCannotFillOrderWithInvalidSingleTakerTokenAmount() public {
        // craft the `flagAndPeriod` of the defaultOrder for BestBuy case
        uint256 flags = FLG_SINGLE_AMOUNT_CAP_MASK | FLG_PERIODIC_MASK | FLG_PARTIAL_FILL_MASK;
        uint256 period = 12 hours;
        defaultOrder.flagsAndPeriod = flags | period;

        defaultTakerSig = signConOrder(takerPrivateKey, defaultOrder, address(conditionalSwap));

        vm.expectRevert(IConditionalSwap.InvalidTakingAmount.selector);
        vm.startPrank(maker);
        conditionalSwap.fillConOrder(defaultOrder, defaultTakerSig, defaultOrder.takerTokenAmount + 1, defaultOrder.makerTokenAmount, defaultSettlementData);
        vm.stopPrank();
    }

    function testCannotFillOrderWithInvalidZeroRecipient() public {
        defaultOrder.recipient = payable(address(0));

        vm.expectRevert(IConditionalSwap.InvalidRecipient.selector);
        vm.startPrank(maker);
        conditionalSwap.fillConOrder(defaultOrder, defaultTakerSig, defaultOrder.takerTokenAmount, defaultOrder.makerTokenAmount, defaultSettlementData);
        vm.stopPrank();
    }

    function testCannotFillOrderWithIncorrectSignature() public {
        uint256 randomPrivateKey = 1234;
        bytes memory randomEOASig = signConOrder(randomPrivateKey, defaultOrder, address(conditionalSwap));

        vm.expectRevert(IConditionalSwap.InvalidSignature.selector);
        vm.startPrank(maker);
        conditionalSwap.fillConOrder(defaultOrder, randomEOASig, defaultOrder.takerTokenAmount, defaultOrder.makerTokenAmount, defaultSettlementData);
        vm.stopPrank();
    }

    function testCannotFillOrderWithinSamePeriod() public {
        // craft the `flagAndPeriod` of the defaultOrder for BestBuy case
        uint256 flags = FLG_SINGLE_AMOUNT_CAP_MASK | FLG_PERIODIC_MASK | FLG_PARTIAL_FILL_MASK;
        uint256 period = 12 hours;
        defaultOrder.flagsAndPeriod = flags | period;

        defaultTakerSig = signConOrder(takerPrivateKey, defaultOrder, address(conditionalSwap));
        vm.startPrank(maker);
        conditionalSwap.fillConOrder(defaultOrder, defaultTakerSig, defaultOrder.takerTokenAmount, defaultOrder.makerTokenAmount, defaultSettlementData);
        vm.warp(block.timestamp + 1);
        vm.expectRevert(IConditionalSwap.InsufficientTimePassed.selector);
        conditionalSwap.fillConOrder(defaultOrder, defaultTakerSig, defaultOrder.takerTokenAmount, defaultOrder.makerTokenAmount, defaultSettlementData);
        vm.stopPrank();
    }

    function testCannotFillOrderWithInvalidSettlementType() public {
        bytes memory settlementData = hex"02";

        defaultTakerSig = signConOrder(takerPrivateKey, defaultOrder, address(conditionalSwap));

        vm.expectRevert(IConditionalSwap.InvalidSettlementType.selector);
        vm.startPrank(maker);
        conditionalSwap.fillConOrder(defaultOrder, defaultTakerSig, defaultOrder.takerTokenAmount, defaultOrder.makerTokenAmount, settlementData);
        vm.stopPrank();
    }

    function testCannotFillOrderWithInvalidMakingAmount() public {
        defaultTakerSig = signConOrder(takerPrivateKey, defaultOrder, address(conditionalSwap));

        vm.expectRevert(IConditionalSwap.InvalidMakingAmount.selector);
        vm.startPrank(maker);
        conditionalSwap.fillConOrder(defaultOrder, defaultTakerSig, defaultOrder.takerTokenAmount, defaultOrder.makerTokenAmount - 1, defaultSettlementData);
        vm.stopPrank();
    }
}
