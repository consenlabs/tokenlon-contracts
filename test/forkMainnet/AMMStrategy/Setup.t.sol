// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IUniswapV3SwapRouter } from "contracts/interfaces/IUniswapV3SwapRouter.sol";
import { IUniswapRouterV2 } from "contracts/interfaces/IUniswapRouterV2.sol";
import { AMMStrategy } from "contracts/AMMStrategy.sol";
import { IAMMStrategy } from "contracts/interfaces/IAMMStrategy.sol";
import { BalanceUtil } from "test/utils/BalanceUtil.sol";
import { Tokens } from "test/utils/Tokens.sol";

contract TestAMMStrategy is Tokens, BalanceUtil {
    using SafeERC20 for IERC20;

    struct AMMStrategyEntry {
        address takerAssetAddr;
        uint256 takerAssetAmount;
        address makerAddr;
        address makerAssetAddr;
        bytes makerSpecificData;
        uint256 deadline;
        bool isDirectToEntryPoint;
        uint24 feeFactor;
    }

    address entryPoint = makeAddr("entryPoint");
    address owner = makeAddr("owner");
    address[] wallets = [entryPoint, owner];
    address[] amms = [address(SUSHISWAP_ADDRESS), UNISWAP_V2_ADDRESS, UNISWAP_V3_ADDRESS, BALANCER_V2_ADDRESS, CURVE_USDT_POOL_ADDRESS];
    bool[] usePermit2InAMMs = [false, false, false, false, false];
    address[] assets = [address(WETH_ADDRESS), USDT_ADDRESS, USDC_ADDRESS, DAI_ADDRESS, WBTC_ADDRESS, LON_ADDRESS, ANKRETH_ADDRESS];
    uint256 DEADLINE = block.timestamp + 1;
    uint16 DEFAULT_FEE_FACTOR = 500;

    AMMStrategy ammStrategy;
    AMMStrategyEntry DEFAULT_ENTRY;

    // effectively a "beforeEach" block
    function setUp() public {
        dealWallets(100);
        ammStrategy = new AMMStrategy(owner, entryPoint, UNISWAP_PERMIT2_ADDRESS, amms);
        vm.prank(owner);
        ammStrategy.approveTokens(assets, amms, usePermit2InAMMs, type(uint256).max);
        // Set token balance and approve
        for (uint256 i = 0; i < tokens.length; ++i) {
            setERC20Balance(address(assets[i]), entryPoint, uint256(100));
        }

        DEFAULT_ENTRY = AMMStrategyEntry(
            address(dai), // takerAssetAddr
            uint256(100 * 1e18), // takerAssetAmount
            UNISWAP_V2_ADDRESS, // makerAddr
            address(usdt), // makerAssetAddr
            "", // makerSpecificData;
            DEADLINE, // deadline
            false, // isDirectToEntryPoint
            DEFAULT_FEE_FACTOR // fee factor
        );

        // Label addresses for easier debugging
        vm.label(owner, "Owner");
        vm.label(address(this), "TestingContract");
        vm.label(address(ammStrategy), "AMMStrategyContract");
        vm.label(UNISWAP_V2_ADDRESS, "UniswapV2");
        vm.label(SUSHISWAP_ADDRESS, "Sushiswap");
        vm.label(UNISWAP_V3_ADDRESS, "UniswapV3");
        vm.label(BALANCER_V2_ADDRESS, "BalancerV2");
        vm.label(CURVE_USDT_POOL_ADDRESS, "CurveUSDTPool");
    }

    /*********************************
     *          Test Helpers         *
     *********************************/
    function dealWallets(uint256 amount) internal {
        // Deal 100 ETH to each account
        for (uint256 i = 0; i < wallets.length; i++) {
            deal(wallets[i], amount);
        }
    }

    function _genUniswapV2TradePayload(AMMStrategyEntry memory entry)
        internal
        view
        returns (
            address inputToken,
            address outputToken,
            uint256 inputAmount,
            bytes memory data,
            IAMMStrategy.Operation memory operation
        )
    {
        require(entry.makerAddr == UNISWAP_V2_ADDRESS, "not a uniswap v2 operation");
        inputToken = entry.takerAssetAddr;
        inputAmount = entry.takerAssetAmount;
        outputToken = entry.makerAssetAddr;
        address[] memory path = new address[](2);
        path[0] = inputToken;
        path[1] = outputToken;
        bytes memory payload = abi.encodeCall(
            IUniswapRouterV2.swapExactTokensForTokens,
            (inputAmount, uint256(0), path, entry.isDirectToEntryPoint ? entryPoint : address(ammStrategy), entry.deadline)
        );
        IAMMStrategy.Operation[] memory operations = new IAMMStrategy.Operation[](1);
        operation = IAMMStrategy.Operation(entry.makerAddr, 0, payload);
        operations[0] = operation;

        data = abi.encode(operations);
    }

    function _genUniswapV3TradePayload(AMMStrategyEntry memory entry)
        internal
        view
        returns (
            address inputToken,
            address outputToken,
            uint256 inputAmount,
            bytes memory data,
            IAMMStrategy.Operation memory operation
        )
    {
        require(entry.makerAddr == UNISWAP_V3_ADDRESS, "not a uniswap v3 operation");
        inputToken = entry.takerAssetAddr;
        inputAmount = entry.takerAssetAmount;
        outputToken = entry.makerAssetAddr;
        IUniswapV3SwapRouter.ExactInputSingleParams memory params = IUniswapV3SwapRouter.ExactInputSingleParams({
            tokenIn: inputToken,
            tokenOut: outputToken,
            fee: entry.feeFactor,
            recipient: entry.isDirectToEntryPoint ? entryPoint : address(ammStrategy),
            deadline: entry.deadline,
            amountIn: inputAmount,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });
        bytes memory payload = abi.encodeCall(IUniswapV3SwapRouter.exactInputSingle, params);
        IAMMStrategy.Operation[] memory operations = new IAMMStrategy.Operation[](1);
        operation = IAMMStrategy.Operation(entry.makerAddr, 0, payload);
        operations[0] = operation;

        data = abi.encode(operations);
    }

    function _sendTakerAssetFromEntryPoint(address takerAssetAddr, uint256 takerAssetAmount) internal {
        vm.prank(entryPoint);
        IERC20(takerAssetAddr).safeTransfer(address(ammStrategy), takerAssetAmount);
        vm.stopPrank();
    }
}
