// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import { ECDSA } from "@openzeppelin/contracts/cryptography/ECDSA.sol";

import { StrategySharedSetup } from "test/utils/StrategySharedSetup.sol";
import { BalanceSnapshot } from "test/utils/BalanceSnapshot.sol";
import { getEIP712Hash } from "test/utils/Sig.sol";
import { Permit2Helper } from "test/utils/Permit2Helper.sol";
import { RFQv2 } from "contracts/RFQv2.sol";
import { MarketMakerProxy } from "contracts/MarketMakerProxy.sol";
import { SignatureValidator } from "contracts/utils/SignatureValidator.sol";
import { TokenCollector } from "contracts/utils/TokenCollector.sol";
import { Offer, getOfferHash } from "contracts/utils/Offer.sol";
import { RFQOrder, getRFQOrderHash } from "contracts/utils/RFQOrder.sol";
import { LibConstant } from "contracts/utils/LibConstant.sol";
import { IUniswapPermit2 } from "contracts/interfaces/IUniswapPermit2.sol";
import { IWETH } from "contracts/interfaces/IWETH.sol";

import { AMMWrapperWithPath } from "contracts/AMMWrapperWithPath.sol";
import { RFQ } from "contracts/RFQ.sol";
import { AMMLibEIP712 } from "contracts/utils/AMMLibEIP712.sol";
import { RFQLibEIP712 } from "contracts/utils/RFQLibEIP712.sol";
import { _encodeUniswapSinglePoolData } from "test/utils/AMMUtil.sol";
import { LimitOrder } from "contracts/LimitOrder.sol";
import { ILimitOrder } from "contracts/interfaces/ILimitOrder.sol";
import { LimitOrderLibEIP712 } from "contracts/utils/LimitOrderLibEIP712.sol";
import { IZxExchange, zxOrder } from "test/utils/zxOrder.sol";

import { console as fconsole } from "forge-std/console.sol";

interface IPMM {
    function fill(
        uint256 userSalt,
        bytes memory data,
        bytes memory userSignature
    ) external payable returns (uint256);
}

