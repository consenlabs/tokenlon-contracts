// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;
pragma abicoder v2;

import "test/forkMainnet/AMMStrategy/Setup.t.sol";
import "test/utils/BalanceSnapshot.sol";

contract TestAMMStrategyTradeWithSingleAMM is TestAMMStrategy {
    using BalanceSnapshot for BalanceSnapshot.Snapshot;

    function testOnlyEntryPointCanExecuteStrategy() public {
        vm.expectRevert("only entry point");
        ammStrategy.executeStrategy(assets[0], 100, assets[1], "");
    }

    function testTradeWithUniswapV2() public {
        AMMStrategyEntry memory entry = DEFAULT_ENTRY;
        BalanceSnapshot.Snapshot memory entryPointTakerAsset = BalanceSnapshot.take(address(entryPoint), entry.takerAssetAddr);
        BalanceSnapshot.Snapshot memory ammStrategyTakerAsset = BalanceSnapshot.take(address(ammStrategy), entry.takerAssetAddr);

        // entryPoint sends taker asset to ammStrategy befor calling executeStrategy
        _sendTakerAssetFromEntryPoint(entry.takerAssetAddr, entry.takerAssetAmount);

        entryPointTakerAsset.assertChange(-int256(entry.takerAssetAmount));
        ammStrategyTakerAsset.assertChange(int256(entry.takerAssetAmount));

        (address srcToken, uint256 inputAmount, address targetToken, bytes memory data, ) = _genUniswapV2TradePayload(entry);

        entryPointTakerAsset = BalanceSnapshot.take(address(entryPoint), entry.takerAssetAddr);
        ammStrategyTakerAsset = BalanceSnapshot.take(address(ammStrategy), entry.takerAssetAddr);
        BalanceSnapshot.Snapshot memory entryPointMakerAsset = BalanceSnapshot.take(address(entryPoint), entry.makerAssetAddr);
        BalanceSnapshot.Snapshot memory ammStrategyMakerAsset = BalanceSnapshot.take(address(ammStrategy), entry.makerAssetAddr);

        vm.prank(entryPoint);
        // ammStrategy swaps taker asset to maker asset and sends maker asset to entry point
        ammStrategy.executeStrategy(srcToken, inputAmount, targetToken, data);
        vm.stopPrank();
        entryPointTakerAsset.assertChange(0);
        ammStrategyTakerAsset.assertChange(-int256(entry.takerAssetAmount));
        entryPointMakerAsset.assertChangeGt(0);
        ammStrategyMakerAsset.assertChange(0);
    }

    function testTradeWithUniswapV3() public {
        AMMStrategyEntry memory entry = DEFAULT_ENTRY;
        entry.makerAddr = UNISWAP_V3_ADDRESS;
        BalanceSnapshot.Snapshot memory entryPointTakerAsset = BalanceSnapshot.take(address(entryPoint), entry.takerAssetAddr);
        BalanceSnapshot.Snapshot memory ammStrategyTakerAsset = BalanceSnapshot.take(address(ammStrategy), entry.takerAssetAddr);

        // entryPoint sends taker asset to ammStrategy befor calling executeStrategy
        _sendTakerAssetFromEntryPoint(entry.takerAssetAddr, entry.takerAssetAmount);

        entryPointTakerAsset.assertChange(-int256(entry.takerAssetAmount));
        ammStrategyTakerAsset.assertChange(int256(entry.takerAssetAmount));

        (address srcToken, uint256 inputAmount, address targetToken, bytes memory data, ) = _genUniswapV3TradePayload(entry);

        entryPointTakerAsset = BalanceSnapshot.take(address(entryPoint), entry.takerAssetAddr);
        ammStrategyTakerAsset = BalanceSnapshot.take(address(ammStrategy), entry.takerAssetAddr);
        BalanceSnapshot.Snapshot memory entryPointMakerAsset = BalanceSnapshot.take(address(entryPoint), entry.makerAssetAddr);
        BalanceSnapshot.Snapshot memory ammStrategyMakerAsset = BalanceSnapshot.take(address(ammStrategy), entry.makerAssetAddr);

        vm.prank(entryPoint);
        // ammStrategy swaps taker asset to maker asset and sends maker asset to entry point
        ammStrategy.executeStrategy(srcToken, inputAmount, targetToken, data);
        vm.stopPrank();
        entryPointTakerAsset.assertChange(0);
        ammStrategyTakerAsset.assertChange(-int256(entry.takerAssetAmount));
        entryPointMakerAsset.assertChangeGt(0);
        ammStrategyMakerAsset.assertChange(0);
    }
}
