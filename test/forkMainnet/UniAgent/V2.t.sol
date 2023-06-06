// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IUniswapRouterV2 } from "contracts//interfaces/IUniswapRouterV2.sol";
import { IUniAgent } from "contracts/interfaces/IUniAgent.sol";
import { Constant } from "contracts/libraries/Constant.sol";
import { BalanceSnapshot, Snapshot } from "test/utils/BalanceSnapshot.sol";
import { UniAgentTest } from "test/forkMainnet/UniAgent/Setup.t.sol";

contract V2Test is UniAgentTest {
    using BalanceSnapshot for Snapshot;

    IUniswapRouterV2 v2Router;
    uint256 defaultOutputAmount;
    bytes defaultRouterPayload;

    function setUp() public override {
        super.setUp();

        v2Router = IUniswapRouterV2(UNISWAP_V2_ADDRESS);
        uint256[] memory amounts = v2Router.getAmountsOut(defaultInputAmount, defaultPath);
        defaultOutputAmount = amounts[amounts.length - 1];
        uint256 minOutputAmount = (defaultOutputAmount * 95) / 100; // default 5% slippage tolerance

        defaultRouterPayload = abi.encodeCall(
            IUniswapRouterV2.swapExactTokensForTokens,
            (defaultInputAmount, minOutputAmount, defaultPath, recipient, defaultExpiry)
        );
    }

    function testV2SwapExactTokensForTokens() public {
        // USDT -> CRV
        Snapshot memory userInputToken = BalanceSnapshot.take({ owner: user, token: defaultInputToken });
        Snapshot memory recvOutputToken = BalanceSnapshot.take({ owner: recipient, token: defaultOutputToken });

        vm.prank(user);
        uniAgent.swap(IUniAgent.RouterType.V2Router, defaultInputToken, defaultInputAmount, defaultRouterPayload, defaultUserPermit);

        userInputToken.assertChange(-int256(defaultInputAmount));
        // recipient should receive exact amount of quote from Uniswap
        recvOutputToken.assertChange(int256(defaultOutputAmount));
    }

    function testV2SwapExactETHForTokens() public {
        // ETH -> CRV
        address inputToken = Constant.ETH_ADDRESS;
        address[] memory path = new address[](2);
        // uniswap always use WETH in path
        path[0] = WETH_ADDRESS;
        path[1] = CRV_ADDRESS;

        Snapshot memory userInputToken = BalanceSnapshot.take({ owner: user, token: inputToken });
        Snapshot memory recvOutputToken = BalanceSnapshot.take({ owner: recipient, token: path[1] });

        uint256[] memory amounts = v2Router.getAmountsOut(defaultInputAmount, path);
        uint256 outputAmount = amounts[amounts.length - 1];

        bytes memory payload = abi.encodeCall(IUniswapRouterV2.swapExactETHForTokens, (outputAmount, path, recipient, defaultExpiry));

        vm.prank(user);
        uniAgent.swap{ value: defaultInputAmount }(IUniAgent.RouterType.V2Router, inputToken, defaultInputAmount, payload, defaultUserPermit);

        userInputToken.assertChange(-int256(defaultInputAmount));
        // recipient should receive exact amount of quote from Uniswap
        recvOutputToken.assertChange(int256(outputAmount));
    }

    function testV2SwapExactTokensForETH() public {
        // USDT -> ETH
        address outputToken = Constant.ETH_ADDRESS;
        address[] memory path = new address[](2);
        // uniswap always use WETH in path
        path[0] = USDT_ADDRESS;
        path[1] = WETH_ADDRESS;

        Snapshot memory userInputToken = BalanceSnapshot.take({ owner: user, token: path[0] });
        Snapshot memory recvOutputToken = BalanceSnapshot.take({ owner: recipient, token: outputToken });

        uint256[] memory amounts = v2Router.getAmountsOut(defaultInputAmount, path);
        uint256 outputAmount = amounts[amounts.length - 1];

        bytes memory payload = abi.encodeCall(IUniswapRouterV2.swapExactTokensForETH, (defaultInputAmount, outputAmount, path, recipient, defaultExpiry));

        vm.prank(user);
        uniAgent.swap(IUniAgent.RouterType.V2Router, path[0], defaultInputAmount, payload, defaultUserPermit);

        userInputToken.assertChange(-int256(defaultInputAmount));
        // recipient should receive exact amount of quote from Uniswap
        recvOutputToken.assertChange(int256(outputAmount));
    }

    function testV2ApproveAndSwap() public {
        // USDC -> CRV
        address inputToken = USDC_ADDRESS;
        Snapshot memory userInputToken = BalanceSnapshot.take({ owner: user, token: inputToken });
        Snapshot memory recvOutputToken = BalanceSnapshot.take({ owner: recipient, token: defaultOutputToken });

        address[] memory path = new address[](2);
        path[0] = inputToken;
        path[1] = defaultOutputToken;

        uint256[] memory amounts = v2Router.getAmountsOut(defaultInputAmount, path);
        uint256 outputAmount = amounts[amounts.length - 1];

        bytes memory payload = abi.encodeCall(IUniswapRouterV2.swapExactTokensForTokens, (defaultInputAmount, outputAmount, path, recipient, defaultExpiry));

        vm.prank(user);
        uniAgent.approveAndSwap(IUniAgent.RouterType.V2Router, inputToken, defaultInputAmount, payload, defaultUserPermit);

        userInputToken.assertChange(-int256(defaultInputAmount));
        // recipient should receive exact amount of quote from Uniswap
        recvOutputToken.assertChange(int256(outputAmount));
    }

    function testV2WithDupplicatedApprove() public {
        // case1 : input token is USDT
        // USDT will revert if approve to a spender but current allownace != 0
        vm.prank(user);
        vm.expectRevert();
        uniAgent.approveAndSwap(IUniAgent.RouterType.V2Router, defaultInputToken, defaultInputAmount, defaultRouterPayload, defaultUserPermit);

        // case2 : input token is WETH
        // WETH will overwrite allowance without any check
        address inputToken = WETH_ADDRESS;
        Snapshot memory userInputToken = BalanceSnapshot.take({ owner: user, token: inputToken });
        Snapshot memory recvOutputToken = BalanceSnapshot.take({ owner: recipient, token: defaultOutputToken });

        address[] memory path = new address[](2);
        path[0] = inputToken;
        path[1] = defaultOutputToken;

        uint256[] memory amounts = v2Router.getAmountsOut(defaultInputAmount, path);
        uint256 outputAmount = amounts[amounts.length - 1];

        bytes memory payload = abi.encodeCall(IUniswapRouterV2.swapExactTokensForTokens, (defaultInputAmount, outputAmount, path, recipient, defaultExpiry));

        // should still succeed even re-approve the token
        vm.startPrank(user);
        address[] memory approveList = new address[](1);
        approveList[0] = inputToken;
        uniAgent.approveTokensToRouters(approveList);
        uniAgent.approveAndSwap(IUniAgent.RouterType.V2Router, inputToken, defaultInputAmount, payload, defaultUserPermit);
        vm.stopPrank();

        userInputToken.assertChange(-int256(defaultInputAmount));
        // recipient should receive exact amount of quote from Uniswap
        recvOutputToken.assertChange(int256(outputAmount));
    }

    function testV2HandleRouterError() public {
        vm.warp(defaultExpiry + 1);

        vm.expectRevert("UniswapV2Router: EXPIRED");
        vm.prank(user);
        uniAgent.swap(IUniAgent.RouterType.V2Router, defaultInputToken, defaultInputAmount, defaultRouterPayload, defaultUserPermit);
    }
}
