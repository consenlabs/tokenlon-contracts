// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";
import { Tokens } from "test/utils/Tokens.sol";
import { BalanceUtil } from "test/utils/BalanceUtil.sol";
import { BalanceSnapshot } from "test/utils/BalanceSnapshot.sol";

import { Constant } from "contracts/libraries/Constant.sol";
import { AMMStrategy } from "contracts/AMMStrategy.sol";
import { Constant } from "contracts/libraries/Constant.sol";

import { IUniversalRouter } from "contracts/interfaces/IUniswapUniversalRouter.sol";
import { Commands } from "contracts/libraries/UniswapCommands.sol";
import { IWETH } from "contracts/interfaces/IWeth.sol";
import { IAMMStrategy } from "contracts/interfaces/IAMMStrategy.sol";
import { IStrategy } from "contracts/interfaces/IStrategy.sol";
import { IUniswapRouterV2 } from "contracts//interfaces/IUniswapRouterV2.sol";
import { IBalancerV2Vault } from "contracts/interfaces/IBalancerV2Vault.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract AMMStrategyTest is Test, Tokens, BalanceUtil {
    using SafeERC20 for IERC20;

    using BalanceSnapshot for BalanceSnapshot.Snapshot;

    address strategyAdmin = makeAddr("strategyAdmin");
    address genericSwap = address(this);
    uint256 defaultDeadline = block.timestamp + 1;
    address[] tokenList = [USDC_ADDRESS, cUSDC_ADDRESS, WETH_ADDRESS, WBTC_ADDRESS];
    address[] ammList = [UNISWAP_UNIVERSAL_ROUTER_ADDRESS, SUSHISWAP_ADDRESS, BALANCER_V2_ADDRESS, CURVE_USDT_POOL_ADDRESS, CURVE_TRICRYPTO2_POOL_ADDRESS];
    bool[] usePermit2InAMMs = [true, false, false, false, false];
    AMMStrategy ammStrategy;

    receive() external payable {}

    function setUp() public {
        ammStrategy = new AMMStrategy(strategyAdmin, genericSwap, WETH_ADDRESS, UNISWAP_PERMIT2_ADDRESS, ammList);
        vm.prank(strategyAdmin);
        ammStrategy.approveTokens(tokenList, ammList, usePermit2InAMMs, Constant.MAX_UINT);
        setBalance(genericSwap, tokenList, 100000);
        deal(genericSwap, 100 ether);

        vm.label(UNISWAP_UNIVERSAL_ROUTER_ADDRESS, "UniswapUniversalRouter");
        vm.label(SUSHISWAP_ADDRESS, "Sushiswap");
        vm.label(CURVE_USDT_POOL_ADDRESS, "CurveUSDTPool");
        vm.label(BALANCER_V2_ADDRESS, "BalancerV2");
        vm.label(UNISWAP_PERMIT2_ADDRESS, "UniswapPermit2");
        vm.label(WETH_ADDRESS, "WETH");
        vm.label(CURVE_TRICRYPTO2_POOL_ADDRESS, "CurveTriCryptoPool");
    }

    function testAMMStrategyTradeWithMultiAMM() public {
        // sushiSwap and curveV1
        address inputToken = USDC_ADDRESS;
        address outputToken = DAI_ADDRESS;
        uint256 inputAmount = 10 * 1e6;

        IAMMStrategy.Operation[] memory operations = new IAMMStrategy.Operation[](2);
        // construct data for sushiSwap (half inputAmount)
        address[] memory path = new address[](2);
        path[0] = inputToken;
        path[1] = outputToken;

        bytes memory payload0 = abi.encodeCall(
            IUniswapRouterV2.swapExactTokensForTokens,
            (inputAmount / 2, uint256(0), path, address(ammStrategy), defaultDeadline)
        );
        operations[0] = IAMMStrategy.Operation(SUSHISWAP_ADDRESS, 0, payload0);

        // construct data for curveV1 (half inputAmount)
        // address[] USDT_POOL_COINS = [cDAI_ADDRESS, cUSDC_ADDRESS, USDT_ADDRESS];
        int128 inputTokenIndex = 1;
        int128 outputTokenIndex = 0;
        // ICurveFi
        bytes memory payload1 = abi.encodeWithSignature(
            "exchange_underlying(int128,int128,uint256,uint256)",
            inputTokenIndex,
            outputTokenIndex,
            inputAmount - inputAmount / 2,
            0,
            defaultDeadline
        );
        operations[1] = IAMMStrategy.Operation(CURVE_USDT_POOL_ADDRESS, 0, payload1);

        bytes memory data = abi.encode(operations);
        _baseTest(inputToken, outputToken, inputAmount, data);
    }

    function testAMMStrategyTradeSushiswap() public {
        address inputToken = USDC_ADDRESS;
        address outputToken = DAI_ADDRESS;
        uint256 inputAmount = 10 * 1e6;
        address[] memory path = new address[](2);
        path[0] = inputToken;
        path[1] = outputToken;

        IAMMStrategy.Operation[] memory operations = new IAMMStrategy.Operation[](1);
        bytes memory payload0 = abi.encodeCall(
            IUniswapRouterV2.swapExactTokensForTokens,
            (inputAmount, uint256(0), path, address(ammStrategy), defaultDeadline)
        );
        operations[0] = IAMMStrategy.Operation(SUSHISWAP_ADDRESS, 0, payload0);

        bytes memory data = abi.encode(operations);
        _baseTest(inputToken, outputToken, inputAmount, data);
    }

    function testAMMStrategyTradeSushiswapWithETHAsInput() public {
        address inputToken = Constant.ETH_ADDRESS;
        address outputToken = DAI_ADDRESS;
        uint256 inputAmount = 1 ether;
        address[] memory path = new address[](2);
        path[0] = WETH_ADDRESS; // use weth when swap
        path[1] = outputToken;
        // ETH -> WETH -> DAI
        IAMMStrategy.Operation[] memory operations = new IAMMStrategy.Operation[](1);
        bytes memory payload1 = abi.encodeCall(
            IUniswapRouterV2.swapExactTokensForTokens,
            (inputAmount, uint256(0), path, address(ammStrategy), defaultDeadline)
        );
        operations[0] = IAMMStrategy.Operation(SUSHISWAP_ADDRESS, 0, payload1);

        bytes memory data = abi.encode(operations);
        _baseTest(inputToken, outputToken, inputAmount, data);
    }

    function testAMMStrategyTradeSushiswapWithETHAsOutput() public {
        address inputToken = USDC_ADDRESS;
        address outputToken = Constant.ETH_ADDRESS;
        uint256 inputAmount = 10 * 1e6;
        address[] memory path = new address[](2);
        path[0] = inputToken;
        path[1] = WETH_ADDRESS; // use weth when swap
        // USDC -> WETH
        // if outputToken is native ETH, strategy contract will unwrap WETH to ETH automatically
        IAMMStrategy.Operation[] memory operations = new IAMMStrategy.Operation[](1);

        bytes memory payload0 = abi.encodeCall(
            IUniswapRouterV2.swapExactTokensForTokens,
            (inputAmount, uint256(0), path, address(ammStrategy), defaultDeadline)
        );
        operations[0] = IAMMStrategy.Operation(SUSHISWAP_ADDRESS, 0, payload0);

        bytes memory data = abi.encode(operations);
        _baseTest(inputToken, outputToken, inputAmount, data);
    }

    function testAMMStrategyTradeUniswapV2() public {
        address inputToken = USDC_ADDRESS;
        address outputToken = DAI_ADDRESS;
        uint256 inputAmount = 10 * 1e6;
        address[] memory path = new address[](2);
        path[0] = inputToken;
        path[1] = outputToken;

        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.V2_SWAP_EXACT_IN)));
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(address(ammStrategy), inputAmount, 0, path, true);

        IAMMStrategy.Operation[] memory operations = new IAMMStrategy.Operation[](1);
        bytes memory payload0 = abi.encodeCall(IUniversalRouter.execute, (commands, inputs, defaultDeadline));
        operations[0] = IAMMStrategy.Operation(UNISWAP_UNIVERSAL_ROUTER_ADDRESS, 0, payload0);

        bytes memory data = abi.encode(operations);
        _baseTest(inputToken, outputToken, inputAmount, data);
    }

    function testAMMStrategyTradeUniswapV3WithMultiHop() public {
        uint16 DEFAULT_FEE_FACTOR = 500;
        address inputToken = USDC_ADDRESS;
        address outputToken = DAI_ADDRESS;
        uint256 inputAmount = 10 * 1e6;

        address[] memory path = new address[](3);
        path[0] = inputToken;
        path[1] = address(weth);
        path[2] = outputToken;

        uint24[] memory fees = new uint24[](2);
        fees[0] = DEFAULT_FEE_FACTOR;
        fees[1] = DEFAULT_FEE_FACTOR;

        address[] memory routerAddrList = new address[](1);
        routerAddrList[0] = UNISWAP_UNIVERSAL_ROUTER_ADDRESS;

        bytes memory encodePath;
        for (uint256 i = 0; i < fees.length; i++) {
            encodePath = abi.encodePacked(encodePath, path[i], fees[i]);
        }
        encodePath = abi.encodePacked(encodePath, path[path.length - 1]);

        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.V3_SWAP_EXACT_IN)));
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(address(ammStrategy), inputAmount, 0, encodePath, true);

        IAMMStrategy.Operation[] memory operations = new IAMMStrategy.Operation[](1);
        bytes memory payload0 = abi.encodeCall(IUniversalRouter.execute, (commands, inputs, defaultDeadline));
        operations[0] = IAMMStrategy.Operation(UNISWAP_UNIVERSAL_ROUTER_ADDRESS, 0, payload0);

        bytes memory data = abi.encode(operations);
        _baseTest(inputToken, outputToken, inputAmount, data);
    }

    function testTradeBalancerV2MultiHop() public {
        bytes32 BALANCER_WETH_DAI_POOL = 0x0b09dea16768f0799065c475be02919503cb2a3500020000000000000000001a;
        bytes32 BALANCER_WETH_USDC_POOL = 0x96646936b91d6b9d7d0c47c496afbf3d6ec7b6f8000200000000000000000019;
        address inputToken = USDC_ADDRESS;
        address outputToken = DAI_ADDRESS;
        uint256 inputAmount = 10 * 1e6;

        address[] memory path = new address[](3);
        path[0] = inputToken;
        path[1] = address(weth);
        path[2] = outputToken;

        IBalancerV2Vault.BatchSwapStep[] memory swapSteps = new IBalancerV2Vault.BatchSwapStep[](2);
        swapSteps[0] = IBalancerV2Vault.BatchSwapStep(
            BALANCER_WETH_USDC_POOL, // poolId
            0, // assetInIndex
            1, // assetOutIndex
            inputAmount, // amount
            new bytes(0) // userData
        );
        swapSteps[1] = IBalancerV2Vault.BatchSwapStep(
            BALANCER_WETH_DAI_POOL, // poolId
            1, // assetInIndex
            2, // assetOutIndex
            0, // amount
            new bytes(0) // userData
        );

        int256[] memory limits = _buildBalancerV2Limits(path, int256(inputAmount), 0);

        IAMMStrategy.Operation[] memory operations = new IAMMStrategy.Operation[](1);

        bytes memory payload0 = abi.encodeCall(
            IBalancerV2Vault.batchSwap,
            (
                IBalancerV2Vault.SwapKind.GIVEN_IN,
                swapSteps,
                path,
                // Balancer supports internal balance which keeps user balance in their contract to skip actual token transfer for efficiency.
                // AMM user should receive tokens right away after swap, so we need to turn off internal balance flag here.
                IBalancerV2Vault.FundManagement({
                    sender: address(ammStrategy),
                    fromInternalBalance: false,
                    recipient: payable(address(ammStrategy)),
                    toInternalBalance: false
                }),
                limits,
                defaultDeadline
            )
        );
        operations[0] = IAMMStrategy.Operation(BALANCER_V2_ADDRESS, 0, payload0);

        bytes memory data = abi.encode(operations);
        _baseTest(inputToken, outputToken, inputAmount, data);
    }

    function testTradeCurveV1WithUnderlyingCoin() public {
        address inputToken = USDC_ADDRESS;
        address outputToken = DAI_ADDRESS;
        uint256 inputAmount = 10 * 1e6;
        // address[] USDT_POOL_COINS = [cDAI_ADDRESS, cUSDC_ADDRESS, USDT_ADDRESS];
        int128 inputTokenIndex = 1;
        int128 outputTokenIndex = 0;

        IAMMStrategy.Operation[] memory operations = new IAMMStrategy.Operation[](1);
        // ICurveFi
        bytes memory payload0 = abi.encodeWithSignature(
            "exchange_underlying(int128,int128,uint256,uint256)",
            inputTokenIndex,
            outputTokenIndex,
            inputAmount,
            0,
            defaultDeadline
        );
        operations[0] = IAMMStrategy.Operation(CURVE_USDT_POOL_ADDRESS, 0, payload0);

        bytes memory data = abi.encode(operations);
        _baseTest(inputToken, outputToken, inputAmount, data);
    }

    function testTradeCurveV1() public {
        address inputToken = cUSDC_ADDRESS;
        address outputToken = cDAI_ADDRESS;
        uint256 inputAmount = 10 * 1e6;
        // address[] USDT_POOL_COINS = [cDAI_ADDRESS, cUSDC_ADDRESS, USDT_ADDRESS];
        int128 inputTokenIndex = 1;
        int128 outputTokenIndex = 0;

        IAMMStrategy.Operation[] memory operations = new IAMMStrategy.Operation[](1);
        // ICurveFi
        bytes memory payload0 = abi.encodeWithSignature(
            "exchange(int128,int128,uint256,uint256)",
            inputTokenIndex,
            outputTokenIndex,
            inputAmount,
            0,
            defaultDeadline
        );
        operations[0] = IAMMStrategy.Operation(CURVE_USDT_POOL_ADDRESS, 0, payload0);

        bytes memory data = abi.encode(operations);
        _baseTest(inputToken, outputToken, inputAmount, data);
    }

    function testTradeCurveV2WithETH() public {
        address inputToken = Constant.ETH_ADDRESS;
        address outputToken = WBTC_ADDRESS;
        uint256 inputAmount = 1 ether;
        // address[] TRICRYPTO2POOL_COINS = [USDT_ADDRESS, WBTC_ADDRESS, WETH_ADDRESS];
        int128 inputTokenIndex = 2; // WETH
        int128 outputTokenIndex = 1; // WBTC
        IAMMStrategy.Operation[] memory operations = new IAMMStrategy.Operation[](1);
        // ICurveFiV2
        bytes memory payload0 = abi.encodeWithSignature(
            "exchange(uint256,uint256,uint256,uint256,bool)",
            uint256(uint128(inputTokenIndex)),
            uint256(uint128(outputTokenIndex)),
            inputAmount,
            0,
            true // use_eth = true
        );
        operations[0] = IAMMStrategy.Operation(CURVE_TRICRYPTO2_POOL_ADDRESS, inputAmount, payload0);

        bytes memory data = abi.encode(operations);
        _baseTest(inputToken, outputToken, inputAmount, data);
    }

    function testTradeCurveV2WithWETH() public {
        address inputToken = WETH_ADDRESS;
        address outputToken = WBTC_ADDRESS;
        uint256 inputAmount = 10 * 1e18;
        // address[] TRICRYPTO2POOL_COINS = [USDT_ADDRESS, WBTC_ADDRESS, WETH_ADDRESS];
        int128 inputTokenIndex = 2; // WETH
        int128 outputTokenIndex = 1; // WBTC
        IAMMStrategy.Operation[] memory operations = new IAMMStrategy.Operation[](1);
        // ICurveFiV2
        bytes memory payload0 = abi.encodeWithSignature(
            "exchange(uint256,uint256,uint256,uint256,bool)",
            uint256(uint128(inputTokenIndex)),
            uint256(uint128(outputTokenIndex)),
            inputAmount,
            0,
            false // use_eth = false
        );
        operations[0] = IAMMStrategy.Operation(CURVE_TRICRYPTO2_POOL_ADDRESS, 0, payload0);

        bytes memory data = abi.encode(operations);
        _baseTest(inputToken, outputToken, inputAmount, data);
    }

    function _baseTest(
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        bytes memory data
    ) internal {
        BalanceSnapshot.Snapshot memory inputTokenBalance = BalanceSnapshot.take(genericSwap, inputToken);
        BalanceSnapshot.Snapshot memory outputTokenBalance = BalanceSnapshot.take(genericSwap, outputToken);

        if (inputToken == Constant.ETH_ADDRESS) {
            IStrategy(ammStrategy).executeStrategy{ value: inputAmount }(inputToken, outputToken, inputAmount, data);
        } else {
            IERC20(inputToken).safeTransfer(address(ammStrategy), inputAmount);
            IStrategy(ammStrategy).executeStrategy(inputToken, outputToken, inputAmount, data);
        }

        inputTokenBalance.assertChange(-int256(inputAmount));
        outputTokenBalance.assertChangeGt(0);
    }

    function setBalance(
        address account,
        address[] memory tokens,
        uint256 amount
    ) internal {
        vm.startPrank(account);
        for (uint256 i = 0; i < tokens.length; i++) {
            setERC20Balance(tokens[i], account, amount);
        }
        vm.stopPrank();
    }

    function _buildBalancerV2Limits(
        address[] memory _path,
        int256 inputAmount,
        int256 _minOutputAmount
    ) internal pure returns (int256[] memory) {
        int256[] memory limits = new int256[](_path.length);
        // amount swapped in to balancer will denoted with positive sign
        limits[0] = inputAmount;
        for (uint256 i = 1; i < _path.length - 1; ++i) {
            // we only care final maker asset out amount
            limits[i] = type(int256).max;
        }
        // amount swapped out from balancer will denoted with negative sign
        limits[_path.length - 1] = -_minOutputAmount;
        return limits;
    }
}
