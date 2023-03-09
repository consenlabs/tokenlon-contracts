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
import { GeneralOrder } from "contracts/interfaces/IGeneralOrder.sol";

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
    uint256 takerPrivateKey = uint256(1);
    address taker = vm.addr(takerPrivateKey);
    uint256 defaultExpiry = block.timestamp + 1;
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
        bytes memory makerSpecificData = abi.encode(defaultExpiry, defaultPath);
        bytes memory swapData = abi.encode(UNISWAP_V2_ADDRESS, makerSpecificData);
        bytes memory defaultInputPermit = abi.encode(TokenCollector.Source.Token, bytes(""));

        deal(taker, 100 ether);
        setEOABalanceAndApprove(taker, address(genericSwap), tokens, 100000);

        gsData = IGenericSwap.GenericSwapData({
            order: GeneralOrder({
                maker: payable(address(uniswapStrategy)),
                taker: taker,
                inputToken: USDT_ADDRESS,
                inputTokenPermit: defaultInputPermit,
                outputToken: CRV_ADDRESS,
                outputTokenPermit: bytes(""),
                inputAmount: 10 * 1e6,
                outputAmount: 0, // to be filled later
                minOutputAmount: 0, // to be filled later
                recipient: payable(taker),
                expiry: defaultExpiry,
                salt: defaultSalt
            }),
            strategyData: swapData
        });

        IUniswapRouterV2 router = IUniswapRouterV2(UNISWAP_V2_ADDRESS);
        uint256[] memory amounts = router.getAmountsOut(gsData.order.inputAmount, defaultPath);
        uint256 expectedOut = amounts[amounts.length - 1];
        // update order of gsData
        gsData.order.outputAmount = expectedOut;
        gsData.order.minOutputAmount = (expectedOut * 95) / 100; // default 5% slippage tolerance
    }

    function testGenericSwap() public {
        vm.expectEmit(true, true, true, true);
        emit Swap(taker, gsData.order.inputToken, gsData.order.outputToken, gsData.order.inputAmount, gsData.order.outputAmount);

        vm.prank(taker);
        genericSwap.executeSwap(gsData);
    }

    function testGenericSwapWithInvalidETHInput() public {
        // change input token as ETH and update amount
        gsData.order.inputToken = Constant.ETH_ADDRESS;
        gsData.order.inputAmount = 1 ether;

        vm.prank(taker);
        vm.expectRevert(IGenericSwap.InvalidMsgValue.selector);
        genericSwap.executeSwap{ value: 2 * gsData.order.inputAmount }(gsData);
    }

    function testGenericSwapInsufficientOutput() public {
        // set mockStrategy contract that returns nothing
        mockStrategy.setReturnToken(false);

        // set mockStrategy as maker
        gsData.order.maker = payable(address(mockStrategy));

        vm.prank(taker);
        vm.expectRevert(IGenericSwap.InsufficientOutput.selector);
        genericSwap.executeSwap(gsData);
    }

    function testGenericSwapRelayed() public {
        bytes memory takerSig = _signGenericSwap(takerPrivateKey, gsData);
        genericSwap.executeSwap(gsData, taker, takerSig);
    }

    function testSwapRelayedWithInvalidSig() public {
        uint256 randomPrivateKey = 5677;
        bytes memory randomSig = _signGenericSwap(randomPrivateKey, gsData);

        vm.expectRevert(IGenericSwap.InvalidSignature.selector);
        // submit with user address as expected signer
        genericSwap.executeSwap(gsData, taker, randomSig);
    }

    function testCannotReplayGenericSwapSig() public {
        bytes memory takerSig = _signGenericSwap(takerPrivateKey, gsData);
        genericSwap.executeSwap(gsData, taker, takerSig);

        vm.expectRevert(IGenericSwap.AlreadyFilled.selector);
        genericSwap.executeSwap(gsData, taker, takerSig);
    }

    function _signGenericSwap(uint256 _privateKey, IGenericSwap.GenericSwapData memory _swapData) internal view returns (bytes memory sig) {
        bytes32 swapHash = _getGSDataHash(_swapData);
        bytes32 EIP712SignDigest = getEIP712Hash(genericSwap.EIP712_DOMAIN_SEPARATOR(), swapHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, EIP712SignDigest);
        return abi.encodePacked(r, s, v);
    }

    function _getGSDataHash(IGenericSwap.GenericSwapData memory _gsData) private view returns (bytes32) {
        // FIXME to confirm with ethers.js
        return keccak256(abi.encode(genericSwap.GS_DATA_TYPEHASH(), _gsData.order, _gsData.strategyData));
    }
}
