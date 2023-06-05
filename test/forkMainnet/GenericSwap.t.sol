// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";
import { Tokens } from "test/utils/Tokens.sol";
import { BalanceUtil } from "test/utils/BalanceUtil.sol";
import { getEIP712Hash } from "test/utils/Sig.sol";
import { BalanceSnapshot, Snapshot } from "test/utils/BalanceSnapshot.sol";
import { computeContractAddress } from "test/utils/Addresses.sol";
import { GenericSwap } from "contracts/GenericSwap.sol";
import { AllowanceTarget } from "contracts/AllowanceTarget.sol";
import { TokenCollector } from "contracts/abstracts/TokenCollector.sol";
import { UniswapStrategy } from "contracts/UniswapStrategy.sol";
import { Constant } from "contracts/libraries/Constant.sol";
import { Asset } from "contracts/libraries/Asset.sol";
import { GenericSwapData, getGSDataHash } from "contracts/libraries/GenericSwapData.sol";
import { IGenericSwap } from "contracts/interfaces/IGenericSwap.sol";
import { IUniswapRouterV2 } from "contracts/interfaces/IUniswapRouterV2.sol";
import { IStrategy } from "contracts/interfaces/IStrategy.sol";

contract MockStrategy is IStrategy, Test {
    using Asset for address;

    uint256 public outputAmount;

    function setOutputAmount(uint256 amount) external {
        outputAmount = amount;
    }

    function executeStrategy(
        address,
        address outputToken,
        uint256,
        bytes calldata
    ) external payable override {
        outputToken.transferTo(payable(msg.sender), outputAmount);
    }
}

contract GenericSwapTest is Test, Tokens, BalanceUtil {
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
    uint256 takerPrivateKey = uint256(1);
    address taker = vm.addr(takerPrivateKey);
    uint256 defaultExpiry = block.timestamp + 1;
    bytes defaultTakerPermit;
    UniswapStrategy uniswapStrategy;
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
        allowanceTarget = new AllowanceTarget(trusted);

        genericSwap = new GenericSwap(UNISWAP_PERMIT2_ADDRESS, address(allowanceTarget));
        uniswapStrategy = new UniswapStrategy(strategyAdmin, address(genericSwap), UNISWAP_V2_ADDRESS);
        mockStrategy = new MockStrategy();
        vm.prank(strategyAdmin);
        uniswapStrategy.approveToken(USDT_ADDRESS, UNISWAP_V2_ADDRESS, Constant.MAX_UINT);

        address[] memory defaultPath = new address[](2);
        defaultPath[0] = USDT_ADDRESS;
        defaultPath[1] = DAI_ADDRESS;
        bytes memory makerSpecificData = abi.encode(defaultExpiry, defaultPath);
        bytes memory swapData = abi.encode(UNISWAP_V2_ADDRESS, makerSpecificData);
        defaultTakerPermit = abi.encode(TokenCollector.Source.Token, bytes(""));

        deal(taker, 100 ether);
        setTokenBalanceAndApprove(taker, address(genericSwap), tokens, 100000);
        deal(address(mockStrategy), 100 ether);
        setTokenBalanceAndApprove(address(mockStrategy), address(genericSwap), tokens, 100000);

        defaultGSData = GenericSwapData({
            maker: payable(address(uniswapStrategy)),
            takerToken: USDT_ADDRESS,
            takerTokenAmount: 10 * 1e6,
            makerToken: DAI_ADDRESS,
            makerTokenAmount: 0, // to be filled later
            minMakerTokenAmount: 0, // to be filled later
            expiry: defaultExpiry,
            salt: 5678,
            recipient: payable(taker),
            strategyData: swapData
        });

        IUniswapRouterV2 router = IUniswapRouterV2(UNISWAP_V2_ADDRESS);
        uint256[] memory amounts = router.getAmountsOut(defaultGSData.takerTokenAmount, defaultPath);
        uint256 expectedOut = amounts[amounts.length - 1];
        // update defaultGSData
        defaultGSData.makerTokenAmount = expectedOut;
        defaultGSData.minMakerTokenAmount = (expectedOut * 95) / 100; // default 5% slippage tolerance
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
        mockStrategy.setOutputAmount(actualOutput);
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

        mockStrategy.setOutputAmount(gsData.makerTokenAmount);
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

        mockStrategy.setOutputAmount(gsData.makerTokenAmount);
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

        mockStrategy.setOutputAmount(gsData.minMakerTokenAmount - 1);
        vm.prank(taker);
        vm.expectRevert(IGenericSwap.InsufficientOutput.selector);
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

        bytes memory takerSig = _signGenericSwap(takerPrivateKey, defaultGSData);
        genericSwap.executeSwap(defaultGSData, defaultTakerPermit, taker, takerSig);

        takerTakerToken.assertChange(-int256(defaultGSData.takerTokenAmount));
        // the makerTokenAmount in the defaultGSData is the exact quote from strategy
        takerMakerToken.assertChange(int256(defaultGSData.makerTokenAmount));
    }

    function testSwapRelayedWithInvalidSig() public {
        uint256 randomPrivateKey = 5677;
        bytes memory randomSig = _signGenericSwap(randomPrivateKey, defaultGSData);

        vm.expectRevert(IGenericSwap.InvalidSignature.selector);
        // submit with user address as expected signer
        genericSwap.executeSwap(defaultGSData, defaultTakerPermit, taker, randomSig);
    }

    function testCannotReplayGenericSwapSig() public {
        bytes memory takerSig = _signGenericSwap(takerPrivateKey, defaultGSData);
        genericSwap.executeSwap(defaultGSData, defaultTakerPermit, taker, takerSig);

        vm.expectRevert(IGenericSwap.AlreadyFilled.selector);
        genericSwap.executeSwap(defaultGSData, defaultTakerPermit, taker, takerSig);
    }

    function _signGenericSwap(uint256 _privateKey, GenericSwapData memory _swapData) internal view returns (bytes memory sig) {
        bytes32 swapHash = getGSDataHash(_swapData);
        bytes32 EIP712SignDigest = getEIP712Hash(genericSwap.EIP712_DOMAIN_SEPARATOR(), swapHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, EIP712SignDigest);
        return abi.encodePacked(r, s, v);
    }
}
