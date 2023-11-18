// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IUniswapSwapRouter02 } from "test/utils/IUniswapSwapRouter02.sol";
import { IUniswapV3Quoter } from "test/utils/IUniswapV3Quoter.sol";
import { IUniAgent } from "contracts/interfaces/IUniAgent.sol";
import { UniswapV3 } from "test/utils/UniswapV3.sol";
import { BalanceSnapshot, Snapshot } from "test/utils/BalanceSnapshot.sol";
import { UniswapV2Library } from "test/utils/UniswapV2Library.sol";
import { UniAgentTest } from "test/forkMainnet/UniAgent/Setup.t.sol";

contract SwapRouter02Test is UniAgentTest {
    using BalanceSnapshot for Snapshot;

    IUniswapV3Quoter v3Quoter = IUniswapV3Quoter(UNISWAP_V3_QUOTER_ADDRESS);
    uint256 defaultOutputAmount;
    uint24 defaultFee = 3000;
    uint24[] v3Fees = [defaultFee];

    function setUp() public override {
        super.setUp();
    }

    function testV2SwapExactTokensForTokens() public {
        // USDT -> CRV
        Snapshot memory userInputToken = BalanceSnapshot.take({ owner: user, token: defaultInputToken });
        Snapshot memory recvOutputToken = BalanceSnapshot.take({ owner: recipient, token: defaultOutputToken });

        uint256[] memory amounts = UniswapV2Library.getAmountsOut(defaultInputAmount, defaultPath);
        uint256 outputAmount = amounts[amounts.length - 1];
        uint256 minOutputAmount = (defaultOutputAmount * 95) / 100; // default 5% slippage tolerance
        bytes memory payload = abi.encodeCall(IUniswapSwapRouter02.swapExactTokensForTokens, (defaultInputAmount, minOutputAmount, defaultPath, recipient));

        vm.prank(user);
        uniAgent.swap(IUniAgent.RouterType.SwapRouter02, defaultInputToken, defaultInputAmount, payload, defaultUserPermit);

        userInputToken.assertChange(-int256(defaultInputAmount));
        // recipient should receive exact amount of quote from Uniswap
        recvOutputToken.assertChange(int256(outputAmount));
    }

    function testV3ExactInputSingle() public {
        // USDT -> CRV
        Snapshot memory userInputToken = BalanceSnapshot.take({ owner: user, token: defaultInputToken });
        Snapshot memory recvOutputToken = BalanceSnapshot.take({ owner: recipient, token: defaultOutputToken });

        bytes memory encodedPath = UniswapV3.encodePath(defaultPath, v3Fees);
        defaultOutputAmount = v3Quoter.quoteExactInput(encodedPath, defaultInputAmount);
        uint256 minOutputAmount = (defaultOutputAmount * 95) / 100; // default 5% slippage tolerance
        bytes memory payload = abi.encodeCall(
            IUniswapSwapRouter02.exactInputSingle,
            (
                IUniswapSwapRouter02.ExactInputSingleParams({
                    tokenIn: defaultInputToken,
                    tokenOut: defaultOutputToken,
                    fee: defaultFee,
                    recipient: recipient,
                    amountIn: defaultInputAmount,
                    amountOutMinimum: minOutputAmount,
                    sqrtPriceLimitX96: 0
                })
            )
        );

        vm.prank(user);
        uniAgent.swap(IUniAgent.RouterType.SwapRouter02, defaultInputToken, defaultInputAmount, payload, defaultUserPermit);

        userInputToken.assertChange(-int256(defaultInputAmount));
        // recipient should receive exact amount of quote from Uniswap
        recvOutputToken.assertChange(int256(defaultOutputAmount));
    }
}
