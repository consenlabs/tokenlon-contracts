// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { Tokens } from "test/utils/Tokens.sol";
import { BalanceUtil } from "test/utils/BalanceUtil.sol";
import { BalanceSnapshot, Snapshot } from "test/utils/BalanceSnapshot.sol";
import { UniswapCommands } from "test/libraries/UniswapCommands.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";
import { IWETH } from "contracts/interfaces/IWETH.sol";
import { ISmartOrderStrategy } from "contracts/interfaces/ISmartOrderStrategy.sol";
import { IStrategy } from "contracts/interfaces/IStrategy.sol";
import { IUniswapRouterV2 } from "contracts//interfaces/IUniswapRouterV2.sol";
import { Constant } from "contracts/libraries/Constant.sol";
import { SmartOrderStrategy } from "contracts/SmartOrderStrategy.sol";

contract SmartOrderStrategyTest is Test, Tokens, BalanceUtil {
    using SafeERC20 for IERC20;
    using BalanceSnapshot for Snapshot;

    address strategyOwner = makeAddr("strategyOwner");
    address genericSwap = makeAddr("genericSwap");
    address defaultInputToken = USDC_ADDRESS;
    address defaultOutputToken = DAI_ADDRESS;
    uint256 defaultInputAmount = 1000;
    uint128 defaultInputRatio = 5000;
    uint256 defaultExpiry = block.timestamp + 100;
    bytes defaultOpsData;
    address[] defaultUniV2Path = [USDC_ADDRESS, DAI_ADDRESS];
    address[] tokenList = [USDC_ADDRESS, cUSDC_ADDRESS, WETH_ADDRESS, WBTC_ADDRESS];
    address[] ammList = [UNISWAP_V2_ADDRESS, SUSHISWAP_ADDRESS, BALANCER_V2_ADDRESS, CURVE_USDT_POOL_ADDRESS, CURVE_TRICRYPTO2_POOL_ADDRESS];
    SmartOrderStrategy smartOrderStrategy;

    receive() external payable {}

    function setUp() public {
        // Deploy and setup SmartOrderStrategy
        smartOrderStrategy = new SmartOrderStrategy(strategyOwner, genericSwap, WETH_ADDRESS);
        vm.prank(strategyOwner);
        smartOrderStrategy.approveTokens(tokenList, ammList);

        // Make genericSwap rich to provide fund for strategy contract
        deal(genericSwap, 100 ether);
        for (uint256 i = 0; i < tokenList.length; i++) {
            setERC20Balance(tokenList[i], genericSwap, 10000);
        }

        ISmartOrderStrategy.Operation[] memory operations = new ISmartOrderStrategy.Operation[](1);
        defaultOpsData = abi.encode(operations);

        vm.label(UNISWAP_UNIVERSAL_ROUTER_ADDRESS, "UniswapUniversalRouter");
    }

    function testCannotApproveTokensByNotOwner() public {
        vm.expectRevert("not owner");
        smartOrderStrategy.approveTokens(tokenList, ammList);
    }

    function testApproveTokens() public {
        MockERC20 mockERC20 = new MockERC20("Mock Token", "MKT", 18);
        address[] memory newTokens = new address[](1);
        newTokens[0] = address(mockERC20);

        address target = makeAddr("target");
        address[] memory targetList = new address[](1);
        targetList[0] = target;

        assertEq(mockERC20.allowance(address(smartOrderStrategy), target), 0);
        vm.prank(strategyOwner);
        smartOrderStrategy.approveTokens(newTokens, targetList);
        assertEq(mockERC20.allowance(address(smartOrderStrategy), target), type(uint256).max);
    }

    function testCannotWithdrawTokensByNotOwner() public {
        vm.expectRevert("not owner");
        smartOrderStrategy.withdrawTokens(tokenList, address(this));
    }

    function testWithdrawTokens() public {
        uint256 amount = 5678;
        MockERC20 mockERC20 = new MockERC20("Mock Token", "MKT", 18);
        mockERC20.mint(address(smartOrderStrategy), amount);

        address[] memory withdrawList = new address[](1);
        withdrawList[0] = address(mockERC20);

        address withdrawTarget = makeAddr("withdrawTarget");
        Snapshot memory recipientBalance = BalanceSnapshot.take(withdrawTarget, address(mockERC20));

        vm.prank(strategyOwner);
        smartOrderStrategy.withdrawTokens(withdrawList, withdrawTarget);

        recipientBalance.assertChange(int256(amount));
    }

    function testCannotExecuteNotFromGenericSwap() public {
        vm.expectRevert(ISmartOrderStrategy.NotFromGS.selector);
        smartOrderStrategy.executeStrategy(defaultInputToken, defaultOutputToken, defaultInputAmount, defaultOpsData);
    }

    function testCannotExecuteWithZeroInputAmount() public {
        vm.expectRevert(ISmartOrderStrategy.ZeroInput.selector);
        vm.prank(genericSwap, genericSwap);
        smartOrderStrategy.executeStrategy(defaultInputToken, defaultOutputToken, 0, defaultOpsData);
    }

    function testCannotExecuteWithFailDecodedData() public {
        vm.expectRevert();
        vm.prank(genericSwap, genericSwap);
        smartOrderStrategy.executeStrategy(defaultInputToken, defaultOutputToken, defaultInputAmount, bytes("random data"));
    }

    function testCannotExecuteWithEmptyOperation() public {
        ISmartOrderStrategy.Operation[] memory operations;
        bytes memory emptyOpsData = abi.encode(operations);

        vm.expectRevert(ISmartOrderStrategy.EmptyOps.selector);
        vm.prank(genericSwap, genericSwap);
        smartOrderStrategy.executeStrategy(defaultInputToken, defaultOutputToken, defaultInputAmount, emptyOpsData);
    }

    function testCannotExecuteWithIncorrectMsgValue() public {
        // case : ETH as input but msg.value mismatch
        address inputToken = Constant.ETH_ADDRESS;
        uint256 inputAmount = 1 ether;

        vm.expectRevert(ISmartOrderStrategy.InvalidMsgValue.selector);
        vm.prank(genericSwap, genericSwap);
        smartOrderStrategy.executeStrategy{ value: inputAmount + 1 }(inputToken, defaultOutputToken, inputAmount, defaultOpsData);

        // case : ETH as input but msg.value is zero
        vm.expectRevert(ISmartOrderStrategy.InvalidMsgValue.selector);
        vm.prank(genericSwap, genericSwap);
        smartOrderStrategy.executeStrategy{ value: 0 }(inputToken, defaultOutputToken, inputAmount, defaultOpsData);

        // case : token as input but msg.value is not zero
        vm.expectRevert(ISmartOrderStrategy.InvalidMsgValue.selector);
        vm.prank(genericSwap, genericSwap);
        smartOrderStrategy.executeStrategy{ value: 1 }(defaultInputToken, defaultOutputToken, defaultInputAmount, defaultOpsData);
    }

    function testUniswapV2WithoutAmountReplace() public {
        bytes memory uniswapData = abi.encodeWithSelector(
            IUniswapRouterV2.swapExactTokensForTokens.selector,
            defaultInputAmount,
            0, // minOutputAmount
            defaultUniV2Path,
            address(smartOrderStrategy),
            defaultExpiry
        );
        ISmartOrderStrategy.Operation[] memory operations = new ISmartOrderStrategy.Operation[](1);
        operations[0] = ISmartOrderStrategy.Operation({
            dest: UNISWAP_V2_ADDRESS,
            inputToken: defaultInputToken,
            inputRatio: 0, // zero ratio indicate no replacement
            dataOffset: 0,
            value: 0,
            data: uniswapData
        });
        bytes memory data = abi.encode(operations);

        // get the exact quote from uniswap
        IUniswapRouterV2 router = IUniswapRouterV2(UNISWAP_V2_ADDRESS);
        uint256[] memory amounts = router.getAmountsOut(defaultInputAmount, defaultUniV2Path);
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
            IUniswapRouterV2.swapExactTokensForTokens.selector,
            defaultInputAmount,
            0,
            defaultUniV2Path,
            address(smartOrderStrategy),
            defaultExpiry
        );
        ISmartOrderStrategy.Operation[] memory operations = new ISmartOrderStrategy.Operation[](1);
        operations[0] = ISmartOrderStrategy.Operation({
            dest: UNISWAP_V2_ADDRESS,
            inputToken: defaultInputToken,
            inputRatio: defaultInputRatio,
            dataOffset: uint128(4 + 32), // add 32 bytes of length prefix
            value: 0,
            data: uniswapData
        });
        bytes memory data = abi.encode(operations);

        // get the exact quote from uniswap
        uint256 inputAmountAfterRatio = (defaultInputAmount * defaultInputRatio) / Constant.BPS_MAX;
        IUniswapRouterV2 router = IUniswapRouterV2(UNISWAP_V2_ADDRESS);
        uint256[] memory amounts = router.getAmountsOut(inputAmountAfterRatio, defaultUniV2Path);
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
            IUniswapRouterV2.swapExactTokensForTokens.selector,
            defaultInputAmount,
            0,
            defaultUniV2Path,
            address(smartOrderStrategy),
            defaultExpiry
        );
        ISmartOrderStrategy.Operation[] memory operations = new ISmartOrderStrategy.Operation[](1);
        operations[0] = ISmartOrderStrategy.Operation({
            dest: UNISWAP_V2_ADDRESS,
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
        IUniswapRouterV2 router = IUniswapRouterV2(UNISWAP_V2_ADDRESS);
        uint256[] memory amounts = router.getAmountsOut(actualInputAmount, defaultUniV2Path);
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
}