contract RFQTest is StrategySharedSetup, Permit2Helper {
    using BalanceSnapshot for BalanceSnapshot.Snapshot;

    event FilledRFQ(
        bytes32 indexed offerHash,
        address indexed user,
        address indexed maker,
        address takerToken,
        uint256 takerTokenAmount,
        address makerToken,
        uint256 makerTokenAmount,
        address recipient,
        uint256 settleAmount,
        uint256 feeFactor
    );

    address rfqOwner = makeAddr("rfqOwner");
    uint256 makerPrivateKey = uint256(2);
    address payable maker = payable(vm.addr(makerPrivateKey));
    uint256 takerPrivateKey = uint256(1);
    address taker = vm.addr(takerPrivateKey);
    address payable recipient;
    address payable feeCollector = payable(makeAddr("feeCollector"));
    uint256 defaultExpiry;
    uint256 defaultSalt = 1234;
    uint256 defaultFeeFactor = 100;
    bytes defaultPermit;
    bytes defaultMakerSig;
    bytes defaultTakerSig;
    Offer defaultOffer;
    RFQOrder defaultOrder;
    MarketMakerProxy marketMakerProxy;
    RFQv2 rfq;
    RFQ rfqv1;
    AMMWrapperWithPath ammWrapperWithPath;
    LimitOrder limitOrder;
    IZxExchange zxExchange;
    IPMM pmm;

    function setUp() public {
        // Setup
        setUpSystemContracts();

        defaultExpiry = block.timestamp + 1 days;

        // Update token list (keep tokens used in this test only)
        tokens = [weth, usdt, lon, usdc, dai, wbtc];

        recipient = payable(makeAddr("recipient"));

        marketMakerProxy = new MarketMakerProxy(maker, maker, IWETH(address(weth)));

        deal(maker, 100 ether);
        setEOABalanceAndApprove(maker, tokens, 100000);
        deal(address(marketMakerProxy), 100 ether);
        setWalletContractBalanceAndApprove({ owner: maker, walletContract: address(marketMakerProxy), tokens: tokens, amount: 100000 });
        deal(taker, 100 ether);
        setEOABalanceAndApprove(taker, tokens, 100000);
        defaultPermit = abi.encodePacked(TokenCollector.Source.TokenlonSpender);

        defaultOffer = Offer({
            taker: taker,
            maker: maker,
            takerToken: address(usdt),
            takerTokenAmount: 10 * 1e6,
            makerToken: address(lon),
            makerTokenAmount: 10,
            feeFactor: defaultFeeFactor,
            expiry: defaultExpiry,
            salt: defaultSalt
        });

        defaultMakerSig = _signOffer(makerPrivateKey, defaultOffer, SignatureValidator.SignatureType.EIP712);

        defaultOrder = RFQOrder({ offer: defaultOffer, recipient: payable(recipient) });
        defaultTakerSig = _signRFQOrder(takerPrivateKey, defaultOrder, SignatureValidator.SignatureType.EIP712);

        vm.label(taker, "taker");
        vm.label(maker, "maker");
        vm.label(address(rfq), "rfq");
    }

    function _deployStrategyAndUpgrade() internal override returns (address) {
        rfq = RFQv2(payable(_readDeployedAddr("$.RFQv2_ADDRESS")));
        rfqOwner = rfq.owner();
        feeCollector = rfq.feeCollector();

        return address(rfq);
    }

    function _setupDeployedStrategy() internal override {
        // deploy RFQv2
        _deployStrategyAndUpgrade();

        ammWrapperWithPath = AMMWrapperWithPath(0x4a14347083B80E5216cA31350a2D21702aC3650d);
        rfqv1 = RFQ(0xfD6C2d2499b1331101726A8AC68CCc9Da3fAB54F);
        limitOrder = LimitOrder(0x623a6B3424f3d5E2eC677D5bb92BA12A9dc4f71A);

        pmm = IPMM(0x8D90113A1e286a5aB3e496fbD1853F265e5913c6);
        zxExchange = IZxExchange(0x080bf510FCbF18b91105470639e9561022937712);
    }

    function testCannotUpgradeSpenderByNotOwner() public {
        address newOwner = makeAddr("newOwner");
        vm.expectRevert("not owner");
        vm.prank(newOwner);
        rfq.upgradeSpender(newOwner);
    }

    function testCannotUpgradeSpenderToZeroAddress() public {
        vm.expectRevert("Strategy: spender can not be zero address");
        vm.prank(rfqOwner, rfqOwner);
        rfq.upgradeSpender(address(0));
    }

    function testUpgradeSpender() public {
        address newOwner = makeAddr("newOwner");
        vm.prank(rfqOwner, rfqOwner);
        rfq.upgradeSpender(newOwner);
        assertEq(address(rfq.spender()), newOwner);
    }

    function testCannotSetAllowanceCloseAllowanceByNotOwner() public {
        address[] memory allowanceTokenList = new address[](1);
        allowanceTokenList[0] = address(usdt);

        vm.startPrank(makeAddr("random"));
        vm.expectRevert("not owner");
        rfq.setAllowance(allowanceTokenList, address(this));
        vm.expectRevert("not owner");
        rfq.closeAllowance(allowanceTokenList, address(this));
        vm.stopPrank();
    }

    function testSetAllowanceCloseAllowance() public {
        address[] memory allowanceTokenList = new address[](1);
        allowanceTokenList[0] = address(usdt);

        vm.prank(rfqOwner, rfqOwner);
        assertEq(usdt.allowance(address(rfq), address(this)), uint256(0));

        vm.prank(rfqOwner, rfqOwner);
        rfq.setAllowance(allowanceTokenList, address(this));
        assertEq(usdt.allowance(address(rfq), address(this)), type(uint256).max);

        vm.prank(rfqOwner, rfqOwner);
        rfq.closeAllowance(allowanceTokenList, address(this));
        assertEq(usdt.allowance(address(rfq), address(this)), uint256(0));
    }

    function testCannotDepositETHByNotOwner() public {
        vm.expectRevert("not owner");
        vm.prank(makeAddr("random"));
        rfq.depositETH();
    }

    function testDepositETH() public {
        deal(address(rfq), 1 ether);
        assertEq(address(rfq).balance, 1 ether);
        vm.prank(rfqOwner, rfqOwner);
        rfq.depositETH();
        assertEq(address(rfq).balance, uint256(0));
        assertEq(weth.balanceOf(address(rfq)), 1 ether);
    }

    function testCannotSetFeeCollectorByNotOwner() public {
        address newFeeCollector = makeAddr("newFeeCollector");
        vm.prank(newFeeCollector);
        vm.expectRevert("not owner");
        rfq.setFeeCollector(payable(newFeeCollector));
    }

    function testSetFeeCollector() public {
        address newFeeCollector = makeAddr("newFeeCollector");
        vm.prank(rfqOwner, rfqOwner);
        rfq.setFeeCollector(payable(newFeeCollector));
        assertEq(rfq.feeCollector(), newFeeCollector);
    }

    function testFillRFQ() public {
        BalanceSnapshot.Snapshot memory takerTakerToken = BalanceSnapshot.take({ owner: defaultOffer.taker, token: defaultOffer.takerToken });
        BalanceSnapshot.Snapshot memory takerMakerToken = BalanceSnapshot.take({ owner: defaultOffer.taker, token: defaultOffer.makerToken });
        BalanceSnapshot.Snapshot memory makerTakerToken = BalanceSnapshot.take({ owner: defaultOffer.maker, token: defaultOffer.takerToken });
        BalanceSnapshot.Snapshot memory makerMakerToken = BalanceSnapshot.take({ owner: defaultOffer.maker, token: defaultOffer.makerToken });
        BalanceSnapshot.Snapshot memory recTakerToken = BalanceSnapshot.take({ owner: recipient, token: defaultOffer.takerToken });
        BalanceSnapshot.Snapshot memory recMakerToken = BalanceSnapshot.take({ owner: recipient, token: defaultOffer.makerToken });
        BalanceSnapshot.Snapshot memory feeCollectorMakerToken = BalanceSnapshot.take({ owner: feeCollector, token: defaultOffer.makerToken });

        uint256 fee = (defaultOffer.makerTokenAmount * defaultOffer.feeFactor) / LibConstant.BPS_MAX;
        uint256 amountAfterFee = defaultOffer.makerTokenAmount - fee;
        vm.expectEmit(true, true, true, true);
        emit FilledRFQ(
            getOfferHash(defaultOffer),
            defaultOffer.taker,
            defaultOffer.maker,
            defaultOffer.takerToken,
            defaultOffer.takerTokenAmount,
            defaultOffer.makerToken,
            defaultOffer.makerTokenAmount,
            defaultOrder.recipient,
            amountAfterFee,
            defaultOffer.feeFactor
        );

        bytes memory payload = _genFillRFQPayload(defaultOrder, defaultMakerSig, defaultPermit, defaultTakerSig, defaultPermit);
        vm.prank(defaultOffer.taker, defaultOffer.taker);
        userProxy.toRFQv2(payload);

        takerTakerToken.assertChange(-int256(defaultOffer.takerTokenAmount));
        takerMakerToken.assertChange(int256(0));
        makerTakerToken.assertChange(int256(defaultOffer.takerTokenAmount));
        makerMakerToken.assertChange(-int256(defaultOffer.makerTokenAmount));
        recTakerToken.assertChange(int256(0));
        // recipient gets less than original makerTokenAmount because of the fee for relayer
        recMakerToken.assertChange(int256(amountAfterFee));
        feeCollectorMakerToken.assertChange(int256(fee));
    }

    function testFillRFQWithContractMakerAndDirectApprove() public {
        Offer memory offer = defaultOffer;
        offer.maker = address(marketMakerProxy);
        offer.feeFactor = 0;
        RFQOrder memory rfqOrder = RFQOrder({ offer: offer, recipient: payable(recipient) });

        bytes memory makerSig = _signOffer(makerPrivateKey, offer, SignatureValidator.SignatureType.WalletBytes32);
        bytes memory takerSig = _signRFQOrder(takerPrivateKey, rfqOrder, SignatureValidator.SignatureType.EIP712);

        address[] memory tokenAddresses = new address[](1);
        tokenAddresses[0] = offer.makerToken;
        vm.startPrank(maker);
        marketMakerProxy.setAllowance(tokenAddresses, address(rfq));
        marketMakerProxy.closeAllowance(tokenAddresses, address(allowanceTarget));
        vm.stopPrank();
        bytes memory makerPermit = abi.encodePacked(TokenCollector.Source.Token);

        BalanceSnapshot.Snapshot memory takerTakerToken = BalanceSnapshot.take({ owner: offer.taker, token: offer.takerToken });
        BalanceSnapshot.Snapshot memory takerMakerToken = BalanceSnapshot.take({ owner: offer.taker, token: offer.makerToken });
        BalanceSnapshot.Snapshot memory makerTakerToken = BalanceSnapshot.take({ owner: offer.maker, token: offer.takerToken });
        BalanceSnapshot.Snapshot memory makerMakerToken = BalanceSnapshot.take({ owner: offer.maker, token: offer.makerToken });
        BalanceSnapshot.Snapshot memory recTakerToken = BalanceSnapshot.take({ owner: recipient, token: offer.takerToken });
        BalanceSnapshot.Snapshot memory recMakerToken = BalanceSnapshot.take({ owner: recipient, token: offer.makerToken });

        bytes memory payload = _genFillRFQPayload(rfqOrder, makerSig, makerPermit, takerSig, defaultPermit);
        vm.prank(defaultOffer.taker, defaultOffer.taker);
        userProxy.toRFQv2(payload);

        takerTakerToken.assertChange(-int256(offer.takerTokenAmount));
        takerMakerToken.assertChange(int256(0));
        makerTakerToken.assertChange(int256(offer.takerTokenAmount));
        makerMakerToken.assertChange(-int256(offer.makerTokenAmount));
        recTakerToken.assertChange(int256(0));
        recMakerToken.assertChange(int256(offer.makerTokenAmount));
    }

    function testFillRFQWithRawETH() public {
        // case : taker token is ETH
        Offer memory offer = defaultOffer;
        offer.takerToken = LibConstant.ZERO_ADDRESS;
        offer.takerTokenAmount = 1 ether;
        offer.feeFactor = 0;
        RFQOrder memory rfqOrder = RFQOrder({ offer: offer, recipient: payable(recipient) });

        bytes memory makerSig = _signOffer(makerPrivateKey, offer, SignatureValidator.SignatureType.EIP712);
        bytes memory takerSig = _signRFQOrder(takerPrivateKey, rfqOrder, SignatureValidator.SignatureType.EIP712);

        BalanceSnapshot.Snapshot memory takerTakerToken = BalanceSnapshot.take({ owner: offer.taker, token: offer.takerToken });
        BalanceSnapshot.Snapshot memory takerMakerToken = BalanceSnapshot.take({ owner: offer.taker, token: offer.makerToken });
        // maker should receive WETH instead
        BalanceSnapshot.Snapshot memory makerTakerToken = BalanceSnapshot.take({ owner: offer.maker, token: address(weth) });
        BalanceSnapshot.Snapshot memory makerMakerToken = BalanceSnapshot.take({ owner: offer.maker, token: offer.makerToken });
        BalanceSnapshot.Snapshot memory recTakerToken = BalanceSnapshot.take({ owner: recipient, token: offer.takerToken });
        BalanceSnapshot.Snapshot memory recMakerToken = BalanceSnapshot.take({ owner: recipient, token: offer.makerToken });

        bytes memory payload = _genFillRFQPayload(rfqOrder, makerSig, defaultPermit, takerSig, defaultPermit);
        vm.prank(offer.taker, offer.taker);
        userProxy.toRFQv2{ value: offer.takerTokenAmount }(payload);

        takerTakerToken.assertChange(-int256(offer.takerTokenAmount));
        takerMakerToken.assertChange(int256(0));
        makerTakerToken.assertChange(int256(offer.takerTokenAmount));
        makerMakerToken.assertChange(-int256(offer.makerTokenAmount));
        recTakerToken.assertChange(int256(0));
        recMakerToken.assertChange(int256(offer.makerTokenAmount));
    }

    function testFillRFQTakerGetRawETH() public {
        // case : maker token is WETH
        Offer memory offer = defaultOffer;
        offer.makerToken = address(weth);
        offer.makerTokenAmount = 1 ether;
        offer.feeFactor = 0;
        RFQOrder memory rfqOrder = RFQOrder({ offer: offer, recipient: payable(recipient) });

        bytes memory makerSig = _signOffer(makerPrivateKey, offer, SignatureValidator.SignatureType.EIP712);
        bytes memory takerSig = _signRFQOrder(takerPrivateKey, rfqOrder, SignatureValidator.SignatureType.EIP712);

        BalanceSnapshot.Snapshot memory takerTakerToken = BalanceSnapshot.take({ owner: offer.taker, token: offer.takerToken });
        BalanceSnapshot.Snapshot memory takerMakerToken = BalanceSnapshot.take({ owner: offer.taker, token: offer.makerToken });
        BalanceSnapshot.Snapshot memory makerTakerToken = BalanceSnapshot.take({ owner: offer.maker, token: offer.takerToken });
        BalanceSnapshot.Snapshot memory makerMakerToken = BalanceSnapshot.take({ owner: offer.maker, token: offer.makerToken });
        // recipient should receive raw ETH
        BalanceSnapshot.Snapshot memory recTakerToken = BalanceSnapshot.take({ owner: recipient, token: offer.takerToken });
        BalanceSnapshot.Snapshot memory recMakerToken = BalanceSnapshot.take({ owner: recipient, token: LibConstant.ETH_ADDRESS });

        bytes memory payload = _genFillRFQPayload(rfqOrder, makerSig, defaultPermit, takerSig, defaultPermit);
        vm.prank(offer.taker, offer.taker);
        userProxy.toRFQv2(payload);

        takerTakerToken.assertChange(-int256(offer.takerTokenAmount));
        takerMakerToken.assertChange(int256(0));
        makerTakerToken.assertChange(int256(offer.takerTokenAmount));
        makerMakerToken.assertChange(-int256(offer.makerTokenAmount));
        recTakerToken.assertChange(int256(0));
        recMakerToken.assertChange(int256(offer.makerTokenAmount));
    }

    function testFillRFQWithWETH() public {
        // case : taker token is WETH
        Offer memory offer = defaultOffer;
        offer.takerToken = address(weth);
        offer.takerTokenAmount = 1 ether;
        offer.feeFactor = 0;
        RFQOrder memory rfqOrder = RFQOrder({ offer: offer, recipient: payable(recipient) });

        bytes memory makerSig = _signOffer(makerPrivateKey, offer, SignatureValidator.SignatureType.EIP712);
        bytes memory takerSig = _signRFQOrder(takerPrivateKey, rfqOrder, SignatureValidator.SignatureType.EIP712);

        BalanceSnapshot.Snapshot memory takerTakerToken = BalanceSnapshot.take({ owner: offer.taker, token: offer.takerToken });
        BalanceSnapshot.Snapshot memory takerMakerToken = BalanceSnapshot.take({ owner: offer.taker, token: offer.makerToken });
        BalanceSnapshot.Snapshot memory makerTakerToken = BalanceSnapshot.take({ owner: offer.maker, token: offer.takerToken });
        BalanceSnapshot.Snapshot memory makerMakerToken = BalanceSnapshot.take({ owner: offer.maker, token: offer.makerToken });
        BalanceSnapshot.Snapshot memory recTakerToken = BalanceSnapshot.take({ owner: recipient, token: offer.takerToken });
        BalanceSnapshot.Snapshot memory recMakerToken = BalanceSnapshot.take({ owner: recipient, token: offer.makerToken });

        bytes memory payload = _genFillRFQPayload(rfqOrder, makerSig, defaultPermit, takerSig, defaultPermit);
        vm.prank(offer.taker, offer.taker);
        userProxy.toRFQv2(payload);

        takerTakerToken.assertChange(-int256(offer.takerTokenAmount));
        takerMakerToken.assertChange(int256(0));
        makerTakerToken.assertChange(int256(offer.takerTokenAmount));
        makerMakerToken.assertChange(-int256(offer.makerTokenAmount));
        recTakerToken.assertChange(int256(0));
        recMakerToken.assertChange(int256(offer.makerTokenAmount));
    }

    function testFillRFQWithDirectlyApprove() public {
        // spender deauthorize RFQv2 to disable other allowance
        address[] memory authListAddress = new address[](1);
        authListAddress[0] = address(rfq);
        vm.prank(tokenlonOperator);
        spender.deauthorize(authListAddress);

        // maker approve tokens to RFQv2 contract directly
        approveERC20(tokens, maker, address(rfq));
        // taker approve tokens to RFQv2 contract directly
        approveERC20(tokens, taker, address(rfq));
        bytes memory tokenPermit = abi.encodePacked(TokenCollector.Source.Token);

        bytes memory payload = _genFillRFQPayload(defaultOrder, defaultMakerSig, tokenPermit, defaultTakerSig, tokenPermit);
        vm.prank(defaultOffer.taker, defaultOffer.taker);
        userProxy.toRFQv2(payload);
    }

    function testFillRFQWithPermit2() public {
        // maker and taker approve tokens to Permit2
        approveERC20(tokens, taker, address(permit2));
        approveERC20(tokens, maker, address(permit2));

        IUniswapPermit2.PermitTransferFrom memory takerPermit = IUniswapPermit2.PermitTransferFrom({
            permitted: IUniswapPermit2.TokenPermissions({ token: defaultOffer.takerToken, amount: defaultOffer.takerTokenAmount }),
            nonce: 0,
            deadline: block.timestamp + 1 days
        });
        bytes memory takerPermitSig = signPermitTransferFrom(takerPrivateKey, takerPermit, address(rfq));
        bytes memory takerPermitData = encodeSignatureTransfer(takerPermit, takerPermitSig);

        IUniswapPermit2.PermitTransferFrom memory makerPermit = IUniswapPermit2.PermitTransferFrom({
            permitted: IUniswapPermit2.TokenPermissions({ token: defaultOffer.makerToken, amount: defaultOffer.makerTokenAmount }),
            nonce: 0,
            deadline: block.timestamp + 1 days
        });
        bytes memory makerPermitSig = signPermitTransferFrom(makerPrivateKey, makerPermit, address(rfq));
        bytes memory makerPermitData = encodeSignatureTransfer(makerPermit, makerPermitSig);

        bytes memory payload = _genFillRFQPayload(defaultOrder, defaultMakerSig, makerPermitData, defaultTakerSig, takerPermitData);
        vm.prank(defaultOffer.taker, defaultOffer.taker);
        userProxy.toRFQv2(payload);
    }

    function testCannotFillWithNonZeroMsgValueIfNoNeed() public {
        // case : takerToken is normal ERC20
        bytes memory payload0 = _genFillRFQPayload(defaultOrder, defaultMakerSig, defaultPermit, defaultTakerSig, defaultPermit);
        vm.prank(defaultOffer.taker, defaultOffer.taker);
        vm.expectRevert("invalid msg value");
        userProxy.toRFQv2{ value: 1 ether }(payload0);

        // case : takerToken is WETH
        Offer memory offer = defaultOffer;
        offer.takerToken = address(weth);
        offer.takerTokenAmount = 1 ether;
        offer.feeFactor = 0;
        RFQOrder memory rfqOrder = RFQOrder({ offer: offer, recipient: payable(recipient) });

        bytes memory makerSig = _signOffer(makerPrivateKey, offer, SignatureValidator.SignatureType.EIP712);
        bytes memory takerSig = _signRFQOrder(takerPrivateKey, rfqOrder, SignatureValidator.SignatureType.EIP712);

        bytes memory payload1 = _genFillRFQPayload(rfqOrder, makerSig, defaultPermit, takerSig, defaultPermit);
        vm.prank(offer.taker, offer.taker);
        vm.expectRevert("invalid msg value");
        userProxy.toRFQv2{ value: 1 ether }(payload1);
    }

    function testCannotFillExpiredOffer() public {
        vm.warp(defaultOffer.expiry);

        vm.expectRevert("offer expired");
        bytes memory payload = _genFillRFQPayload(defaultOrder, defaultMakerSig, defaultPermit, defaultTakerSig, defaultPermit);
        vm.prank(defaultOffer.taker, defaultOffer.taker);
        userProxy.toRFQv2(payload);
    }

    function testCannotFillAlreadyFilledOffer() public {
        bytes memory payload = _genFillRFQPayload(defaultOrder, defaultMakerSig, defaultPermit, defaultTakerSig, defaultPermit);
        vm.prank(defaultOffer.taker, defaultOffer.taker);
        userProxy.toRFQv2(payload);

        vm.expectRevert("PermanentStorage: offer already filled");
        vm.prank(defaultOffer.taker, defaultOffer.taker);
        userProxy.toRFQv2(payload);
    }

    function testCannotFillRFQByIncorrectMakerSig() public {
        uint256 randomPrivateKey = 5677;
        bytes memory randomMakerSig = _signOffer(randomPrivateKey, defaultOffer, SignatureValidator.SignatureType.EIP712);

        vm.expectRevert("invalid signature");
        bytes memory payload = _genFillRFQPayload(defaultOrder, randomMakerSig, defaultPermit, defaultTakerSig, defaultPermit);
        vm.prank(defaultOffer.taker, defaultOffer.taker);
        userProxy.toRFQv2(payload);
    }

    function testCannotFillRFQByIncorrectTakerSig() public {
        RFQOrder memory rfqOrder = RFQOrder({ offer: defaultOffer, recipient: payable(defaultOffer.taker) });
        uint256 randomPrivateKey = 5677;
        bytes memory randomSig = _signRFQOrder(randomPrivateKey, rfqOrder, SignatureValidator.SignatureType.EIP712);

        vm.expectRevert("invalid signature");
        bytes memory payload = _genFillRFQPayload(rfqOrder, defaultMakerSig, defaultPermit, randomSig, defaultPermit);
        vm.prank(defaultOffer.taker, defaultOffer.taker);
        userProxy.toRFQv2(payload);
    }

    function testCannotFillWithInvalidFeeFactor() public {
        Offer memory offer = defaultOffer;
        offer.feeFactor = LibConstant.BPS_MAX;
        RFQOrder memory newRFQOrder = RFQOrder({ offer: offer, recipient: payable(defaultOffer.taker) });
        bytes memory makerSig = _signOffer(makerPrivateKey, offer, SignatureValidator.SignatureType.EIP712);
        bytes memory takerSig = _signRFQOrder(takerPrivateKey, newRFQOrder, SignatureValidator.SignatureType.EIP712);

        vm.expectRevert("invalid fee factor");
        bytes memory payload = _genFillRFQPayload(newRFQOrder, makerSig, defaultPermit, takerSig, defaultPermit);
        vm.prank(defaultOffer.taker, defaultOffer.taker);
        userProxy.toRFQv2(payload);
    }

    function testCannotFillWithZeroRecipient() public {
        RFQOrder memory newRFQOrder = RFQOrder({ offer: defaultOffer, recipient: address(0) });
        bytes memory takerSig = _signRFQOrder(takerPrivateKey, newRFQOrder, SignatureValidator.SignatureType.EIP712);

        vm.expectRevert("zero recipient");
        bytes memory payload = _genFillRFQPayload(newRFQOrder, defaultMakerSig, defaultPermit, takerSig, defaultPermit);
        vm.prank(defaultOffer.taker, defaultOffer.taker);
        userProxy.toRFQv2(payload);
    }

    function _signOffer(
        uint256 _privateKey,
        Offer memory _offer,
        SignatureValidator.SignatureType _sigType
    ) private view returns (bytes memory sig) {
        bytes32 offerHash = getOfferHash(_offer);
        bytes32 EIP712SignDigest = getEIP712Hash(rfq.EIP712_DOMAIN_SEPARATOR(), offerHash);
        return _signEIP712Digest(_privateKey, EIP712SignDigest, _sigType);
    }

    function _signRFQOrder(
        uint256 _privateKey,
        RFQOrder memory _rfqOrder,
        SignatureValidator.SignatureType _sigType
    ) private view returns (bytes memory sig) {
        (, bytes32 rfqOrderHash) = getRFQOrderHash(_rfqOrder);
        bytes32 EIP712SignDigest = getEIP712Hash(rfq.EIP712_DOMAIN_SEPARATOR(), rfqOrderHash);
        return _signEIP712Digest(_privateKey, EIP712SignDigest, _sigType);
    }

    function _signEIP712Digest(
        uint256 _privateKey,
        bytes32 _digest,
        SignatureValidator.SignatureType _sigType
    ) internal pure returns (bytes memory) {
        if (
            _sigType == SignatureValidator.SignatureType.EIP712 ||
            _sigType == SignatureValidator.SignatureType.WalletBytes ||
            _sigType == SignatureValidator.SignatureType.WalletBytes32
        ) {
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, _digest);
            return abi.encodePacked(r, s, v, uint8(_sigType));
        } else if (_sigType == SignatureValidator.SignatureType.Wallet) {
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, ECDSA.toEthSignedMessageHash(_digest));
            return abi.encodePacked(r, s, v, uint8(_sigType));
        } else {
            revert("Invalid signature type");
        }
    }

    function _genFillRFQPayload(
        RFQOrder memory _rfqOrder,
        bytes memory _makerSignature,
        bytes memory _makerTokenPermit,
        bytes memory _takerSignature,
        bytes memory _takerTokenPermit
    ) private view returns (bytes memory payload) {
        return abi.encodeWithSelector(rfq.fillRFQ.selector, _rfqOrder, _makerSignature, _makerTokenPermit, _takerSignature, _takerTokenPermit);
    }

    // =====================
    // AMMWrapperWithPath
    // =====================
    function testAMMWrapperWithPath() public {
        uint256 SINGLE_POOL_SWAP_TYPE = 1;
        uint16 DEFAULT_FEE_FACTOR = 500;
        uint24 FEE_MEDIUM = 3000;

        AMMLibEIP712.Order memory order = AMMLibEIP712.Order(
            UNISWAP_V3_ADDRESS, // makerAddr
            address(usdc), // takerAssetAddr
            address(dai), // makerAssetAddr
            uint256(100 * 1e6), // takerAssetAmount
            uint256(90 * 1e18), // makerAssetAmount
            taker, // userAddr
            payable(taker), // receiverAddr
            uint256(1234), // salt
            defaultExpiry // deadline
        );

        bytes memory sig = _signTrade(takerPrivateKey, order);
        address[] memory path = new address[](0);
        bytes memory makerSpecificData = _encodeUniswapSinglePoolData(SINGLE_POOL_SWAP_TYPE, FEE_MEDIUM);
        bytes memory payload = _genTradePayload(order, DEFAULT_FEE_FACTOR, sig, makerSpecificData, path);

        //vm.prank(relayer, relayer);
        userProxy.toAMM(payload);
    }

    function _signTrade(uint256 privateKey, AMMLibEIP712.Order memory order) internal returns (bytes memory) {
        bytes32 orderHash = AMMLibEIP712._getOrderHash(order);
        bytes32 EIP712SignDigest = getEIP712Hash(ammWrapperWithPath.EIP712_DOMAIN_SEPARATOR(), orderHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, EIP712SignDigest);
        return abi.encodePacked(r, s, v, bytes32(0), uint8(SignatureValidator.SignatureType.EIP712));
    }

    function _genTradePayload(
        AMMLibEIP712.Order memory order,
        uint256 feeFactor,
        bytes memory sig,
        bytes memory makerSpecificData,
        address[] memory path
    ) internal pure returns (bytes memory payload) {
        return
            abi.encodeWithSignature(
                "trade((address,address,address,uint256,uint256,address,address,uint256,uint256),uint256,bytes,bytes,address[])",
                order,
                feeFactor,
                sig,
                makerSpecificData,
                path
            );
    }

    // =====================
    // PMM
    // =====================

    function testPMM() public {
        zxOrder.Order memory order = zxOrder.Order({
            makerAddress: maker,
            takerAddress: address(pmm),
            feeRecipientAddress: taker,
            senderAddress: address(pmm),
            makerAssetAmount: 100,
            takerAssetAmount: 300,
            makerFee: 0,
            takerFee: 0,
            expirationTimeSeconds: defaultExpiry,
            salt: defaultSalt,
            makerAssetData: _encodeAssetData(address(dai)),
            takerAssetData: _encodeAssetData(address(usdc))
        });

        bytes memory makerSig = _signPMMOrder(makerPrivateKey, order);
        bytes memory zxPayload = abi.encodeWithSelector(IZxExchange.fillOrKillOrder.selector, order, order.takerAssetAmount, makerSig);
        bytes memory takerSig = _signPMMTx(takerPrivateKey, taker, zxPayload);

        bytes memory payload = abi.encodeWithSelector(pmm.fill.selector, defaultSalt, zxPayload, takerSig);
        vm.prank(taker, taker); // Only EOA
        userProxy.toPMM(payload);
    }

    function _encodeAssetData(address tokenAddr) internal returns (bytes memory) {
        // 4 bytes proxy id
        // 12 bytes dummy
        // 20 bytes token address
        bytes4 proxyId = hex"f47261b0";
        bytes12 dummy;
        return abi.encodePacked(proxyId, dummy, tokenAddr);
    }

    function _signPMMOrder(uint256 privateKey, zxOrder.Order memory order) internal returns (bytes memory) {
        bytes32 orderHash = zxOrder.hashOrder(order);
        bytes32 EIP712SignDigest = getEIP712Hash(zxExchange.EIP712_DOMAIN_HASH(), orderHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, EIP712SignDigest);
        return abi.encodePacked(v, r, s, uint8(SignatureValidator.SignatureType.EIP712));
    }

    function _signPMMTx(
        uint256 privateKey,
        address receiver,
        bytes memory data
    ) internal returns (bytes memory) {
        bytes32 txStructHash = zxOrder.encodeTransactionHash(defaultSalt, address(pmm), data);
        bytes32 tx712Hash = getEIP712Hash(zxExchange.EIP712_DOMAIN_HASH(), txStructHash);
        bytes32 signHash = keccak256(abi.encodePacked(tx712Hash, receiver));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, signHash);
        // FIXME sig format
        return abi.encodePacked(v, r, s, receiver);
    }

    // =====================
    // RFQv1
    // =====================
    function testRFQv1() public {
        RFQLibEIP712.Order memory order = RFQLibEIP712.Order(
            taker, // takerAddr
            maker, // makerAddr
            address(dai), // takerAssetAddr
            address(usdt), // makerAssetAddr
            100 * 1e18, // takerAssetAmount
            90 * 1e6, // makerAssetAmount
            taker, // receiverAddr
            uint256(1234), // salt
            defaultExpiry, // deadline
            0 // feeFactor
        );
        bytes memory makerSig = _signOrder({ privateKey: makerPrivateKey, order: order });
        bytes memory takerSig = _signFill({ privateKey: takerPrivateKey, order: order });
        bytes memory payload = _genFillPayload({ order: order, makerSig: makerSig, takerSig: takerSig });

        vm.prank(taker, taker); // Only EOA
        userProxy.toRFQ(payload);
    }

    function _signOrder(uint256 privateKey, RFQLibEIP712.Order memory order) internal returns (bytes memory) {
        bytes32 orderHash = RFQLibEIP712._getOrderHash(order);
        bytes32 EIP712SignDigest = getEIP712Hash(rfqv1.EIP712_DOMAIN_SEPARATOR(), orderHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, EIP712SignDigest);
        return abi.encodePacked(r, s, v, bytes32(0), uint8(SignatureValidator.SignatureType.EIP712));
    }

    function _signFill(uint256 privateKey, RFQLibEIP712.Order memory order) internal returns (bytes memory) {
        bytes32 transactionHash = RFQLibEIP712._getTransactionHash(order);
        bytes32 EIP712SignDigest = getEIP712Hash(rfqv1.EIP712_DOMAIN_SEPARATOR(), transactionHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, EIP712SignDigest);
        return abi.encodePacked(r, s, v, bytes32(0), uint8(SignatureValidator.SignatureType.EIP712));
    }

    function _genFillPayload(
        RFQLibEIP712.Order memory order,
        bytes memory makerSig,
        bytes memory takerSig
    ) internal view returns (bytes memory) {
        return abi.encodeWithSelector(rfqv1.fill.selector, order, makerSig, takerSig);
    }

    // =====================
    // LimitOrder
    // =====================
    function testLimitOrder() public {
        uint256 coordinatorPrivateKey = uint256(3);
        address loOwner = 0x63Ef071b8A69C52a88dCA4A844286Aeff195129F;
        vm.prank(loOwner, loOwner);
        limitOrder.upgradeCoordinator(vm.addr(coordinatorPrivateKey));
        uint64 expiry = uint64(defaultExpiry);

        LimitOrderLibEIP712.Order memory order = LimitOrderLibEIP712.Order(
            dai, // makerToken
            usdt, // takerToken
            100 * 1e18, // makerTokenAmount
            90 * 1e6, // takerTokenAmount
            maker, // maker
            address(0), // taker
            uint256(1001), // salt
            expiry // expiry
        );
        bytes32 orderHash = getEIP712Hash(limitOrder.EIP712_DOMAIN_SEPARATOR(), LimitOrderLibEIP712._getOrderStructHash(order));

        bytes memory makerSig = _signLO(makerPrivateKey, order);
        LimitOrderLibEIP712.Fill memory fill = LimitOrderLibEIP712.Fill(orderHash, taker, taker, order.takerTokenAmount, uint256(1002), expiry);

        ILimitOrder.TraderParams memory traderParams = ILimitOrder.TraderParams(
            taker, // taker
            taker, // recipient
            fill.takerTokenAmount, // takerTokenAmount
            fill.takerSalt, // salt
            expiry, // expiry
            _signLOFill(takerPrivateKey, fill) // takerSig
        );
        LimitOrderLibEIP712.AllowFill memory allowFill = LimitOrderLibEIP712.AllowFill(
            orderHash, // orderHash
            taker, // executor
            fill.takerTokenAmount, // fillAmount
            uint256(1003), // salt
            expiry // expiry
        );
        ILimitOrder.CoordinatorParams memory crdParams = ILimitOrder.CoordinatorParams(
            _signAllowFill(coordinatorPrivateKey, allowFill),
            allowFill.salt,
            allowFill.expiry
        );

        bytes memory payload = _genFillByTraderPayload(order, makerSig, traderParams, crdParams);
        vm.prank(taker, taker); // Only EOA
        userProxy.toLimitOrder(payload);
    }

    function _signLO(uint256 privateKey, LimitOrderLibEIP712.Order memory order) internal returns (bytes memory) {
        bytes32 orderHash = LimitOrderLibEIP712._getOrderStructHash(order);
        bytes32 EIP712SignDigest = getEIP712Hash(limitOrder.EIP712_DOMAIN_SEPARATOR(), orderHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, EIP712SignDigest);
        return abi.encodePacked(r, s, v, bytes32(0), uint8(SignatureValidator.SignatureType.EIP712));
    }

    function _signLOFill(uint256 privateKey, LimitOrderLibEIP712.Fill memory fill) internal returns (bytes memory) {
        bytes32 fillHash = LimitOrderLibEIP712._getFillStructHash(fill);
        bytes32 EIP712SignDigest = getEIP712Hash(limitOrder.EIP712_DOMAIN_SEPARATOR(), fillHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, EIP712SignDigest);
        return abi.encodePacked(r, s, v, bytes32(0), uint8(SignatureValidator.SignatureType.EIP712));
    }

    function _signAllowFill(uint256 privateKey, LimitOrderLibEIP712.AllowFill memory allowFill) internal returns (bytes memory) {
        bytes32 allowFillHash = LimitOrderLibEIP712._getAllowFillStructHash(allowFill);
        bytes32 EIP712SignDigest = getEIP712Hash(limitOrder.EIP712_DOMAIN_SEPARATOR(), allowFillHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, EIP712SignDigest);
        return abi.encodePacked(r, s, v, bytes32(0), uint8(SignatureValidator.SignatureType.EIP712));
    }

    function _genFillByTraderPayload(
        LimitOrderLibEIP712.Order memory order,
        bytes memory orderMakerSig,
        ILimitOrder.TraderParams memory params,
        ILimitOrder.CoordinatorParams memory crdParams
    ) internal view returns (bytes memory payload) {
        return abi.encodeWithSelector(limitOrder.fillLimitOrderByTrader.selector, order, orderMakerSig, params, crdParams);
    }
}
