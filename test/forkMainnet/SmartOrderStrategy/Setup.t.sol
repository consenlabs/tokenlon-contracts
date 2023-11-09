// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";
import { SmartOrderStrategy } from "contracts/SmartOrderStrategy.sol";
import { Tokens } from "test/utils/Tokens.sol";
import { BalanceUtil } from "test/utils/BalanceUtil.sol";

contract SmartOrderStrategyTest is Test, Tokens, BalanceUtil {
    address strategyOwner = makeAddr("strategyOwner");
    address genericSwap = makeAddr("genericSwap");
    address defaultInputToken = USDC_ADDRESS;
    address defaultOutputToken = WETH_ADDRESS;
    uint256 defaultInputAmount = 1000;
    uint128 defaultInputRatio = 5000;
    uint256 defaultExpiry = block.timestamp + 100;
    bytes defaultOpsData;
    address[] defaultUniV2Path = [USDC_ADDRESS, WETH_ADDRESS];
    address[] tokenList = [USDT_ADDRESS, USDC_ADDRESS, WETH_ADDRESS, WBTC_ADDRESS];
    address[] ammList = [UNISWAP_SWAP_ROUTER_02_ADDRESS, SUSHISWAP_ADDRESS, CURVE_TRICRYPTO2_POOL_ADDRESS];

    SmartOrderStrategy smartOrderStrategy;

    function setUp() public virtual {
        // Deploy and setup SmartOrderStrategy
        smartOrderStrategy = new SmartOrderStrategy(strategyOwner, genericSwap, WETH_ADDRESS);
        vm.prank(strategyOwner);
        smartOrderStrategy.approveTokens(tokenList, ammList);

        // Make genericSwap rich to provide fund for strategy contract
        deal(genericSwap, 100 ether);
        for (uint256 i = 0; i < tokenList.length; i++) {
            setERC20Balance(tokenList[i], genericSwap, 10000);
        }

        SmartOrderStrategy.Operation[] memory operations = new SmartOrderStrategy.Operation[](1);
        defaultOpsData = abi.encode(operations);

        vm.label(UNISWAP_UNIVERSAL_ROUTER_ADDRESS, "UniswapUniversalRouter");
    }
}
