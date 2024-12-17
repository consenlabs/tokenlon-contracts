// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";

import { AllowanceTarget } from "contracts/AllowanceTarget.sol";
import { GenericSwap } from "contracts/GenericSwap.sol";
import { SmartOrderStrategy } from "contracts/SmartOrderStrategy.sol";
import { IGenericSwap } from "contracts/interfaces/IGenericSwap.sol";
import { ISmartOrderStrategy } from "contracts/interfaces/ISmartOrderStrategy.sol";
import { Constant } from "contracts/libraries/Constant.sol";
import { GenericSwapData, getGSDataHash } from "contracts/libraries/GenericSwapData.sol";

import { MockStrategy } from "test/mocks/MockStrategy.sol";
import { computeContractAddress } from "test/utils/Addresses.sol";
import { BalanceSnapshot, Snapshot } from "test/utils/BalanceSnapshot.sol";
import { BalanceUtil } from "test/utils/BalanceUtil.sol";
import { IUniswapSwapRouter02 } from "test/utils/IUniswapSwapRouter02.sol";
import { IUniswapV3Quoter } from "test/utils/IUniswapV3Quoter.sol";
import { Permit2Helper } from "test/utils/Permit2Helper.sol";
import { SigHelper } from "test/utils/SigHelper.sol";
import { Tokens } from "test/utils/Tokens.sol";
import { UniswapV3 } from "test/utils/UniswapV3.sol";

