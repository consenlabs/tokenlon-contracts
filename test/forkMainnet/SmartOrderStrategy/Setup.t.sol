// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";
import { SmartOrderStrategy } from "contracts/SmartOrderStrategy.sol";
import { Tokens } from "test/utils/Tokens.sol";
import { BalanceUtil } from "test/utils/BalanceUtil.sol";
import { IUniswapV3Quoter } from "test/utils/IUniswapV3Quoter.sol";
import { UniswapV3 } from "test/utils/UniswapV3.sol";

contract SmartOrderStrategyTest is Test, Tokens, BalanceUtil {
    address strategyOwner = makeAddr("strategyOwner");
    address genericSwap = makeAddr("genericSwap");
    address defaultInputToken = USDC_ADDRESS;
    address defaultOutputToken = WETH_ADDRESS;
    uint256 defaultInputAmount = 1000;
    uint128 defaultInputRatio = 5000;
    uint256 defaultExpiry = block.timestamp + 100;
    bytes defaultOpsData;
    bytes encodedUniv3Path;
    address[] defaultUniV2Path = [defaultInputToken, defaultOutputToken];
    address[] tokenList = [USDT_ADDRESS, USDC_ADDRESS, WETH_ADDRESS, WBTC_ADDRESS];
    address[] ammList = [UNISWAP_SWAP_ROUTER_02_ADDRESS, CURVE_TRICRYPTO2_POOL_ADDRESS];

    uint24 defaultFee = 3000;
    uint24[] v3Fees = [defaultFee];

    SmartOrderStrategy smartOrderStrategy;
    IUniswapV3Quoter v3Quoter;

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

        deal(USDC_ADDRESS, address(smartOrderStrategy), 1 wei);
        deal(USDT_ADDRESS, address(smartOrderStrategy), 1 wei);
        deal(WETH_ADDRESS, address(smartOrderStrategy), 1 wei);
        deal(WBTC_ADDRESS, address(smartOrderStrategy), 1 wei);

        SmartOrderStrategy.Operation[] memory operations = new SmartOrderStrategy.Operation[](1);
        defaultOpsData = abi.encode(operations);

        v3Quoter = IUniswapV3Quoter(UNISWAP_V3_QUOTER_ADDRESS);
        encodedUniv3Path = UniswapV3.encodePath(defaultUniV2Path, v3Fees);

        vm.label(UNISWAP_UNIVERSAL_ROUTER_ADDRESS, "UniswapUniversalRouter");
    }
}
