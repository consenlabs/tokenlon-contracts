// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";
import { Tokens } from "test/utils/Tokens.sol";
import { BalanceUtil } from "test/utils/BalanceUtil.sol";
import { getEIP712Hash } from "test/utils/Sig.sol";
import { GenericSwap } from "contracts/GenericSwap.sol";
import { TokenCollector } from "contracts/abstracts/TokenCollector.sol";
import { UniswapStrategy } from "contracts/UniswapStrategy.sol";
import { Constant } from "contracts/libraries/Constant.sol";
import { IGenericSwap } from "contracts/interfaces/IGenericSwap.sol";
import { IUniswapRouterV2 } from "contracts/interfaces/IUniswapRouterV2.sol";
import { IStrategy } from "contracts/interfaces/IStrategy.sol";

contract MockStrategy is IStrategy, Test {
    bool returnToken = true;

    function setReturnToken(bool enable) external {
        returnToken = enable;
    }

    function executeStrategy(
        address,
        address outputToken,
        uint256,
        bytes calldata
    ) external payable override {
        if (returnToken) {
            deal(outputToken, msg.sender, 100000 ether, false);
        }
        return;
    }
}

contract GenericSwapTest is Test, Tokens, BalanceUtil {
    event Swap(address indexed maker, address indexed inputToken, address indexed outputToken, uint256 inputAmount, uint256 outputAmount);

    address strategyAdmin = makeAddr("strategyAdmin");
    address user = makeAddr("user");
    uint256 takerPrivateKey = uint256(1);
    address taker = vm.addr(takerPrivateKey);
    uint256 defaultDeadline = block.timestamp + 1;
    uint256 defaultSalt = 1234;
    UniswapStrategy uniswapStrategy;
    GenericSwap genericSwap;
    IGenericSwap.GenericSwapData gsData;
    MockStrategy mockStrategy;

    function setUp() public {
        genericSwap = new GenericSwap(UNISWAP_PERMIT2_ADDRESS);
        uniswapStrategy = new UniswapStrategy(strategyAdmin, address(genericSwap), UNISWAP_V2_ADDRESS);
        mockStrategy = new MockStrategy();
        vm.prank(strategyAdmin);
        uniswapStrategy.approveToken(USDT_ADDRESS, UNISWAP_V2_ADDRESS, Constant.MAX_UINT);

        address[] memory defaultPath = new address[](2);
        defaultPath[0] = USDT_ADDRESS;
        defaultPath[1] = CRV_ADDRESS;
        bytes memory makerSpecificData = abi.encode(defaultDeadline, defaultPath);
        bytes memory swapData = abi.encode(UNISWAP_V2_ADDRESS, makerSpecificData);
        bytes memory empty;
        bytes memory defaultInputData = abi.encode(TokenCollector.Source.Token, empty);

        deal(user, 100 ether);
        setEOABalanceAndApprove(user, address(genericSwap), tokens, 100000);
        deal(taker, 100 ether);
        setEOABalanceAndApprove(taker, address(genericSwap), tokens, 100000);

        gsData = IGenericSwap.GenericSwapData({
            inputToken: USDT_ADDRESS,
            outputToken: CRV_ADDRESS,
            inputAmount: 10 * 1e6,
            minOutputAmount: 0, // to be filled
            receiver: payable(user),
            deadline: defaultDeadline,
            strategyData: swapData,
            inputData: defaultInputData
        });

        IUniswapRouterV2 router = IUniswapRouterV2(UNISWAP_V2_ADDRESS);
        uint256[] memory amounts = router.getAmountsOut(gsData.inputAmount, defaultPath);
        uint256 expectedOut = amounts[amounts.length - 1];
        // update minOutputAmount of gsData
        gsData.minOutputAmount = expectedOut;
    }

    function testGenericSwap() public {
        vm.expectEmit(true, true, true, true);
        emit Swap(user, gsData.inputToken, gsData.outputToken, gsData.inputAmount, gsData.minOutputAmount);

        vm.prank(user);
        genericSwap.executeSwap(IStrategy(uniswapStrategy), gsData);
    }

    function testGenericSwapWithInvalidETHInput() public {
        // change input token as ETH and update amount
        gsData.inputToken = Constant.ETH_ADDRESS;
        gsData.inputAmount = 1 ether;

        vm.prank(user);
        vm.expectRevert(IGenericSwap.InvalidMsgValue.selector);
        genericSwap.executeSwap{ value: 2 * gsData.inputAmount }(IStrategy(uniswapStrategy), gsData);
    }

    function testGenericSwapInsufficientOutput() public {
        // set mockStrategy contract that returns nothing
        mockStrategy.setReturnToken(false);

        vm.prank(user);
        vm.expectRevert(IGenericSwap.InsufficientOutput.selector);
        genericSwap.executeSwap(IStrategy(mockStrategy), gsData);
    }

    function testGenericSwapRelayed() public {
        bytes memory takerSig = _signGenericSwap(takerPrivateKey, gsData, defaultSalt);
        genericSwap.executeSwap(IStrategy(uniswapStrategy), gsData, taker, defaultSalt, takerSig);
    }

    function testSwapRelayedWithInvalidSig() public {
        bytes memory takerSig = _signGenericSwap(takerPrivateKey, gsData, defaultSalt);

        vm.expectRevert(IGenericSwap.InvalidSignature.selector);
        // submit with user address as expected signer
        genericSwap.executeSwap(IStrategy(uniswapStrategy), gsData, user, defaultSalt, takerSig);
    }

    function testCannotReplayGenericSwapSig() public {
        bytes memory takerSig = _signGenericSwap(takerPrivateKey, gsData, defaultSalt);
        genericSwap.executeSwap(IStrategy(uniswapStrategy), gsData, taker, defaultSalt, takerSig);

        vm.expectRevert("already filled");
        genericSwap.executeSwap(IStrategy(uniswapStrategy), gsData, taker, defaultSalt, takerSig);
    }

    function _signGenericSwap(
        uint256 _privateKey,
        IGenericSwap.GenericSwapData memory _swapData,
        uint256 _salt
    ) internal view returns (bytes memory sig) {
        bytes32 swapHash = _getGSDataHash(_swapData, _salt);
        bytes32 EIP712SignDigest = getEIP712Hash(genericSwap.EIP712_DOMAIN_SEPARATOR(), swapHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, EIP712SignDigest);
        return abi.encodePacked(r, s, v);
    }

    function _getGSDataHash(IGenericSwap.GenericSwapData memory _gsData, uint256 _salt) private view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    genericSwap.GS_DATA_TYPEHASH(),
                    _gsData.inputToken,
                    _gsData.outputToken,
                    _gsData.inputAmount,
                    _gsData.minOutputAmount,
                    _gsData.receiver,
                    _gsData.deadline,
                    _gsData.inputData,
                    _gsData.strategyData,
                    _salt
                )
            );
    }
}
