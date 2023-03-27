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
import { Offer, getOfferHash } from "contracts/libraries/Offer.sol";
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
    event Swap(
        address indexed maker,
        address indexed taker,
        address indexed recipient,
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
        defaultTakerPermit = abi.encode(TokenCollector.Source.Token, bytes(""));

        deal(taker, 100 ether);
        setEOABalanceAndApprove(taker, address(genericSwap), tokens, 100000);

        gsData = IGenericSwap.GenericSwapData({
            offer: Offer({
                taker: taker,
                maker: payable(address(uniswapStrategy)),
                takerToken: USDT_ADDRESS,
                takerTokenAmount: 10 * 1e6,
                makerToken: CRV_ADDRESS,
                makerTokenAmount: 0, // to be filled later
                minMakerTokenAmount: 0, // to be filled later
                expiry: 0, // not used in GS
                salt: 0 // not used in GS
            }),
            recipient: payable(taker),
            strategyData: swapData
        });

        IUniswapRouterV2 router = IUniswapRouterV2(UNISWAP_V2_ADDRESS);
        uint256[] memory amounts = router.getAmountsOut(gsData.offer.takerTokenAmount, defaultPath);
        uint256 expectedOut = amounts[amounts.length - 1];
        // update offer of gsData
        gsData.offer.makerTokenAmount = expectedOut;
        gsData.offer.minMakerTokenAmount = (expectedOut * 95) / 100; // default 5% slippage tolerance
    }

    function testGenericSwap() public {
        vm.expectEmit(true, true, true, true);
        emit Swap(
            gsData.offer.maker,
            gsData.offer.taker,
            gsData.offer.taker,
            gsData.offer.takerToken,
            gsData.offer.takerTokenAmount,
            gsData.offer.makerToken,
            gsData.offer.makerTokenAmount
        );

        vm.prank(taker);
        genericSwap.executeSwap(gsData, defaultTakerPermit);
    }

    function testGenericSwapWithInvalidETHInput() public {
        // change input token as ETH and update amount
        gsData.offer.takerToken = Constant.ETH_ADDRESS;
        gsData.offer.takerTokenAmount = 1 ether;

        vm.prank(taker);
        vm.expectRevert(IGenericSwap.InvalidMsgValue.selector);
        genericSwap.executeSwap{ value: 2 * gsData.offer.takerTokenAmount }(gsData, defaultTakerPermit);
    }

    function testGenericSwapInsufficientOutput() public {
        // set mockStrategy contract that returns nothing
        mockStrategy.setReturnToken(false);

        // set mockStrategy as maker
        gsData.offer.maker = payable(address(mockStrategy));

        vm.prank(taker);
        vm.expectRevert(IGenericSwap.InsufficientOutput.selector);
        genericSwap.executeSwap(gsData, defaultTakerPermit);
    }

    function testGenericSwapRelayed() public {
        bytes memory takerSig = _signGenericSwap(takerPrivateKey, gsData);
        genericSwap.executeSwap(gsData, defaultTakerPermit, taker, takerSig);
    }

    function testSwapRelayedWithInvalidSig() public {
        uint256 randomPrivateKey = 5677;
        bytes memory randomSig = _signGenericSwap(randomPrivateKey, gsData);

        vm.expectRevert(IGenericSwap.InvalidSignature.selector);
        // submit with user address as expected signer
        genericSwap.executeSwap(gsData, defaultTakerPermit, taker, randomSig);
    }

    function testCannotReplayGenericSwapSig() public {
        bytes memory takerSig = _signGenericSwap(takerPrivateKey, gsData);
        genericSwap.executeSwap(gsData, defaultTakerPermit, taker, takerSig);

        vm.expectRevert(IGenericSwap.AlreadyFilled.selector);
        genericSwap.executeSwap(gsData, defaultTakerPermit, taker, takerSig);
    }

    function _signGenericSwap(uint256 _privateKey, IGenericSwap.GenericSwapData memory _swapData) internal view returns (bytes memory sig) {
        bytes32 swapHash = _getGSDataHash(_swapData);
        bytes32 EIP712SignDigest = getEIP712Hash(genericSwap.EIP712_DOMAIN_SEPARATOR(), swapHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, EIP712SignDigest);
        return abi.encodePacked(r, s, v);
    }

    function _getGSDataHash(IGenericSwap.GenericSwapData memory _gsData) private view returns (bytes32) {
        bytes32 offerHash = getOfferHash(_gsData.offer);
        return keccak256(abi.encode(genericSwap.GS_DATA_TYPEHASH(), offerHash, _gsData.recipient, _gsData.strategyData));
    }
}
