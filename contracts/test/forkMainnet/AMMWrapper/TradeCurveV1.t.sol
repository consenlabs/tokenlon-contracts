// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "contracts-test/forkMainnet/AMMWrapper/Setup.t.sol";
import "contracts-test/utils/BalanceSnapshot.sol";

contract TestAMMWrapperTradeCurveV1 is TestAMMWrapper {
    using BalanceSnapshot for BalanceSnapshot.Snapshot;

    function testTradeCurveV1() public {
        uint256 feeFactor = 0;
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        order.makerAddr = CURVE_USDT_POOL_ADDRESS;
        bytes memory sig = _signTrade(userPrivateKey, order);
        bytes memory payload; // Bypass stack too deep error
        {
            SpenderLibEIP712.SpendWithPermit memory takerAssetPermit = _createSpenderPermitFromOrder(order);
            bytes memory takerAssetPermitSig = signSpendWithPermit(
                userPrivateKey,
                takerAssetPermit,
                spender.EIP712_DOMAIN_SEPARATOR(),
                SignatureValidator.SignatureType.EIP712
            );
            payload = _genTradePayload(order, feeFactor, sig, takerAssetPermitSig);
        }
        BalanceSnapshot.Snapshot memory userTakerAsset = BalanceSnapshot.take(user, order.takerAssetAddr);
        BalanceSnapshot.Snapshot memory userMakerAsset = BalanceSnapshot.take(user, order.makerAssetAddr);

        vm.prank(relayer, relayer);
        userProxy.toAMM(payload);

        userTakerAsset.assertChange(-int256(order.takerAssetAmount));
        // FIXME assert balance change precisely
        userMakerAsset.assertChangeGt(int256(order.makerAssetAmount));
    }
}
