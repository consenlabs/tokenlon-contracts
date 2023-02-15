// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "test/forkMainnet/AMMStrategy/Setup.t.sol";
import "test/utils/BalanceSnapshot.sol";

contract TestAMMStrategyTradeSushiswap is TestAMMStrategy {
    using BalanceSnapshot for BalanceSnapshot.Snapshot;

    function testOnlyEntryPointCanExecuteStrategy() public {
        AMMStrategyEntry memory entry = DEFAULT_ENTRY;
        entry.makerAddr = SUSHISWAP_ADDRESS;
        (address srcToken, uint256 inputAmount, bytes memory data) = _genTradePayload(entry);
        vm.expectRevert("only entry point");
        ammStrategy.executeStrategy(srcToken, inputAmount, data);
    }

    function testTradeWithSingleHop() public {
        AMMStrategyEntry memory entry = DEFAULT_ENTRY;
        entry.makerAddr = SUSHISWAP_ADDRESS;
        BalanceSnapshot.Snapshot memory entryPointTakerAsset = BalanceSnapshot.take(address(entryPoint), entry.takerAssetAddr);
        BalanceSnapshot.Snapshot memory ammStrategyTakerAsset = BalanceSnapshot.take(address(ammStrategy), entry.takerAssetAddr);

        // entryPoint sends taker asset to ammStrategy befor calling executeStrategy
        _sendTakerAssetFromEntryPoint(entry.takerAssetAddr, entry.takerAssetAmount);

        entryPointTakerAsset.assertChange(-int256(entry.takerAssetAmount));
        ammStrategyTakerAsset.assertChange(int256(entry.takerAssetAmount));

        (address srcToken, uint256 inputAmount, bytes memory data) = _genTradePayload(entry);

        uint256 expectedOutAmount = ammQuoter.getMakerOutAmount(entry.makerAddr, entry.takerAssetAddr, entry.makerAssetAddr, entry.takerAssetAmount);

        entryPointTakerAsset = BalanceSnapshot.take(address(entryPoint), entry.takerAssetAddr);
        ammStrategyTakerAsset = BalanceSnapshot.take(address(ammStrategy), entry.takerAssetAddr);
        BalanceSnapshot.Snapshot memory entryPointMakerAsset = BalanceSnapshot.take(address(entryPoint), entry.makerAssetAddr);
        BalanceSnapshot.Snapshot memory ammStrategyMakerAsset = BalanceSnapshot.take(address(ammStrategy), entry.makerAssetAddr);

        vm.prank(entryPoint);
        // ammStrategy swaps taker asset to maker asset and sends maker asset to entry point
        ammStrategy.executeStrategy(srcToken, inputAmount, data);
        vm.stopPrank();

        entryPointTakerAsset.assertChange(0);
        ammStrategyTakerAsset.assertChange(-int256(entry.takerAssetAmount));
        entryPointMakerAsset.assertChange(int256(expectedOutAmount));
        ammStrategyMakerAsset.assertChange(0);
    }
}
