// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";
import { Tokens } from "test/utils/Tokens.sol";
import { BalanceUtil } from "test/utils/BalanceUtil.sol";
import { BalanceSnapshot } from "test/utils/BalanceSnapshot.sol";
import { AMMStrategy } from "contracts/AMMStrategy.sol";
import { Constant } from "contracts/libraries/Constant.sol";

import { Commands } from "contracts/libraries/UniswapCommands.sol";
import { IStrategy } from "contracts/interfaces/IStrategy.sol";
import { IBalancerV2Vault } from "contracts/interfaces/IBalancerV2Vault.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract AMMStrategyTest is Test, Tokens, BalanceUtil {
    using SafeERC20 for IERC20;

    using BalanceSnapshot for BalanceSnapshot.Snapshot;

    address strategyAdmin = makeAddr("strategyAdmin");
    address genericSwap = makeAddr("genericSwap");
    uint256 defaultDeadline = block.timestamp + 1;
    address[] tokenList = [USDC_ADDRESS, cUSDC_ADDRESS];
    address[] ammList = [SUSHISWAP_ADDRESS, UNISWAP_UNIVERSAL_ROUTER_ADDRESS, BALANCER_V2_ADDRESS, CURVE_USDT_POOL_ADDRESS];
    AMMStrategy ammStrategy;

    function setUp() public {
        ammStrategy = new AMMStrategy(
            strategyAdmin,
            payable(genericSwap),
            WETH_ADDRESS,
            SUSHISWAP_ADDRESS,
            UNISWAP_PERMIT2_ADDRESS,
            UNISWAP_UNIVERSAL_ROUTER_ADDRESS,
            BALANCER_V2_ADDRESS
        );
        vm.prank(strategyAdmin);
        ammStrategy.approveTokenList(tokenList, ammList, Constant.MAX_UINT);
        setEOABalance(genericSwap, tokenList, 100000);

        vm.label(UNISWAP_UNIVERSAL_ROUTER_ADDRESS, "UniswapUniversalRouter");
        vm.label(SUSHISWAP_ADDRESS, "Sushiswap");
        vm.label(CURVE_USDT_POOL_ADDRESS, "CurveUSDTPool");
        vm.label(BALANCER_V2_ADDRESS, "BalancerV2");
        vm.label(UNISWAP_PERMIT2_ADDRESS, "UniswapPermit2");
    }

    function testAMMStrategyTradeWithMultiAMM() public {
        // sushiSwap and curveV1
        address inputToken = USDC_ADDRESS;
        address outputToken = DAI_ADDRESS;
        uint256 inputAmount = 10 * 1e6;

        // construct data for sushiSwap (half inputAmount)
        address[] memory path = new address[](2);
        path[0] = inputToken;
        path[1] = outputToken;
        bytes memory data1 = abi.encode(inputAmount / 2, defaultDeadline, path);

        // construct data for curveV1 (half inputAmount)
        uint16 UNDERLAY_SWAP_METHOD = 2;
        uint8 version = 1;
        // address[] USDT_POOL_COINS = [cDAI_ADDRESS, cUSDC_ADDRESS, USDT_ADDRESS];
        int128 inputTokenIndex = 1;
        int128 outputTokenIndex = 0;
        bytes memory data2 = abi.encode(inputAmount - inputAmount / 2, version, inputTokenIndex, outputTokenIndex, UNDERLAY_SWAP_METHOD);

        // bundle
        address[] memory routerAddrList = new address[](2);
        routerAddrList[0] = SUSHISWAP_ADDRESS;
        routerAddrList[1] = CURVE_USDT_POOL_ADDRESS;

        bytes[] memory dataList = new bytes[](2);
        dataList[0] = data1;
        dataList[1] = data2;

        _baseTest(inputToken, outputToken, inputAmount, routerAddrList, dataList);
    }

    function testAMMStrategyTradeSushiswap() public {
        address inputToken = USDC_ADDRESS;
        address outputToken = DAI_ADDRESS;
        uint256 inputAmount = 10 * 1e6;
        address[] memory path = new address[](2);
        path[0] = inputToken;
        path[1] = outputToken;

        address[] memory routerAddrList = new address[](1);
        routerAddrList[0] = SUSHISWAP_ADDRESS;

        bytes[] memory dataList = new bytes[](1);
        dataList[0] = abi.encode(inputAmount, defaultDeadline, path);

        _baseTest(inputToken, outputToken, inputAmount, routerAddrList, dataList);
    }

    function testAMMStrategyTradeUniswapV2() public {
        address inputToken = USDC_ADDRESS;
        address outputToken = DAI_ADDRESS;
        uint256 inputAmount = 10 * 1e6;
        address[] memory path = new address[](2);
        path[0] = inputToken;
        path[1] = outputToken;

        address[] memory routerAddrList = new address[](1);
        routerAddrList[0] = UNISWAP_UNIVERSAL_ROUTER_ADDRESS;

        bytes[] memory dataList = new bytes[](1);
        dataList[0] = abi.encode(Commands.V2_SWAP_EXACT_IN, inputAmount, defaultDeadline, abi.encode(path));

        _baseTest(inputToken, outputToken, inputAmount, routerAddrList, dataList);
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

        bytes[] memory dataList = new bytes[](1);
        dataList[0] = abi.encode(Commands.V3_SWAP_EXACT_IN, inputAmount, defaultDeadline, encodePath);

        _baseTest(inputToken, outputToken, inputAmount, routerAddrList, dataList);
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

        address[] memory routerAddrList = new address[](1);
        routerAddrList[0] = BALANCER_V2_ADDRESS;

        bytes[] memory dataList = new bytes[](1);
        dataList[0] = abi.encode(inputAmount, defaultDeadline, path, swapSteps);

        _baseTest(inputToken, outputToken, inputAmount, routerAddrList, dataList);
    }

    function testTradeCurveV1WithUnderlyingCoin() public {
        uint16 UNDERLAY_SWAP_METHOD = 2;
        address inputToken = USDC_ADDRESS;
        address outputToken = DAI_ADDRESS;
        uint256 inputAmount = 10 * 1e6;
        uint8 version = 1;
        // address[] USDT_POOL_COINS = [cDAI_ADDRESS, cUSDC_ADDRESS, USDT_ADDRESS];
        int128 inputTokenIndex = 1;
        int128 outputTokenIndex = 0;

        address[] memory routerAddrList = new address[](1);

        routerAddrList[0] = CURVE_USDT_POOL_ADDRESS;

        bytes[] memory dataList = new bytes[](1);
        dataList[0] = abi.encode(inputAmount, version, inputTokenIndex, outputTokenIndex, UNDERLAY_SWAP_METHOD);

        _baseTest(inputToken, outputToken, inputAmount, routerAddrList, dataList);
    }

    function testTradeCurveV1() public {
        uint16 DEFAULT_SWAP_METHOD = 1;
        address inputToken = cUSDC_ADDRESS;
        address outputToken = cDAI_ADDRESS;
        uint256 inputAmount = 10 * 1e6;
        uint8 version = 1;
        // address[] USDT_POOL_COINS = [cDAI_ADDRESS, cUSDC_ADDRESS, USDT_ADDRESS];
        int128 inputTokenIndex = 1;
        int128 outputTokenIndex = 0;

        address[] memory routerAddrList = new address[](1);

        routerAddrList[0] = CURVE_USDT_POOL_ADDRESS;

        bytes[] memory dataList = new bytes[](1);
        dataList[0] = abi.encode(inputAmount, version, inputTokenIndex, outputTokenIndex, DEFAULT_SWAP_METHOD);

        _baseTest(inputToken, outputToken, inputAmount, routerAddrList, dataList);
    }

    function testTradeCurveV2() public {
        uint16 DEFAULT_SWAP_METHOD = 1;
        address inputToken = cUSDC_ADDRESS;
        address outputToken = cDAI_ADDRESS;
        uint256 inputAmount = 10 * 1e6;
        uint8 version = 1;
        // address[] USDT_POOL_COINS = [cDAI_ADDRESS, cUSDC_ADDRESS, USDT_ADDRESS];
        int128 inputTokenIndex = 1;
        int128 outputTokenIndex = 0;

        address[] memory routerAddrList = new address[](1);

        routerAddrList[0] = CURVE_USDT_POOL_ADDRESS;

        bytes[] memory dataList = new bytes[](1);
        dataList[0] = abi.encode(inputAmount, version, inputTokenIndex, outputTokenIndex, DEFAULT_SWAP_METHOD);

        _baseTest(inputToken, outputToken, inputAmount, routerAddrList, dataList);
    }

    function _baseTest(
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        address[] memory routerAddrList,
        bytes[] memory dataList
    ) internal {
        bytes memory data = abi.encode(routerAddrList, dataList);

        BalanceSnapshot.Snapshot memory inputTokenBalance = BalanceSnapshot.take(genericSwap, inputToken);
        BalanceSnapshot.Snapshot memory outputTokenBalance = BalanceSnapshot.take(genericSwap, outputToken);

        vm.startPrank(genericSwap);
        IERC20(inputToken).safeTransfer(address(ammStrategy), inputAmount);
        IStrategy(ammStrategy).executeStrategy(inputToken, outputToken, inputAmount, data);
        vm.stopPrank();

        inputTokenBalance.assertChange(-int256(inputAmount));
        outputTokenBalance.assertChangeGt(0);
    }

    function setEOABalance(
        address eoa,
        address[] memory tokens,
        uint256 amount
    ) internal {
        vm.startPrank(eoa);
        for (uint256 i = 0; i < tokens.length; i++) {
            setERC20Balance(tokens[i], eoa, amount);
        }
        vm.stopPrank();
    }
}
