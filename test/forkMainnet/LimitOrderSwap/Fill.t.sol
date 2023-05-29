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
        limitOrderSwap.fillLimitOrder({
            order: defaultOrder,
            makerSignature: defaultMakerSig,
            takerTokenAmount: defaultOrder.takerTokenAmount,
            makerTokenAmount: defaultOrder.makerTokenAmount,
            recipient: recipient,
            extraAction: bytes(""),
            takerTokenPermit: defaultPermit
        });

        takerTakerToken.assertChange(-int256(defaultOrder.takerTokenAmount));
        takerMakerToken.assertChange(int256(0));
        makerTakerToken.assertChange(int256(defaultOrder.takerTokenAmount));
        makerMakerToken.assertChange(-int256(defaultOrder.makerTokenAmount));
        recTakerToken.assertChange(int256(0));
        recMakerToken.assertChange(int256(defaultOrder.makerTokenAmount - fee));
        feeCollectorBal.assertChange(int256(fee));
    }

    function testFullyFillLimitOrderUsingAMM() public {
        address[] memory defaultPath = new address[](2);
        defaultPath[0] = DAI_ADDRESS;
        defaultPath[1] = USDT_ADDRESS;

        uint256 fee = (defaultOrder.makerTokenAmount * defaultFeeFactor) / Constant.BPS_MAX;

        IUniswapRouterV2 router = IUniswapRouterV2(UNISWAP_V2_ADDRESS);
        uint256[] memory amounts = router.getAmountsOut(defaultOrder.makerTokenAmount - fee, defaultPath);
        uint256 expectedOut = amounts[amounts.length - 1];

        LimitOrder memory order = defaultOrder;
        order.takerTokenAmount = expectedOut;

        bytes memory makerSig = _signLimitOrder(makerPrivateKey, order);

        bytes memory makerSpecificData = abi.encode(defaultExpiry, defaultPath);
        bytes memory strategyData = abi.encode(UNISWAP_V2_ADDRESS, makerSpecificData);
        bytes memory extraAction = abi.encode(address(mockLimitOrderTaker), strategyData);

        vm.prank(address(mockLimitOrderTaker));
        limitOrderSwap.fillLimitOrder({
            order: order,
            makerSignature: makerSig,
            takerTokenAmount: order.takerTokenAmount,
            makerTokenAmount: order.makerTokenAmount,
            recipient: address(mockLimitOrderTaker),
            extraAction: extraAction,
            takerTokenPermit: defaultPermit
        });
    }

    function testFillWithBetterPrice() public {
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
        limitOrderSwap.fillLimitOrder({
            order: defaultOrder,
            makerSignature: defaultMakerSig,
            takerTokenAmount: actualTokenAmount,
            makerTokenAmount: defaultOrder.makerTokenAmount,
            recipient: recipient,
            extraAction: bytes(""),
            takerTokenPermit: defaultPermit
        });

        takerTakerToken.assertChange(-int256(actualTokenAmount));
        takerMakerToken.assertChange(int256(0));
        makerTakerToken.assertChange(int256(actualTokenAmount));
        makerMakerToken.assertChange(-int256(defaultOrder.makerTokenAmount));
        recTakerToken.assertChange(int256(0));
        recMakerToken.assertChange(int256(defaultOrder.makerTokenAmount - fee));
        feeCollectorBal.assertChange(int256(fee));
    }

    function testCannotFillWithNotEnoughTakingAmount() public {
        // fill with less than required
        uint256 actualTokenAmount = defaultOrder.takerTokenAmount - 100;

        vm.expectRevert(ILimitOrderSwap.InvalidTakingAmount.selector);
        vm.prank(taker);
        limitOrderSwap.fillLimitOrder({
            order: defaultOrder,
            makerSignature: defaultMakerSig,
            takerTokenAmount: actualTokenAmount,
            makerTokenAmount: defaultOrder.makerTokenAmount,
            recipient: recipient,
            extraAction: bytes(""),
            takerTokenPermit: defaultPermit
        });
    }

    // case : fill an order with extra action (RFQ)
    // case : partial fill
    // cast : WETH as input
    // x order filled
    // x order expired
    // x not valid taker
    // x wrong maker sig
    // x invalid fill permission (replayed, expired, invalid amount)
}