contract GenericSwapTest is Test, Tokens, BalanceUtil, Permit2Helper, SigHelper {
    using BalanceSnapshot for Snapshot;

    address strategyAdmin = makeAddr("strategyAdmin");
    address allowanceTargetOwner = makeAddr("allowanceTargetOwner");
    uint256 takerPrivateKey = uint256(1);
    uint256 alicePrivateKey = uint256(2);
    address taker = vm.addr(takerPrivateKey);
    address alice = vm.addr(alicePrivateKey);
    uint256 defaultExpiry = block.timestamp + 1;
    address defaultInputToken = USDT_ADDRESS;
    uint256 defaultInputAmount = 10 * 1e6;
    address defaultOutputToken = DAI_ADDRESS;
    address[] defaultPath = [defaultInputToken, defaultOutputToken];
    uint24[] defaultV3Fees = [3000];
    bytes defaultTakerPermit;
    bytes alicePermit;
    bytes strategyData;
    SmartOrderStrategy smartStrategy;
    GenericSwap genericSwap;
    GenericSwapData defaultGSData;
    GenericSwapData aliceGSData;
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

        mockStrategy = new MockStrategy();
        address[] memory tokenList = new address[](1);
        tokenList[0] = USDT_ADDRESS;
        address[] memory ammList = new address[](1);
        ammList[0] = UNISWAP_SWAP_ROUTER_02_ADDRESS;
        vm.startPrank(strategyAdmin);
        smartStrategy.approveTokens(tokenList, ammList);
        vm.stopPrank();

        IUniswapV3Quoter v3Quoter = IUniswapV3Quoter(UNISWAP_V3_QUOTER_ADDRESS);
        bytes memory encodedPath = UniswapV3.encodePath(defaultPath, defaultV3Fees);
        uint256 expectedOut = v3Quoter.quoteExactInput(encodedPath, defaultInputAmount) - 2; // leaving 1 wei in GS and SOS separately
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
            ratioNumerator: 0, // zero ratio indicate no replacement
            ratioDenominator: 0,
            dataOffset: 0,
            value: 0,
            data: routerPayload
        });
        strategyData = abi.encode(operations);

        deal(taker, 100 ether);
        setTokenBalanceAndApprove(taker, UNISWAP_PERMIT2_ADDRESS, tokens, 100000);
        deal(alice, 100 ether);
        setTokenBalanceAndApprove(alice, UNISWAP_PERMIT2_ADDRESS, tokens, 100000);
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
            recipient: payable(taker)
        });

        defaultTakerPermit = getTokenlonPermit2Data(taker, takerPrivateKey, defaultGSData.takerToken, address(genericSwap));
    }

    function testGenericSwapInitialState() public {
        genericSwap = new GenericSwap(UNISWAP_PERMIT2_ADDRESS, address(allowanceTarget));

        assertEq(genericSwap.permit2(), UNISWAP_PERMIT2_ADDRESS);
        assertEq(genericSwap.allowanceTarget(), address(allowanceTarget));
    }

    function testGenericSwapWithUniswap() public {
        Snapshot memory takerTakerToken = BalanceSnapshot.take({ owner: taker, token: defaultGSData.takerToken });
        Snapshot memory takerMakerToken = BalanceSnapshot.take({ owner: taker, token: defaultGSData.makerToken });

        vm.expectEmit(true, true, true, true);
        emit IGenericSwap.Swap(
            getGSDataHash(defaultGSData),
            defaultGSData.maker,
            taker,
            taker,
            defaultGSData.takerToken,
            defaultGSData.takerTokenAmount,
            defaultGSData.makerToken,
            defaultGSData.makerTokenAmount,
            defaultGSData.salt
        );

        vm.startPrank(taker);
        genericSwap.executeSwap(defaultGSData, defaultTakerPermit);
        vm.stopPrank();
        vm.snapshotGasLastCall("GenericSwap", "executeSwap(): testGenericSwapWithUniswap");

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
        uint256 realChangedInGS = actualOutput - 1; // leaving 1 wei in GS

        // 800 < 900 < 1000
        mockStrategy.setOutputAmountAndRecipient(actualOutput, payable(address(genericSwap)));
        vm.expectEmit(true, true, true, true);
        emit IGenericSwap.Swap(
            getGSDataHash(gsData),
            gsData.maker,
            taker,
            taker,
            gsData.takerToken,
            gsData.takerTokenAmount,
            gsData.makerToken,
            realChangedInGS,
            gsData.salt
        );
        vm.startPrank(taker);
        genericSwap.executeSwap(gsData, defaultTakerPermit);
        vm.stopPrank();
        vm.snapshotGasLastCall("GenericSwap", "executeSwap(): testSwapWithLessOutputButWithinTolerance");

        takerTakerToken.assertChange(-int256(gsData.takerTokenAmount));
        takerMakerToken.assertChange(int256(realChangedInGS));
        makerTakerToken.assertChange(int256(gsData.takerTokenAmount));
        makerMakerToken.assertChange(-int256(actualOutput));
    }

    function testSwapWithETHInput() public {
        GenericSwapData memory gsData = defaultGSData;
        gsData.maker = payable(address(mockStrategy));
        gsData.takerToken = Constant.ETH_ADDRESS;
        gsData.takerTokenAmount = 1 ether;

        uint256 realChangedInGS = gsData.makerTokenAmount - 1; // leaving 1 wei in GS

        Snapshot memory takerTakerToken = BalanceSnapshot.take({ owner: taker, token: gsData.takerToken });
        Snapshot memory takerMakerToken = BalanceSnapshot.take({ owner: taker, token: gsData.makerToken });
        Snapshot memory makerTakerToken = BalanceSnapshot.take({ owner: address(mockStrategy), token: gsData.takerToken });
        Snapshot memory makerMakerToken = BalanceSnapshot.take({ owner: address(mockStrategy), token: gsData.makerToken });

        mockStrategy.setOutputAmountAndRecipient(gsData.makerTokenAmount, payable(address(genericSwap)));
        vm.expectEmit(true, true, true, true);
        emit IGenericSwap.Swap(
            getGSDataHash(gsData),
            gsData.maker,
            taker,
            taker,
            gsData.takerToken,
            gsData.takerTokenAmount,
            gsData.makerToken,
            realChangedInGS,
            gsData.salt
        );
        vm.startPrank(taker);
        genericSwap.executeSwap{ value: gsData.takerTokenAmount }(gsData, defaultTakerPermit);
        vm.stopPrank();
        vm.snapshotGasLastCall("GenericSwap", "executeSwap(): testSwapWithETHInput");

        takerTakerToken.assertChange(-int256(gsData.takerTokenAmount));
        takerMakerToken.assertChange(int256(realChangedInGS));
        makerTakerToken.assertChange(int256(gsData.takerTokenAmount));
        makerMakerToken.assertChange(-int256(gsData.makerTokenAmount));
    }

    function testSwapWithETHOutput() public {
        GenericSwapData memory gsData = defaultGSData;
        gsData.maker = payable(address(mockStrategy));
        gsData.makerToken = Constant.ETH_ADDRESS;
        gsData.makerTokenAmount = 1 ether;
        gsData.minMakerTokenAmount = 1 ether - 1000;

        uint256 realChangedInGS = gsData.makerTokenAmount - 1; // leaving 1 wei in GS

        Snapshot memory takerTakerToken = BalanceSnapshot.take({ owner: taker, token: gsData.takerToken });
        Snapshot memory takerMakerToken = BalanceSnapshot.take({ owner: taker, token: gsData.makerToken });
        Snapshot memory makerTakerToken = BalanceSnapshot.take({ owner: address(mockStrategy), token: gsData.takerToken });
        Snapshot memory makerMakerToken = BalanceSnapshot.take({ owner: address(mockStrategy), token: gsData.makerToken });

        mockStrategy.setOutputAmountAndRecipient(gsData.makerTokenAmount, payable(address(genericSwap)));
        vm.expectEmit(true, true, true, true);
        emit IGenericSwap.Swap(
            getGSDataHash(gsData),
            gsData.maker,
            taker,
            taker,
            gsData.takerToken,
            gsData.takerTokenAmount,
            gsData.makerToken,
            realChangedInGS,
            gsData.salt
        );
        vm.startPrank(taker);
        genericSwap.executeSwap(gsData, defaultTakerPermit);
        vm.stopPrank();
        vm.snapshotGasLastCall("GenericSwap", "executeSwap(): testSwapWithETHOutput");

        takerTakerToken.assertChange(-int256(gsData.takerTokenAmount));
        takerMakerToken.assertChange(int256(realChangedInGS));
        makerTakerToken.assertChange(int256(gsData.takerTokenAmount));
        makerMakerToken.assertChange(-int256(gsData.makerTokenAmount));
    }

    function testCannotSwapWithExpiredOrder() public {
        vm.warp(defaultExpiry + 1);

        vm.startPrank(taker);
        vm.expectRevert(IGenericSwap.ExpiredOrder.selector);
        genericSwap.executeSwap(defaultGSData, defaultTakerPermit);
        vm.stopPrank();
    }

    function testCannotSwapWithInvalidETHInput() public {
        // case1 : msg.value != 0 when takerToken is not ETH
        vm.expectRevert(IGenericSwap.InvalidMsgValue.selector);
        genericSwap.executeSwap{ value: 1 }(defaultGSData, strategyData, defaultTakerPermit);

        // change input token as ETH and update amount
        GenericSwapData memory gsData = defaultGSData;
        gsData.takerToken = Constant.ETH_ADDRESS;
        gsData.takerTokenAmount = 1 ether;

        // case2 : msg.value > takerTokenAmount
        vm.startPrank(taker);
        vm.expectRevert(IGenericSwap.InvalidMsgValue.selector);
        genericSwap.executeSwap{ value: gsData.takerTokenAmount + 1 }(gsData, defaultTakerPermit);
        vm.stopPrank();

        // case3 : msg.value < takerTokenAmount
        vm.startPrank(taker);
        vm.expectRevert(IGenericSwap.InvalidMsgValue.selector);
        genericSwap.executeSwap{ value: gsData.takerTokenAmount - 1 }(gsData, defaultTakerPermit);
        vm.stopPrank();
    }

    function testCannotSwapWithInsufficientOutput() public {
        // set mockStrategy as maker
        GenericSwapData memory gsData = defaultGSData;
        gsData.maker = payable(address(mockStrategy));

        mockStrategy.setOutputAmountAndRecipient(gsData.minMakerTokenAmount - 1, payable(address(genericSwap)));
        vm.startPrank(taker);
        vm.expectRevert(IGenericSwap.InsufficientOutput.selector);
        genericSwap.executeSwap(gsData, defaultTakerPermit);
        vm.stopPrank();
    }

    function testCannotSwapWithZeroRecipient() public {
        GenericSwapData memory gsData = defaultGSData;
        gsData.recipient = payable(address(0));

        vm.startPrank(taker);
        vm.expectRevert(IGenericSwap.ZeroAddress.selector);
        genericSwap.executeSwap(gsData, defaultTakerPermit);
        vm.stopPrank();
    }

    function testCannotSwapWithZeroAmount() public {
        GenericSwapData memory gsData = defaultGSData;
        gsData.takerTokenAmount = 0;

        vm.startPrank(taker);
        vm.expectRevert(IGenericSwap.SwapWithZeroAmount.selector);
        genericSwap.executeSwap(gsData, defaultTakerPermit);
        vm.stopPrank();
    }

    function testGenericSwapRelayed() public {
        Snapshot memory takerTakerToken = BalanceSnapshot.take({ owner: taker, token: defaultGSData.takerToken });
        Snapshot memory takerMakerToken = BalanceSnapshot.take({ owner: taker, token: defaultGSData.makerToken });

        vm.expectEmit(true, true, true, true);
        emit IGenericSwap.Swap(
            getGSDataHash(defaultGSData),
            defaultGSData.maker,
            taker,
            taker,
            defaultGSData.takerToken,
            defaultGSData.takerTokenAmount,
            defaultGSData.makerToken,
            defaultGSData.makerTokenAmount,
            defaultGSData.salt
        );

        bytes memory takerSig = signGenericSwap(takerPrivateKey, defaultGSData, address(genericSwap));
        genericSwap.executeSwapWithSig(defaultGSData, defaultTakerPermit, taker, takerSig);
        vm.snapshotGasLastCall("GenericSwap", "executeSwapWithSig(): testGenericSwapRelayed");

        takerTakerToken.assertChange(-int256(defaultGSData.takerTokenAmount));
        // the makerTokenAmount in the defaultGSData is the exact quote from strategy
        takerMakerToken.assertChange(int256(defaultGSData.makerTokenAmount));
    }

    function testSwapRelayedWithInvalidSig() public {
        uint256 randomPrivateKey = 5677;
        bytes memory randomSig = signGenericSwap(randomPrivateKey, defaultGSData, address(genericSwap));

        vm.expectRevert(IGenericSwap.InvalidSignature.selector);
        // submit with user address as expected signer
        genericSwap.executeSwapWithSig(defaultGSData, strategyData, defaultTakerPermit, taker, randomSig);
    }

    function testCannotReplayGenericSwapSig() public {
        bytes memory takerSig = signGenericSwap(takerPrivateKey, defaultGSData, address(genericSwap));
        genericSwap.executeSwapWithSig(defaultGSData, strategyData, defaultTakerPermit, taker, takerSig);

        vm.expectRevert(IGenericSwap.AlreadyFilled.selector);
        genericSwap.executeSwapWithSig(defaultGSData, strategyData, defaultTakerPermit, taker, takerSig);
    }

    function testLeaveOneWeiWithMultipleUsers() public {
        Snapshot memory takerTakerToken = BalanceSnapshot.take({ owner: taker, token: defaultGSData.takerToken });
        Snapshot memory takerMakerToken = BalanceSnapshot.take({ owner: taker, token: defaultGSData.makerToken });
        Snapshot memory gsTakerToken = BalanceSnapshot.take({ owner: address(genericSwap), token: defaultGSData.takerToken });
        Snapshot memory gsMakerToken = BalanceSnapshot.take({ owner: address(genericSwap), token: defaultGSData.makerToken });
        Snapshot memory makerTakerToken = BalanceSnapshot.take({ owner: defaultGSData.maker, token: defaultGSData.takerToken });
        Snapshot memory makerMakerToken = BalanceSnapshot.take({ owner: defaultGSData.maker, token: defaultGSData.makerToken });

        // the first user: taker
        // his makerTokenAmount has already been reduced by 2 in the setup function
        // leaving 1 wei in GS and SOS separately
        vm.expectEmit(true, true, true, true);
        emit IGenericSwap.Swap(
            getGSDataHash(defaultGSData),
            defaultGSData.maker,
            taker,
            taker,
            defaultGSData.takerToken,
            defaultGSData.takerTokenAmount,
            defaultGSData.makerToken,
            defaultGSData.makerTokenAmount,
            defaultGSData.salt
        );

        vm.startPrank(taker);
        genericSwap.executeSwap(defaultGSData, defaultTakerPermit);
        vm.stopPrank();
        vm.snapshotGasLastCall("GenericSwap", "executeSwap(): testLeaveOneWeiWithMultipleUsers(the first deposit)");

        // the second user: Alice
        // his makerTokenAmount is recalculate by `quoteExactInput() function base on the current state`
        // but there is no need to reduce it by 2 this time
        aliceGSData = defaultGSData;

        IUniswapV3Quoter v3Quoter = IUniswapV3Quoter(UNISWAP_V3_QUOTER_ADDRESS);
        bytes memory encodedPath = UniswapV3.encodePath(defaultPath, defaultV3Fees);
        uint256 aliceExpectedOut = v3Quoter.quoteExactInput(encodedPath, defaultInputAmount);

        aliceGSData.recipient = payable(alice);
        aliceGSData.makerTokenAmount = aliceExpectedOut;
        alicePermit = getTokenlonPermit2Data(alice, alicePrivateKey, aliceGSData.takerToken, address(genericSwap));

        Snapshot memory aliceTakerToken = BalanceSnapshot.take({ owner: alice, token: aliceGSData.takerToken });
        Snapshot memory aliceMakerToken = BalanceSnapshot.take({ owner: alice, token: aliceGSData.makerToken });

        vm.expectEmit(true, true, true, true);

        emit IGenericSwap.Swap(
            getGSDataHash(aliceGSData),
            aliceGSData.maker,
            alice,
            alice,
            aliceGSData.takerToken,
            aliceGSData.takerTokenAmount,
            aliceGSData.makerToken,
            aliceGSData.makerTokenAmount,
            aliceGSData.salt
        );

        vm.startPrank(alice);
        genericSwap.executeSwap(aliceGSData, strategyData, alicePermit);
        vm.stopPrank();
        vm.snapshotGasLastCall("GenericSwap", "executeSwap(): testLeaveOneWeiWithMultipleUsers(the second deposit)");

        takerTakerToken.assertChange(-int256(defaultGSData.takerTokenAmount));
        takerMakerToken.assertChange(int256(defaultGSData.makerTokenAmount));
        aliceTakerToken.assertChange(-int256(aliceGSData.takerTokenAmount));
        aliceMakerToken.assertChange(int256(aliceGSData.makerTokenAmount));
        gsTakerToken.assertChange(0);
        gsMakerToken.assertChange(1);
        makerTakerToken.assertChange(0);
        makerMakerToken.assertChange(1);
    }
}
