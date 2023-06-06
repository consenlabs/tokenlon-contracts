// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IUniswapV3Quoter } from "contracts/interfaces/IUniswapV3Quoter.sol";
import { IUniswapV3SwapRouter } from "contracts/interfaces/IUniswapV3SwapRouter.sol";
import { IUniAgent } from "contracts/interfaces/IUniAgent.sol";
import { UniswapV3 } from "contracts/libraries/UniswapV3.sol";
import { BalanceSnapshot, Snapshot } from "test/utils/BalanceSnapshot.sol";
import { UniAgentTest } from "test/forkMainnet/UniAgent/Setup.t.sol";

contract V3Test is UniAgentTest {
    using BalanceSnapshot for Snapshot;

    IUniswapV3Quoter v3Quoter;
    uint24 defaultFee = 3000;
    uint24[] v3Fees = [defaultFee];
    uint256 defaultOutputAmount;
    bytes defaultRouterPayload;

    function setUp() public override {
        super.setUp();

        v3Quoter = IUniswapV3Quoter(UNISWAP_V3_QUOTER_ADDRESS);
        bytes memory encodedPath = UniswapV3.encodePath(defaultPath, v3Fees);
        defaultOutputAmount = v3Quoter.quoteExactInput(encodedPath, defaultInputAmount);
        uint256 minOutputAmount = (defaultOutputAmount * 95) / 100; // default 5% slippage tolerance

        defaultRouterPayload = abi.encodeCall(
            IUniswapV3SwapRouter.exactInputSingle,
            (
                IUniswapV3SwapRouter.ExactInputSingleParams({
                    tokenIn: defaultInputToken,
                    tokenOut: defaultOutputToken,
                    fee: defaultFee,
                    recipient: recipient,
                    deadline: defaultExpiry,
                    amountIn: defaultInputAmount,
                    amountOutMinimum: minOutputAmount,
                    sqrtPriceLimitX96: 0
                })
            )
        );
    }

    function testV3ExactInputSingle() public {
        // USDT -> CRV
        Snapshot memory userInputToken = BalanceSnapshot.take({ owner: user, token: defaultInputToken });
        Snapshot memory recvOutputToken = BalanceSnapshot.take({ owner: recipient, token: defaultOutputToken });

        vm.prank(user);
        uniAgent.swap(IUniAgent.RouterType.V3Router, defaultInputToken, defaultInputAmount, defaultRouterPayload, defaultUserPermit);

        userInputToken.assertChange(-int256(defaultInputAmount));
        // recipient should receive exact amount of quote from Uniswap
        recvOutputToken.assertChange(int256(defaultOutputAmount));
    }

    function testV3ExactInput() public {
        // USDT -> CRV
        Snapshot memory userInputToken = BalanceSnapshot.take({ owner: user, token: defaultInputToken });
        Snapshot memory recvOutputToken = BalanceSnapshot.take({ owner: recipient, token: defaultOutputToken });

        bytes memory encodedPath = UniswapV3.encodePath(defaultPath, v3Fees);
        bytes memory payload = abi.encodeCall(
            IUniswapV3SwapRouter.exactInput,
            (
                IUniswapV3SwapRouter.ExactInputParams({
                    path: encodedPath,
                    recipient: recipient,
                    deadline: defaultExpiry,
                    amountIn: defaultInputAmount,
                    amountOutMinimum: defaultOutputAmount
                })
            )
        );

        vm.prank(user);
        uniAgent.swap(IUniAgent.RouterType.V3Router, defaultInputToken, defaultInputAmount, payload, defaultUserPermit);

        userInputToken.assertChange(-int256(defaultInputAmount));
        // recipient should receive exact amount of quote from Uniswap
        recvOutputToken.assertChange(int256(defaultOutputAmount));
    }

    function testV3HandleRouterError() public {
        vm.warp(defaultExpiry + 1);

        vm.expectRevert("Transaction too old");
        vm.prank(user);
        uniAgent.swap(IUniAgent.RouterType.V3Router, defaultInputToken, defaultInputAmount, defaultRouterPayload, defaultUserPermit);
    }
}
