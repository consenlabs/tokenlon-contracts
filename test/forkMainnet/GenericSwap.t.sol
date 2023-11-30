// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";
import { Tokens } from "test/utils/Tokens.sol";
import { BalanceUtil } from "test/utils/BalanceUtil.sol";
import { SigHelper } from "test/utils/SigHelper.sol";
import { BalanceSnapshot, Snapshot } from "test/utils/BalanceSnapshot.sol";
import { computeContractAddress } from "test/utils/Addresses.sol";
import { Permit2Helper } from "test/utils/Permit2Helper.sol";
import { UniswapV3 } from "test/utils/UniswapV3.sol";
import { IUniswapV3Quoter } from "test/utils/IUniswapV3Quoter.sol";
import { IUniswapSwapRouter02 } from "test/utils/IUniswapSwapRouter02.sol";
import { MockStrategy } from "test/mocks/MockStrategy.sol";
import { GenericSwap } from "contracts/GenericSwap.sol";
import { AllowanceTarget } from "contracts/AllowanceTarget.sol";
import { TokenCollector } from "contracts/abstracts/TokenCollector.sol";
import { SmartOrderStrategy } from "contracts/SmartOrderStrategy.sol";
import { Constant } from "contracts/libraries/Constant.sol";
import { GenericSwapData, getGSDataHash } from "contracts/libraries/GenericSwapData.sol";
import { IGenericSwap } from "contracts/interfaces/IGenericSwap.sol";
import { ISmartOrderStrategy } from "contracts/interfaces/ISmartOrderStrategy.sol";

