// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { ILimitOrderSwap } from "contracts/interfaces/ILimitOrderSwap.sol";
import { Constant } from "contracts/libraries/Constant.sol";
import { getLimitOrderHash } from "contracts/libraries/LimitOrder.sol";
import { BalanceSnapshot, Snapshot } from "test/utils/BalanceSnapshot.sol";
import { LimitOrderSwapTest } from "test/forkMainnet/LimitOrderSwap/Setup.t.sol";

contract FullOrKillTest is LimitOrderSwapTest {
    using BalanceSnapshot for Snapshot;

    function testFillWithFOK() public {
        Snapshot memory takerTakerToken = BalanceSnapshot.take({ owner: taker, token: defaultOrder.takerToken });
        Snapshot memory takerMakerToken = BalanceSnapshot.take({ owner: taker, token: defaultOrder.makerToken });
        Snapshot memory makerTakerToken = BalanceSnapshot.take({ owner: defaultOrder.maker, token: defaultOrder.takerToken });
        Snapshot memory makerMakerToken = BalanceSnapshot.take({ owner: defaultOrder.maker, token: defaultOrder.makerToken });
        Snapshot memory recTakerToken = BalanceSnapshot.take({ owner: recipient, token: defaultOrder.takerToken });
        Snapshot memory recMakerToken = BalanceSnapshot.take({ owner: recipient, token: defaultOrder.makerToken });
        Snapshot memory fcMakerToken = BalanceSnapshot.take({ owner: feeCollector, token: defaultOrder.makerToken });

        // fill FOK default order with 1/10 amount
        uint256 traderMakingAmount = defaultOrder.makerTokenAmount / 10;
        uint256 traderTakingAmount = defaultOrder.takerTokenAmount / 10;
        uint256 fee = (traderMakingAmount * defaultFeeFactor) / Constant.BPS_MAX;

        vm.expectEmit(true, true, true, true);
        emit LimitOrderFilled(
            getLimitOrderHash(defaultOrder),
            taker,
            defaultOrder.maker,
            defaultOrder.takerToken,
            traderTakingAmount,
            defaultOrder.makerToken,
            traderMakingAmount - fee,
            fee,
            recipient
        );

        vm.prank(taker);
        limitOrderSwap.fillLimitOrderFullOrKill({
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

        takerTakerToken.assertChange(-int256(traderTakingAmount));
        takerMakerToken.assertChange(int256(0));
        makerTakerToken.assertChange(int256(traderTakingAmount));
        makerMakerToken.assertChange(-int256(traderMakingAmount));
        recTakerToken.assertChange(int256(0));
        recMakerToken.assertChange(int256(traderMakingAmount - fee));
        fcMakerToken.assertChange(int256(fee));
    }

    function testCannotFillFOKIfNotEnough() public {
        // fill FOK default order with larger volume
        uint256 traderMakingAmount = defaultOrder.makerTokenAmount * 2;
        uint256 traderTakingAmount = defaultOrder.takerTokenAmount * 2;

        vm.expectRevert(ILimitOrderSwap.NotEnoughForFill.selector);
        vm.prank(taker);
        limitOrderSwap.fillLimitOrderFullOrKill({
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
    }

    function testCannotFillFOKIfNotEnoughEvenPriceIsBetter() public {
        // fill FOK default order with larger volume, also provide better price (takingAmount is 20x)
        uint256 traderMakingAmount = defaultOrder.makerTokenAmount * 2;
        uint256 traderTakingAmount = defaultOrder.takerTokenAmount * 20;

        vm.expectRevert(ILimitOrderSwap.NotEnoughForFill.selector);
        vm.prank(taker);
        limitOrderSwap.fillLimitOrderFullOrKill({
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
    }
}
