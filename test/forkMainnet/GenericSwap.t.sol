// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";
import { Tokens } from "test/utils/Tokens.sol";
import { BalanceUtil } from "test/utils/BalanceUtil.sol";
import { GenericSwap } from "contracts/GenericSwap.sol";
import { TokenCollector } from "contracts/abstracts/TokenCollector.sol";
import { UniswapStrategy } from "contracts/UniswapStrategy.sol";
import { Constant } from "contracts/libraries/Constant.sol";
import { IGenericSwap } from "contracts/interfaces/IGenericSwap.sol";
import { IStrategy } from "contracts/interfaces/IStrategy.sol";

contract GenericSwapTest is Test, Tokens, BalanceUtil {
    address strategyAdmin = makeAddr("strategyAdmin");
    address user = makeAddr("user");
    uint256 defaultDeadline = block.timestamp + 1;
    UniswapStrategy uniswapStrategy;
    GenericSwap genericSwap;
    IGenericSwap.GenericSwapData gsData;

    function setUp() public {
        genericSwap = new GenericSwap(UNISWAP_PERMIT2_ADDRESS);
        uniswapStrategy = new UniswapStrategy(strategyAdmin, address(genericSwap), UNISWAP_V2_ADDRESS);
        vm.prank(strategyAdmin);
        uniswapStrategy.approveToken(USDT_ADDRESS, UNISWAP_V2_ADDRESS, Constant.MAX_UINT);

        address[] memory defaultPath = new address[](2);
        defaultPath[0] = USDT_ADDRESS;
        defaultPath[1] = CRV_ADDRESS;
        bytes memory makerSpecificData = abi.encode(defaultDeadline, defaultPath);
        bytes memory swapData = abi.encode(UNISWAP_V2_ADDRESS, makerSpecificData);
        bytes memory empty;
        bytes memory defaultInputData = abi.encode(TokenCollector.Source.Token, empty);

        setEOABalanceAndApprove(user, address(genericSwap), tokens, 100000);

        // FIXME get the quote dynamically
        gsData = IGenericSwap.GenericSwapData({
            inputToken: USDT_ADDRESS,
            outputToken: CRV_ADDRESS,
            inputAmount: 10 * 1e6,
            minOutputAmount: 1 * 1e18,
            receiver: payable(user),
            deadline: defaultDeadline,
            strategyData: swapData,
            inputData: defaultInputData
        });
    }

    function testGenericSwap() public {
        vm.prank(user);
        genericSwap.executeSwap(IStrategy(uniswapStrategy), gsData);
    }
}