contract GenericSwapTest is Test, Tokens, BalanceUtil, Permit2Helper, SigHelper {
    using BalanceSnapshot for Snapshot;

    event Swap(
        bytes32 indexed swapHash,
        address indexed maker,
        address indexed taker,
        address recipient,
        address inputToken,
        uint256 inputAmount,
        address outputToken,
        uint256 outputAmount
    );

    address strategyAdmin = makeAddr("strategyAdmin");
    address allowanceTargetOwner = makeAddr("allowanceTargetOwner");
    uint256 takerPrivateKey = uint256(1);
    address taker = vm.addr(takerPrivateKey);
    uint256 defaultExpiry = block.timestamp + 1;
    address defaultInputToken = USDT_ADDRESS;
    uint256 defaultInputAmount = 10 * 1e6;
    address defaultOutputToken = DAI_ADDRESS;
    address[] defaultPath = [defaultInputToken, defaultOutputToken];
    uint24[] defaultV3Fees = [3000];
    bytes defaultTakerPermit;
    SmartOrderStrategy smartStrategy;
    GenericSwap genericSwap;
    GenericSwapData defaultGSData;
    MockStrategy mockStrategy;
    AllowanceTarget allowanceTarget;

    function setUp() public {
        // deploy allowance target
        address[] memory trusted = new address[](1);
        // pre-compute GenericSwap address since the whitelist of allowance target is immutable
        // NOTE: this assumes GenericSwap is deployed right next to Allowance Target
        trusted[0] = computeContractAddress(address(this), uint8(vm.getNonce(address(this)) + 1));
        allowanceTarget = new AllowanceTarget(allowanceTargetOwner, trusted);

        genericSwap = new GenericSwap(UNISWAP_PERMIT2_ADDRESS, address(allowanceTarget));
        smartStrategy = new SmartOrderStrategy(strategyAdmin, address(genericSwap), WETH_ADDRESS);

        // deposit 1 wei in SOR and GS
        deal(DAI_ADDRESS, address(smartStrategy), 1 wei);
        deal(DAI_ADDRESS, address(genericSwap), 1 wei);
        deal(address(genericSwap), 1 wei);

        mockStrategy = new MockStrategy();
        vm.prank(strategyAdmin);
        address[] memory tokenList = new address[](1);
        tokenList[0] = USDT_ADDRESS;
        address[] memory ammList = new address[](1);
        ammList[0] = UNISWAP_SWAP_ROUTER_02_ADDRESS;
        smartStrategy.approveTokens(tokenList, ammList);

        IUniswapV3Quoter v3Quoter = IUniswapV3Quoter(UNISWAP_V3_QUOTER_ADDRESS);
        bytes memory encodedPath = UniswapV3.encodePath(defaultPath, defaultV3Fees);
        uint256 expectedOut = v3Quoter.quoteExactInput(encodedPath, defaultInputAmount);
        uint256 minOutputAmount = (expectedOut * 95) / 100; // default 5% slippage tolerance
        bytes memory routerPayload = abi.encodeCall(
            IUniswapSwapRouter02.exactInputSingle,
            (
                IUniswapSwapRouter02.ExactInputSingleParams({
                    tokenIn: defaultInputToken,
                    tokenOut: defaultOutputToken,
                    fee: defaultV3Fees[0],
                    recipient: address(smartStrategy),
                    amountIn: defaultInputAmount,
                    amountOutMinimum: minOutputAmount,
                    sqrtPriceLimitX96: 0
                })
            )
        );
        ISmartOrderStrategy.Operation[] memory operations = new ISmartOrderStrategy.Operation[](1);
        operations[0] = ISmartOrderStrategy.Operation({
            dest: UNISWAP_SWAP_ROUTER_02_ADDRESS,
            inputToken: defaultInputToken,
            inputRatio: 0, // zero ratio indicate no replacement
            dataOffset: 0,
            value: 0,
            data: routerPayload
        });
        bytes memory swapData = abi.encode(operations);

        deal(taker, 100 ether);
        setTokenBalanceAndApprove(taker, UNISWAP_PERMIT2_ADDRESS, tokens, 100000);
        deal(address(mockStrategy), 100 ether);
        setTokenBalanceAndApprove(address(mockStrategy), UNISWAP_PERMIT2_ADDRESS, tokens, 100000);

        defaultGSData = GenericSwapData({
            maker: payable(address(smartStrategy)),
            takerToken: defaultInputToken,
            takerTokenAmount: defaultInputAmount,
            makerToken: defaultOutputToken,
            makerTokenAmount: expectedOut,
            minMakerTokenAmount: minOutputAmount,
            expiry: defaultExpiry,
            salt: 5678,
            recipient: payable(taker),
            strategyData: swapData
        });

        defaultTakerPermit = getTokenlonPermit2Data(taker, takerPrivateKey, defaultGSData.takerToken, address(genericSwap));
    }

    function testGenericSwapWithUniswap() public {
        Snapshot memory takerTakerToken = BalanceSnapshot.take({ owner: taker, token: defaultGSData.takerToken });
        Snapshot memory takerMakerToken = BalanceSnapshot.take({ owner: taker, token: defaultGSData.makerToken });

        vm.expectEmit(true, true, true, true);
        emit Swap(
            getGSDataHash(defaultGSData),
            defaultGSData.maker,
            taker,
            taker,
            defaultGSData.takerToken,
            defaultGSData.takerTokenAmount,
            defaultGSData.makerToken,
            defaultGSData.makerTokenAmount
        );

        vm.prank(taker);
        genericSwap.executeSwap(defaultGSData, defaultTakerPermit);

        takerTakerToken.assertChange(-int256(defaultGSData.takerTokenAmount));
        // the makerTokenAmount in the defaultGSData is the exact quote from strategy
        takerMakerToken.assertChange(int256(defaultGSData.makerTokenAmount));
    }

    function testSwapWithLessOutputButWithinTolerance() public {
        GenericSwapData memory gsData = defaultGSData;
        gsData.maker = payable(address(mockStrategy));
        gsData.makerTokenAmount = 1000;
        gsData.minMakerTokenAmount = 800;

        Snapshot memory takerTakerToken = BalanceSnapshot.take({ owner: taker, token: gsData.takerToken });
        Snapshot memory takerMakerToken = BalanceSnapshot.take({ owner: taker, token: gsData.makerToken });
        Snapshot memory makerTakerToken = BalanceSnapshot.take({ owner: address(mockStrategy), token: gsData.takerToken });
        Snapshot memory makerMakerToken = BalanceSnapshot.take({ owner: address(mockStrategy), token: gsData.makerToken });

        uint256 actualOutput = 900;

        // 800 < 900 < 1000
        mockStrategy.setOutputAmountAndRecipient(actualOutput, payable(address(genericSwap)));
        vm.expectEmit(true, true, true, true);
        emit Swap(getGSDataHash(gsData), gsData.maker, taker, taker, gsData.takerToken, gsData.takerTokenAmount, gsData.makerToken, actualOutput);
        vm.prank(taker);
        genericSwap.executeSwap(gsData, defaultTakerPermit);

        takerTakerToken.assertChange(-int256(gsData.takerTokenAmount));
        takerMakerToken.assertChange(int256(actualOutput));
        makerTakerToken.assertChange(int256(gsData.takerTokenAmount));
        makerMakerToken.assertChange(-int256(actualOutput));
    }

    function testSwapWithETHInput() public {
        GenericSwapData memory gsData = defaultGSData;
        gsData.maker = payable(address(mockStrategy));
        gsData.takerToken = Constant.ETH_ADDRESS;
        gsData.takerTokenAmount = 1 ether;

        Snapshot memory takerTakerToken = BalanceSnapshot.take({ owner: taker, token: gsData.takerToken });
        Snapshot memory takerMakerToken = BalanceSnapshot.take({ owner: taker, token: gsData.makerToken });
        Snapshot memory makerTakerToken = BalanceSnapshot.take({ owner: address(mockStrategy), token: gsData.takerToken });
        Snapshot memory makerMakerToken = BalanceSnapshot.take({ owner: address(mockStrategy), token: gsData.makerToken });

        mockStrategy.setOutputAmountAndRecipient(gsData.makerTokenAmount, payable(address(genericSwap)));
        vm.expectEmit(true, true, true, true);
        emit Swap(getGSDataHash(gsData), gsData.maker, taker, taker, gsData.takerToken, gsData.takerTokenAmount, gsData.makerToken, gsData.makerTokenAmount);
        vm.prank(taker);
        genericSwap.executeSwap{ value: gsData.takerTokenAmount }(gsData, defaultTakerPermit);

        takerTakerToken.assertChange(-int256(gsData.takerTokenAmount));
        takerMakerToken.assertChange(int256(gsData.makerTokenAmount));
        makerTakerToken.assertChange(int256(gsData.takerTokenAmount));
        makerMakerToken.assertChange(-int256(gsData.makerTokenAmount));
    }

    function testSwapWithETHOutput() public {
        GenericSwapData memory gsData = defaultGSData;
        gsData.maker = payable(address(mockStrategy));
        gsData.makerToken = Constant.ETH_ADDRESS;
        gsData.makerTokenAmount = 1 ether;
        gsData.minMakerTokenAmount = 1 ether - 1000;

        Snapshot memory takerTakerToken = BalanceSnapshot.take({ owner: taker, token: gsData.takerToken });
        Snapshot memory takerMakerToken = BalanceSnapshot.take({ owner: taker, token: gsData.makerToken });
        Snapshot memory makerTakerToken = BalanceSnapshot.take({ owner: address(mockStrategy), token: gsData.takerToken });
        Snapshot memory makerMakerToken = BalanceSnapshot.take({ owner: address(mockStrategy), token: gsData.makerToken });

        mockStrategy.setOutputAmountAndRecipient(gsData.makerTokenAmount, payable(address(genericSwap)));
        vm.expectEmit(true, true, true, true);
        emit Swap(getGSDataHash(gsData), gsData.maker, taker, taker, gsData.takerToken, gsData.takerTokenAmount, gsData.makerToken, gsData.makerTokenAmount);
        vm.prank(taker);
        genericSwap.executeSwap(gsData, defaultTakerPermit);

        takerTakerToken.assertChange(-int256(gsData.takerTokenAmount));
        takerMakerToken.assertChange(int256(gsData.makerTokenAmount));
        makerTakerToken.assertChange(int256(gsData.takerTokenAmount));
        makerMakerToken.assertChange(-int256(gsData.makerTokenAmount));
    }

    function testCannotSwapWithExpiredOrder() public {
        vm.warp(defaultExpiry + 1);

        vm.prank(taker);
        vm.expectRevert(IGenericSwap.ExpiredOrder.selector);
        genericSwap.executeSwap(defaultGSData, defaultTakerPermit);
    }

    function testCannotSwapWithInvalidETHInput() public {
        // case1 : msg.value != 0 when takerToken is not ETH
        vm.expectRevert(IGenericSwap.InvalidMsgValue.selector);
        genericSwap.executeSwap{ value: 1 }(defaultGSData, defaultTakerPermit);

        // change input token as ETH and update amount
        GenericSwapData memory gsData = defaultGSData;
        gsData.takerToken = Constant.ETH_ADDRESS;
        gsData.takerTokenAmount = 1 ether;

        // case2 : msg.value > takerTokenAmount
        vm.prank(taker);
        vm.expectRevert(IGenericSwap.InvalidMsgValue.selector);
        genericSwap.executeSwap{ value: gsData.takerTokenAmount + 1 }(gsData, defaultTakerPermit);

        // case3 : msg.value < takerTokenAmount
        vm.prank(taker);
        vm.expectRevert(IGenericSwap.InvalidMsgValue.selector);
        genericSwap.executeSwap{ value: gsData.takerTokenAmount - 1 }(gsData, defaultTakerPermit);
    }

    function testCannotSwapWithInsufficientOutput() public {
        // set mockStrategy as maker
        GenericSwapData memory gsData = defaultGSData;
        gsData.maker = payable(address(mockStrategy));

        mockStrategy.setOutputAmountAndRecipient(gsData.minMakerTokenAmount - 1, payable(address(genericSwap)));
        vm.prank(taker);
        vm.expectRevert(IGenericSwap.InsufficientOutput.selector);
        genericSwap.executeSwap(gsData, defaultTakerPermit);
    }

    function testCannotSwapWithZeroRecipient() public {
        GenericSwapData memory gsData = defaultGSData;
        gsData.recipient = payable(address(0));

        vm.prank(taker);
        vm.expectRevert(IGenericSwap.ZeroAddress.selector);
        genericSwap.executeSwap(gsData, defaultTakerPermit);
    }

    function testGenericSwapRelayed() public {
        Snapshot memory takerTakerToken = BalanceSnapshot.take({ owner: taker, token: defaultGSData.takerToken });
        Snapshot memory takerMakerToken = BalanceSnapshot.take({ owner: taker, token: defaultGSData.makerToken });

        vm.expectEmit(true, true, true, true);
        emit Swap(
            getGSDataHash(defaultGSData),
            defaultGSData.maker,
            taker,
            taker,
            defaultGSData.takerToken,
            defaultGSData.takerTokenAmount,
            defaultGSData.makerToken,
            defaultGSData.makerTokenAmount
        );

        bytes memory takerSig = signGenericSwap(takerPrivateKey, defaultGSData, address(genericSwap));
        genericSwap.executeSwapWithSig(defaultGSData, defaultTakerPermit, taker, takerSig);

        takerTakerToken.assertChange(-int256(defaultGSData.takerTokenAmount));
        // the makerTokenAmount in the defaultGSData is the exact quote from strategy
        takerMakerToken.assertChange(int256(defaultGSData.makerTokenAmount));
    }

    function testSwapRelayedWithInvalidSig() public {
        uint256 randomPrivateKey = 5677;
        bytes memory randomSig = signGenericSwap(randomPrivateKey, defaultGSData, address(genericSwap));

        vm.expectRevert(IGenericSwap.InvalidSignature.selector);
        // submit with user address as expected signer
        genericSwap.executeSwapWithSig(defaultGSData, defaultTakerPermit, taker, randomSig);
    }

    function testCannotReplayGenericSwapSig() public {
        bytes memory takerSig = signGenericSwap(takerPrivateKey, defaultGSData, address(genericSwap));
        genericSwap.executeSwapWithSig(defaultGSData, defaultTakerPermit, taker, takerSig);

        vm.expectRevert(IGenericSwap.AlreadyFilled.selector);
        genericSwap.executeSwapWithSig(defaultGSData, defaultTakerPermit, taker, takerSig);
    }
}
