// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IUniswapV3Quoter } from "contracts/interfaces/IUniswapV3Quoter.sol";
import { IUniversalRouter } from "contracts/interfaces/IUniswapUniversalRouter.sol";
import { IUniAgent } from "contracts/interfaces/IUniAgent.sol";
import { UniswapV3 } from "contracts/libraries/UniswapV3.sol";
import { UniswapCommands } from "test/utils/UniswapCommands.sol";
import { UniswapV2Library } from "test/utils/UniswapV2Library.sol";
import { BalanceSnapshot, Snapshot } from "test/utils/BalanceSnapshot.sol";
import { UniAgentTest } from "test/forkMainnet/UniAgent/Setup.t.sol";

contract UniversalTest is UniAgentTest {
    using BalanceSnapshot for Snapshot;

    IUniswapV3Quoter v3Quoter;

    function setUp() public override {
        super.setUp();

        v3Quoter = IUniswapV3Quoter(UNISWAP_V3_QUOTER_ADDRESS);
    }

    function testURV2SwapExactIn() public {
        // USDT -> CRV
        Snapshot memory userInputToken = BalanceSnapshot.take({ owner: user, token: defaultInputToken });
        Snapshot memory recvOutputToken = BalanceSnapshot.take({ owner: recipient, token: defaultOutputToken });

        uint256[] memory amounts = UniswapV2Library.getAmountsOut(defaultInputAmount, defaultPath);
        uint256 outputAmount = amounts[amounts.length - 1];
        uint256 minOutputAmount = (outputAmount * 95) / 100; // default 5% slippage tolerance

        bytes memory cmds = abi.encodePacked(bytes1(uint8(UniswapCommands.V2_SWAP_EXACT_IN)));
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(recipient, defaultInputAmount, minOutputAmount, defaultPath, false);
        bytes memory payload = abi.encodeCall(IUniversalRouter.execute, (cmds, inputs, defaultExpiry));

        vm.prank(user);
        uniAgent.swap(IUniAgent.RouterType.UniversalRouter, defaultInputToken, defaultInputAmount, payload, defaultUserPermit);

        userInputToken.assertChange(-int256(defaultInputAmount));
        // recipient should receive exact amount of quote from Uniswap
        recvOutputToken.assertChange(int256(outputAmount));
    }

    function testURV3SwapExactIn() public {
        // USDT -> CRV
        Snapshot memory userInputToken = BalanceSnapshot.take({ owner: user, token: defaultInputToken });
        Snapshot memory recvOutputToken = BalanceSnapshot.take({ owner: recipient, token: defaultOutputToken });

        uint24[] memory v3Fees = new uint24[](1);
        v3Fees[0] = 3000;
        bytes memory encodedPath = UniswapV3.encodePath(defaultPath, v3Fees);
        uint256 outputAmount = v3Quoter.quoteExactInput(encodedPath, defaultInputAmount);

        bytes memory cmds = abi.encodePacked(bytes1(uint8(UniswapCommands.V3_SWAP_EXACT_IN)));
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(recipient, defaultInputAmount, outputAmount, encodedPath, false);
        bytes memory payload = abi.encodeCall(IUniversalRouter.execute, (cmds, inputs, defaultExpiry));

        vm.prank(user);
        uniAgent.swap(IUniAgent.RouterType.UniversalRouter, defaultInputToken, defaultInputAmount, payload, defaultUserPermit);

        userInputToken.assertChange(-int256(defaultInputAmount));
        // recipient should receive exact amount of quote from Uniswap
        recvOutputToken.assertChange(int256(outputAmount));
    }

    function testURHandleRouterError() public {
        vm.warp(defaultExpiry + 1);

        bytes memory cmds = abi.encodePacked(bytes1(uint8(UniswapCommands.V2_SWAP_EXACT_IN)));
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(recipient, defaultInputAmount, 0, defaultPath, false);
        bytes memory payload = abi.encodeCall(IUniversalRouter.execute, (cmds, inputs, defaultExpiry));

        vm.expectRevert(IUniversalRouter.TransactionDeadlinePassed.selector);
        vm.prank(user);
        uniAgent.swap(IUniAgent.RouterType.UniversalRouter, defaultInputToken, defaultInputAmount, payload, defaultUserPermit);
    }
}
