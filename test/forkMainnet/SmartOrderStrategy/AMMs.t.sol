// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { SmartOrderStrategyTest } from "./Setup.t.sol";
import { ICurveFiV2 } from "contracts/interfaces/ICurveFiV2.sol";
import { ISmartOrderStrategy } from "contracts/interfaces/ISmartOrderStrategy.sol";
import { IUniswapSwapRouter02 } from "test/utils/IUniswapSwapRouter02.sol";
import { Constant } from "contracts/libraries/Constant.sol";
import { BalanceSnapshot, Snapshot } from "test/utils/BalanceSnapshot.sol";
import { UniswapV2Library } from "test/utils/UniswapV2Library.sol";

contract AMMsTest is SmartOrderStrategyTest {
    using SafeERC20 for IERC20;
    using BalanceSnapshot for Snapshot;

    function testUniswapV2WithoutAmountReplace() public {
        bytes memory uniswapData = abi.encodeWithSelector(
            IUniswapSwapRouter02.swapExactTokensForTokens.selector,
            defaultInputAmount,
            0, // minOutputAmount
            defaultUniV2Path,
            address(smartOrderStrategy)
        );
        ISmartOrderStrategy.Operation[] memory operations = new ISmartOrderStrategy.Operation[](1);
        operations[0] = ISmartOrderStrategy.Operation({
            dest: UNISWAP_SWAP_ROUTER_02_ADDRESS,
            inputToken: defaultInputToken,
            inputRatio: 0, // zero ratio indicate no replacement
            dataOffset: 0,
            value: 0,
            data: uniswapData
        });
        bytes memory data = abi.encode(operations);

        // get the exact quote from uniswap
        uint256[] memory amounts = UniswapV2Library.getAmountsOut(defaultInputAmount, defaultUniV2Path);
        uint256 expectedOut = amounts[amounts.length - 1];

        vm.startPrank(genericSwap, genericSwap);
        IERC20(defaultInputToken).safeTransfer(address(smartOrderStrategy), defaultInputAmount);
        Snapshot memory sosInputToken = BalanceSnapshot.take(address(smartOrderStrategy), defaultInputToken);
        Snapshot memory gsOutputToken = BalanceSnapshot.take(genericSwap, defaultOutputToken);
        smartOrderStrategy.executeStrategy(defaultInputToken, defaultOutputToken, defaultInputAmount, data);
        vm.stopPrank();

        sosInputToken.assertChange(-int256(defaultInputAmount));
        gsOutputToken.assertChange(int256(expectedOut));
    }

    function testUniswapV2WithAmountReplace() public {
        bytes memory uniswapData = abi.encodeWithSelector(
            IUniswapSwapRouter02.swapExactTokensForTokens.selector,
            defaultInputAmount,
            0,
            defaultUniV2Path,
            address(smartOrderStrategy)
        );
        ISmartOrderStrategy.Operation[] memory operations = new ISmartOrderStrategy.Operation[](1);
        operations[0] = ISmartOrderStrategy.Operation({
            dest: UNISWAP_SWAP_ROUTER_02_ADDRESS,
            inputToken: defaultInputToken,
            inputRatio: defaultInputRatio,
            dataOffset: uint128(4 + 32), // add 32 bytes of length prefix
            value: 0,
            data: uniswapData
        });
        bytes memory data = abi.encode(operations);

        // get the exact quote from uniswap
        uint256 inputAmountAfterRatio = (defaultInputAmount * defaultInputRatio) / Constant.BPS_MAX;
        uint256[] memory amounts = UniswapV2Library.getAmountsOut(inputAmountAfterRatio, defaultUniV2Path);
        uint256 expectedOut = amounts[amounts.length - 1];

        vm.startPrank(genericSwap, genericSwap);
        IERC20(defaultInputToken).safeTransfer(address(smartOrderStrategy), defaultInputAmount);
        Snapshot memory sosInputToken = BalanceSnapshot.take(address(smartOrderStrategy), defaultInputToken);
        Snapshot memory gsOutputToken = BalanceSnapshot.take(genericSwap, defaultOutputToken);
        smartOrderStrategy.executeStrategy(defaultInputToken, defaultOutputToken, defaultInputAmount, data);
        vm.stopPrank();

        sosInputToken.assertChange(-int256(inputAmountAfterRatio));
        gsOutputToken.assertChange(int256(expectedOut));
    }

    function testUniswapV2WithMaxAmountReplace() public {
        bytes memory uniswapData = abi.encodeWithSelector(
            IUniswapSwapRouter02.swapExactTokensForTokens.selector,
            defaultInputAmount,
            0,
            defaultUniV2Path,
            address(smartOrderStrategy)
        );
        ISmartOrderStrategy.Operation[] memory operations = new ISmartOrderStrategy.Operation[](1);
        operations[0] = ISmartOrderStrategy.Operation({
            dest: UNISWAP_SWAP_ROUTER_02_ADDRESS,
            inputToken: defaultInputToken,
            inputRatio: Constant.BPS_MAX, // BPS_MAX indicate the input amount will be replaced by the actual balance
            dataOffset: uint128(4 + 32), // add 32 bytes of length prefix
            value: 0,
            data: uniswapData
        });
        bytes memory data = abi.encode(operations);

        // set the actual input amount which will replace the amount of operations[0]
        uint256 actualInputAmount = 5678;

        // get the exact quote from uniswap
        uint256[] memory amounts = UniswapV2Library.getAmountsOut(actualInputAmount, defaultUniV2Path);
        uint256 expectedOut = amounts[amounts.length - 1];

        vm.startPrank(genericSwap, genericSwap);
        IERC20(defaultInputToken).safeTransfer(address(smartOrderStrategy), actualInputAmount);
        Snapshot memory sosInputToken = BalanceSnapshot.take(address(smartOrderStrategy), defaultInputToken);
        Snapshot memory gsOutputToken = BalanceSnapshot.take(genericSwap, defaultOutputToken);
        smartOrderStrategy.executeStrategy(defaultInputToken, defaultOutputToken, defaultInputAmount, data);
        vm.stopPrank();

        // the amount change will be the actual balance at the moment
        sosInputToken.assertChange(-int256(actualInputAmount));
        gsOutputToken.assertChange(int256(expectedOut));
    }

    function testUniswapV2WithWETHUnwrap() public {
        bytes memory uniswapData = abi.encodeWithSelector(
            IUniswapSwapRouter02.swapExactTokensForTokens.selector,
            defaultInputAmount,
            0, // minOutputAmount
            defaultUniV2Path,
            address(smartOrderStrategy)
        );
        ISmartOrderStrategy.Operation[] memory operations = new ISmartOrderStrategy.Operation[](2);
        operations[0] = ISmartOrderStrategy.Operation({
            dest: UNISWAP_SWAP_ROUTER_02_ADDRESS,
            inputToken: defaultInputToken,
            inputRatio: 0, // zero ratio indicate no replacement
            dataOffset: 0,
            value: 0,
            data: uniswapData
        });
        bytes memory data = abi.encode(operations);

        // get the exact quote from uniswap
        uint256[] memory amounts = UniswapV2Library.getAmountsOut(defaultInputAmount, defaultUniV2Path);
        uint256 expectedOut = amounts[amounts.length - 1];

        // set output token as ETH
        address outputToken = Constant.ETH_ADDRESS;
        vm.startPrank(genericSwap, genericSwap);
        IERC20(defaultInputToken).safeTransfer(address(smartOrderStrategy), defaultInputAmount);
        Snapshot memory sosInputToken = BalanceSnapshot.take(address(smartOrderStrategy), defaultInputToken);
        Snapshot memory gsOutputToken = BalanceSnapshot.take(genericSwap, outputToken);
        smartOrderStrategy.executeStrategy(defaultInputToken, outputToken, defaultInputAmount, data);
        vm.stopPrank();

        sosInputToken.assertChange(-int256(defaultInputAmount));
        gsOutputToken.assertChange(int256(expectedOut));
    }

    function testMultipleAMMs() public {
        // (USDC -> USDT) via UniswapV2 + Curve
        // UniswapV2 : USDC -> WETH
        // Curve : WETH -> USDT

        // get the exact quote from uniswap
        uint256[] memory amounts = UniswapV2Library.getAmountsOut(defaultInputAmount, defaultUniV2Path);
        uint256 uniOut = amounts[amounts.length - 1];

        bytes memory uniswapData = abi.encodeWithSelector(
            IUniswapSwapRouter02.swapExactTokensForTokens.selector,
            defaultInputAmount,
            0, // minOutputAmount
            defaultUniV2Path,
            address(smartOrderStrategy)
        );

        // exhange function selector : 0x5b41b908
        bytes memory curveData = abi.encodeWithSelector(0x5b41b908, 2, 0, uniOut, 0);
        ICurveFiV2 curvePool = ICurveFiV2(CURVE_TRICRYPTO2_POOL_ADDRESS);
        uint256 curveOut = curvePool.get_dy(2, 0, uniOut);

        ISmartOrderStrategy.Operation[] memory operations = new ISmartOrderStrategy.Operation[](2);
        operations[0] = ISmartOrderStrategy.Operation({
            dest: UNISWAP_SWAP_ROUTER_02_ADDRESS,
            inputToken: USDC_ADDRESS,
            inputRatio: 0, // zero ratio indicate no replacement
            dataOffset: 0,
            value: 0,
            data: uniswapData
        });
        operations[1] = ISmartOrderStrategy.Operation({
            dest: CURVE_TRICRYPTO2_POOL_ADDRESS,
            inputToken: WETH_ADDRESS,
            inputRatio: 0, // zero ratio indicate no replacement
            dataOffset: 0,
            value: 0,
            data: curveData
        });
        bytes memory data = abi.encode(operations);

        vm.startPrank(genericSwap, genericSwap);
        IERC20(defaultInputToken).safeTransfer(address(smartOrderStrategy), defaultInputAmount);
        Snapshot memory sosInputToken = BalanceSnapshot.take(address(smartOrderStrategy), defaultInputToken);
        Snapshot memory gsOutputToken = BalanceSnapshot.take(genericSwap, USDT_ADDRESS);
        smartOrderStrategy.executeStrategy(defaultInputToken, USDT_ADDRESS, defaultInputAmount, data);
        vm.stopPrank();

        sosInputToken.assertChange(-int256(defaultInputAmount));
        gsOutputToken.assertChange(int256(curveOut));
    }
}
