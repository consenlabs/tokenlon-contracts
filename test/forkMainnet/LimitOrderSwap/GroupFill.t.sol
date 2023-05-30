// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { ILimitOrderSwap } from "contracts/interfaces/ILimitOrderSwap.sol";
import { LimitOrder, getLimitOrderHash } from "contracts/libraries/LimitOrder.sol";
import { BalanceSnapshot, Snapshot } from "test/utils/BalanceSnapshot.sol";
import { LimitOrderSwapTest } from "test/forkMainnet/LimitOrderSwap/Setup.t.sol";

contract GroupFillTest is LimitOrderSwapTest {
    using BalanceSnapshot for Snapshot;

    address arbitrageur = makeAddr("arbitrageur");
    uint256[] makerPrivateKeys = [1001, 1002, 1003, 1004];
    address payable[] makers = new address payable[](makerPrivateKeys.length);

    function setUp() public override {
        super.setUp();
        for (uint256 i = 0; i < makerPrivateKeys.length; ++i) {
            makers[i] = payable(vm.addr(makerPrivateKeys[i]));
            deal(makers[i], 100 ether);
            setTokenBalanceAndApprove(makers[i], address(limitOrderSwap), tokens, 100000);
        }
    }

    function testGroupFillWithProfit() public {
        bytes[] memory makerSigs = new bytes[](2);
        LimitOrder[] memory orders = new LimitOrder[](2);
        uint256[] memory makerTokenAmounts = new uint256[](2);

        // order0 10 DAI -> 10 USDT
        orders[0] = LimitOrder({
            taker: address(0),
            maker: makers[0],
            takerToken: USDT_ADDRESS,
            takerTokenAmount: 10 * 1e6,
            makerToken: DAI_ADDRESS,
            makerTokenAmount: 10 ether,
            makerTokenPermit: defaultPermit,
            feeFactor: 0,
            expiry: defaultExpiry,
            salt: defaultSalt
        });
        makerSigs[0] = _signLimitOrder(makerPrivateKeys[0], orders[0]);
        makerTokenAmounts[0] = orders[0].makerTokenAmount;
        Snapshot memory maker0TakerToken = BalanceSnapshot.take({ owner: orders[0].maker, token: orders[0].takerToken });
        Snapshot memory maker0MakerToken = BalanceSnapshot.take({ owner: orders[0].maker, token: orders[0].makerToken });

        // order1 10 USDT -> 8 DAI
        orders[1] = LimitOrder({
            taker: address(0),
            maker: makers[1],
            takerToken: DAI_ADDRESS,
            takerTokenAmount: 8 ether,
            makerToken: USDT_ADDRESS,
            makerTokenAmount: 10 * 1e6,
            makerTokenPermit: defaultPermit,
            feeFactor: 0,
            expiry: defaultExpiry,
            salt: defaultSalt
        });
        makerSigs[1] = _signLimitOrder(makerPrivateKeys[1], orders[1]);
        makerTokenAmounts[1] = orders[1].makerTokenAmount;
        Snapshot memory maker1TakerToken = BalanceSnapshot.take({ owner: orders[1].maker, token: orders[1].takerToken });
        Snapshot memory maker1MakerToken = BalanceSnapshot.take({ owner: orders[1].maker, token: orders[1].makerToken });

        // the profit of this group for arbitrageur is 2 DAI
        address[] memory profitTokens = new address[](1);
        profitTokens[0] = DAI_ADDRESS;
        Snapshot memory arbProfitToken = BalanceSnapshot.take({ owner: arbitrageur, token: DAI_ADDRESS });
        vm.prank(arbitrageur, arbitrageur);
        limitOrderSwap.fillLimitOrderGroup({ orders: orders, makerSignatures: makerSigs, makerTokenAmounts: makerTokenAmounts, profitTokens: profitTokens });

        // two makers should give/get exactly as order specified
        maker0TakerToken.assertChange(int256(orders[0].takerTokenAmount));
        maker0MakerToken.assertChange(-int256(orders[0].makerTokenAmount));
        maker1TakerToken.assertChange(int256(orders[1].takerTokenAmount));
        maker1MakerToken.assertChange(-int256(orders[1].makerTokenAmount));
        // arbitrageur gets 2 DAI as profit
        arbProfitToken.assertChange(int256(2 ether));
    }

    function testPartialFillLargeOrderWithSmallOrders() public {
        bytes[] memory makerSigs = new bytes[](3);
        LimitOrder[] memory orders = new LimitOrder[](3);
        uint256[] memory makerTokenAmounts = new uint256[](3);

        // order0 10 DAI -> 10 USDT
        orders[0] = LimitOrder({
            taker: address(0),
            maker: makers[0],
            takerToken: USDT_ADDRESS,
            takerTokenAmount: 10 * 1e6,
            makerToken: DAI_ADDRESS,
            makerTokenAmount: 10 ether,
            makerTokenPermit: defaultPermit,
            feeFactor: 0,
            expiry: defaultExpiry,
            salt: defaultSalt
        });
        makerSigs[0] = _signLimitOrder(makerPrivateKeys[0], orders[0]);
        makerTokenAmounts[0] = orders[0].makerTokenAmount;
        Snapshot memory maker0TakerToken = BalanceSnapshot.take({ owner: orders[0].maker, token: orders[0].takerToken });
        Snapshot memory maker0MakerToken = BalanceSnapshot.take({ owner: orders[0].maker, token: orders[0].makerToken });

        // order1 35 DAI -> 35 USDT
        orders[1] = LimitOrder({
            taker: address(0),
            maker: makers[1],
            takerToken: USDT_ADDRESS,
            takerTokenAmount: 35 * 1e6,
            makerToken: DAI_ADDRESS,
            makerTokenAmount: 35 ether,
            makerTokenPermit: defaultPermit,
            feeFactor: 0,
            expiry: defaultExpiry,
            salt: defaultSalt
        });
        makerSigs[1] = _signLimitOrder(makerPrivateKeys[1], orders[1]);
        makerTokenAmounts[1] = orders[1].makerTokenAmount;
        Snapshot memory maker1TakerToken = BalanceSnapshot.take({ owner: orders[1].maker, token: orders[1].takerToken });
        Snapshot memory maker1MakerToken = BalanceSnapshot.take({ owner: orders[1].maker, token: orders[1].makerToken });

        // order2 1000 USDT -> 1000 DAI
        orders[2] = LimitOrder({
            taker: address(0),
            maker: makers[2],
            takerToken: DAI_ADDRESS,
            takerTokenAmount: 1000 ether,
            makerToken: USDT_ADDRESS,
            makerTokenAmount: 1000 * 1e6,
            makerTokenPermit: defaultPermit,
            feeFactor: 0,
            expiry: defaultExpiry,
            salt: defaultSalt
        });
        makerSigs[2] = _signLimitOrder(makerPrivateKeys[2], orders[2]);
        makerTokenAmounts[2] = orders[0].takerTokenAmount + orders[1].takerTokenAmount;
        Snapshot memory maker2TakerToken = BalanceSnapshot.take({ owner: orders[2].maker, token: orders[2].takerToken });
        Snapshot memory maker2MakerToken = BalanceSnapshot.take({ owner: orders[2].maker, token: orders[2].makerToken });

        address[] memory profitTokens;
        limitOrderSwap.fillLimitOrderGroup({ orders: orders, makerSignatures: makerSigs, makerTokenAmounts: makerTokenAmounts, profitTokens: profitTokens });

        // small orders maker should be fully filled
        maker0TakerToken.assertChange(int256(orders[0].takerTokenAmount));
        maker0MakerToken.assertChange(-int256(orders[0].makerTokenAmount));
        maker1TakerToken.assertChange(int256(orders[1].takerTokenAmount));
        maker1MakerToken.assertChange(-int256(orders[1].makerTokenAmount));
        // large order maker should gets partial filled
        maker2TakerToken.assertChange(int256(orders[0].makerTokenAmount + orders[1].makerTokenAmount));
        maker2MakerToken.assertChange(-int256(makerTokenAmounts[2]));
        // check order filled amount
        assertEq(limitOrderSwap.orderHashToMakerTokenFilledAmount(getLimitOrderHash(orders[2])), makerTokenAmounts[2]);
    }

    // one of order should specify taker address
    // price mismatch should cause fail
    // extra actions with AMM interactions
}
