// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";
import { Tokens } from "test/utils/Tokens.sol";
import { BalanceUtil } from "test/utils/BalanceUtil.sol";
import { BalanceSnapshot } from "test/utils/BalanceSnapshot.sol";
import { AMMStrategy } from "contracts/AMMStrategy.sol";
import { Constant } from "contracts/libraries/Constant.sol";
import { IStrategy } from "contracts/interfaces/IStrategy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract AMMStrategyTest is Test, Tokens, BalanceUtil {
    using SafeERC20 for IERC20;

    using BalanceSnapshot for BalanceSnapshot.Snapshot;

    address strategyAdmin = makeAddr("strategyAdmin");
    address genericSwap = makeAddr("genericSwap");
    uint256 defaultDeadline = block.timestamp + 1;
    address[] tokenList = [USDT_ADDRESS];
    address[] ammList = [UNISWAP_V2_ADDRESS, SUSHISWAP_ADDRESS];
    AMMStrategy ammStrategy;

    function setUp() public {
        ammStrategy = new AMMStrategy(strategyAdmin, genericSwap, SUSHISWAP_ADDRESS, UNISWAP_V2_ADDRESS);
        vm.prank(strategyAdmin);
        ammStrategy.approveTokenList(tokenList, ammList, Constant.MAX_UINT);
        setEOABalance(genericSwap, tokens, 100000);
    }

    function testAMMStrategyTradeUniswapV2() public {
        address inputToken = USDT_ADDRESS;
        address outputToken = CRV_ADDRESS;
        uint256 inputAmount = 10 * 1e6;
        address[] memory path = new address[](2);
        path[0] = inputToken;
        path[1] = outputToken;

        address[] memory routerAddrList = new address[](1);
        routerAddrList[0] = UNISWAP_V2_ADDRESS;

        bytes[] memory makerSpecificDataList = new bytes[](1);
        makerSpecificDataList[0] = abi.encode(defaultDeadline, path);

        bytes memory data = abi.encode(routerAddrList, makerSpecificDataList);

        BalanceSnapshot.Snapshot memory inputTokenBalance = BalanceSnapshot.take(genericSwap, inputToken);
        BalanceSnapshot.Snapshot memory outputTokenBalance = BalanceSnapshot.take(genericSwap, outputToken);

        vm.startPrank(genericSwap);
        IERC20(inputToken).safeTransfer(address(ammStrategy), inputAmount);
        IStrategy(ammStrategy).executeStrategy(inputToken, outputToken, inputAmount, data);
        vm.stopPrank();

        inputTokenBalance.assertChange(-int256(inputAmount));
        outputTokenBalance.assertChangeGt(0);
    }

    function testAMMStrategyTradeSushiswap() public {
        address inputToken = USDT_ADDRESS;
        address outputToken = CRV_ADDRESS;
        uint256 inputAmount = 10 * 1e6;
        address[] memory path = new address[](2);
        path[0] = inputToken;
        path[1] = outputToken;

        address[] memory routerAddrList = new address[](1);
        routerAddrList[0] = SUSHISWAP_ADDRESS;

        bytes[] memory makerSpecificDataList = new bytes[](1);
        makerSpecificDataList[0] = abi.encode(defaultDeadline, path);

        bytes memory data = abi.encode(routerAddrList, makerSpecificDataList);

        BalanceSnapshot.Snapshot memory inputTokenBalance = BalanceSnapshot.take(genericSwap, inputToken);
        BalanceSnapshot.Snapshot memory outputTokenBalance = BalanceSnapshot.take(genericSwap, outputToken);

        vm.startPrank(genericSwap);
        IERC20(inputToken).safeTransfer(address(ammStrategy), inputAmount);
        IStrategy(ammStrategy).executeStrategy(inputToken, outputToken, inputAmount, data);
        vm.stopPrank();

        inputTokenBalance.assertChange(-int256(inputAmount));
        outputTokenBalance.assertChangeGt(0);
    }
}
