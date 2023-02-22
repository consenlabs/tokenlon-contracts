// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;
pragma abicoder v2;

import "contracts/interfaces/IAMMStrategy.sol";

import "test/forkMainnet/AMMStrategy/Setup.t.sol";
import "test/utils/BalanceSnapshot.sol";

contract TestAMMStrategyTradeWithMultiAMM is TestAMMStrategy {
    using BalanceSnapshot for BalanceSnapshot.Snapshot;

    function testTradeWithUniswapV2AndUniswapV3() public {
        AMMStrategyEntry memory entry = DEFAULT_ENTRY;
        uint256 totalAmount = entry.takerAssetAmount;
        AMMStrategyEntry memory entryForV2 = DEFAULT_ENTRY;
        entryForV2.takerAssetAmount = totalAmount / 2;
        AMMStrategyEntry memory entryForV3 = DEFAULT_ENTRY;
        entryForV3.makerAddr = UNISWAP_V3_ADDRESS;
        entryForV3.takerAssetAmount = totalAmount - totalAmount / 2;

        assertEq(entry.takerAssetAmount, entryForV2.takerAssetAmount + entryForV3.takerAssetAmount);

        BalanceSnapshot.Snapshot memory entryPointTakerAsset = BalanceSnapshot.take(address(entryPoint), entry.takerAssetAddr);
        BalanceSnapshot.Snapshot memory ammStrategyTakerAsset = BalanceSnapshot.take(address(ammStrategy), entry.takerAssetAddr);

        // entryPoint sends taker asset to ammStrategy befor calling executeStrategy
        _sendTakerAssetFromEntryPoint(entry.takerAssetAddr, entry.takerAssetAmount);

        entryPointTakerAsset.assertChange(-int256(entry.takerAssetAmount));
        ammStrategyTakerAsset.assertChange(int256(entry.takerAssetAmount));

        IAMMStrategy.Operation[] memory operations = new IAMMStrategy.Operation[](2);

        (, , , , IAMMStrategy.Operation memory operation1) = _genUniswapV2TradePayload(entryForV2);
        (, , , , IAMMStrategy.Operation memory operation2) = _genUniswapV3TradePayload(entryForV3);

        operations[0] = operation1;
        operations[1] = operation2;

        entryPointTakerAsset = BalanceSnapshot.take(address(entryPoint), entry.takerAssetAddr);
        ammStrategyTakerAsset = BalanceSnapshot.take(address(ammStrategy), entry.takerAssetAddr);
        BalanceSnapshot.Snapshot memory entryPointMakerAsset = BalanceSnapshot.take(address(entryPoint), entry.makerAssetAddr);
        BalanceSnapshot.Snapshot memory ammStrategyMakerAsset = BalanceSnapshot.take(address(ammStrategy), entry.makerAssetAddr);

        vm.prank(entryPoint);
        // ammStrategy swaps taker asset to maker asset and sends maker asset to entry point
        ammStrategy.executeStrategy(entry.takerAssetAddr, entry.takerAssetAmount, entry.makerAssetAddr, abi.encode(operations));
        vm.stopPrank();
        entryPointTakerAsset.assertChange(0);
        ammStrategyTakerAsset.assertChange(-int256(entry.takerAssetAmount));
        entryPointMakerAsset.assertChangeGt(0);
        ammStrategyMakerAsset.assertChange(0);
    }
}
