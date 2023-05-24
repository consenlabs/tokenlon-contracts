// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import { ECDSA } from "@openzeppelin/contracts/cryptography/ECDSA.sol";

import { StrategySharedSetup } from "test/utils/StrategySharedSetup.sol";
import { BalanceSnapshot } from "test/utils/BalanceSnapshot.sol";
import { getEIP712Hash } from "test/utils/Sig.sol";
import { getPermitTransferFromStructHash, encodePermitTransferFromData } from "test/utils/Permit2.sol";
import { RFQv2 } from "contracts/RFQv2.sol";
import { MarketMakerProxy } from "contracts/MarketMakerProxy.sol";
import { SignatureValidator } from "contracts/utils/SignatureValidator.sol";
import { TokenCollector } from "contracts/utils/TokenCollector.sol";
import { Offer, getOfferHash } from "contracts/utils/Offer.sol";
import { RFQOrder, getRFQOrderHash } from "contracts/utils/RFQOrder.sol";
import { LibConstant } from "contracts/utils/LibConstant.sol";
import { IUniswapPermit2 } from "contracts/interfaces/IUniswapPermit2.sol";
import { IWETH } from "contracts/interfaces/IWeth.sol";

contract RFQTest is StrategySharedSetup {
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
    address payable recipient = payable(makeAddr("recipient"));
    address payable feeCollector = payable(makeAddr("feeCollector"));
    uint256 defaultExpiry = block.timestamp + 1;
    uint256 defaultSalt = 1234;
    uint256 defaultFeeFactor = 100;
    bytes defaultPermit;
    bytes defaultMakerSig;
    bytes defaultTakerSig;
    IUniswapPermit2 permit2 = IUniswapPermit2(UNISWAP_PERMIT2_ADDRESS);
    Offer defaultOffer;
    RFQOrder defaultOrder;
    MarketMakerProxy marketMakerProxy;
    RFQv2 rfq;

    function setUp() public {
        // Setup
        setUpSystemContracts();

        marketMakerProxy = new MarketMakerProxy(maker, maker, IWETH(address(weth)));

        deal(maker, 100 ether);
        setEOABalanceAndApprove(maker, tokens, 100000);
        deal(address(marketMakerProxy), 100 ether);
        setWalletContractBalanceAndApprove({ owner: maker, walletContract: address(marketMakerProxy), tokens: tokens, amount: 100000 });
        deal(taker, 100 ether);
        setEOABalanceAndApprove(taker, tokens, 100000);
        defaultPermit = abi.encode(TokenCollector.Source.TokenlonSpender, bytes(""));

        defaultOffer = Offer({
            taker: taker,
            maker: maker,
            takerToken: USDT_ADDRESS,
            takerTokenAmount: 10 * 1e6,
            makerToken: LON_ADDRESS,
            makerTokenAmount: 10,
            expiry: defaultExpiry,
            salt: defaultSalt
        });

        defaultMakerSig = _signOffer(makerPrivateKey, defaultOffer, SignatureValidator.SignatureType.EIP712);

        defaultOrder = RFQOrder({ offer: defaultOffer, recipient: payable(recipient), feeFactor: defaultFeeFactor });
        defaultTakerSig = _signRFQOrder(takerPrivateKey, defaultOrder, SignatureValidator.SignatureType.EIP712);

        vm.label(taker, "taker");
        vm.label(maker, "maker");
        vm.label(address(rfq), "rfq");
    }

    function _deployStrategyAndUpgrade() internal override returns (address) {
        rfq = new RFQv2(rfqOwner, address(userProxy), address(weth), address(permanentStorage), address(spender), UNISWAP_PERMIT2_ADDRESS, feeCollector);

        // Setup
        userProxy.upgradeRFQv2(address(rfq), true);

        vm.startPrank(psOperator, psOperator);
        permanentStorage.upgradeRFQv2(address(rfq));
        permanentStorage.setPermission(permanentStorage.transactionSeenStorageId(), address(rfq), true);
        vm.stopPrank();

        return address(rfq);
    }

    function _setupDeployedStrategy() internal override {
        rfq = RFQv2(payable(vm.envAddress("RFQv2_ADDRESS")));

        // prank owner and update coordinator address
        rfqOwner = rfq.owner();
        vm.prank(rfqOwner, rfqOwner);
        // update local feeCollector address
        feeCollector = rfq.feeCollector();
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

        uint256 fee = (defaultOffer.makerTokenAmount * defaultOrder.feeFactor) / LibConstant.BPS_MAX;
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
            defaultOrder.feeFactor
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
        RFQOrder memory rfqOrder = RFQOrder({ offer: offer, recipient: payable(recipient), feeFactor: 0 });

        bytes memory makerSig = _signOffer(makerPrivateKey, offer, SignatureValidator.SignatureType.WalletBytes32);
        bytes memory takerSig = _signRFQOrder(takerPrivateKey, rfqOrder, SignatureValidator.SignatureType.EIP712);

        address[] memory tokenAddresses = new address[](1);
        tokenAddresses[0] = offer.makerToken;
        vm.startPrank(maker);
        marketMakerProxy.setAllowance(tokenAddresses, address(rfq));
        marketMakerProxy.closeAllowance(tokenAddresses, address(allowanceTarget));
        vm.stopPrank();
        bytes memory makerPermit = abi.encode(TokenCollector.Source.Token, bytes(""));

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
        RFQOrder memory rfqOrder = RFQOrder({ offer: offer, recipient: payable(recipient), feeFactor: 0 });

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
        offer.makerToken = WETH_ADDRESS;
        offer.makerTokenAmount = 1 ether;
        RFQOrder memory rfqOrder = RFQOrder({ offer: offer, recipient: payable(recipient), feeFactor: 0 });

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
        offer.takerToken = WETH_ADDRESS;
        offer.takerTokenAmount = 1 ether;
        RFQOrder memory rfqOrder = RFQOrder({ offer: offer, recipient: payable(recipient), feeFactor: 0 });

        bytes memory makerSig = _signOffer(makerPrivateKey, offer, SignatureValidator.SignatureType.EIP712);
        bytes memory takerSig = _signRFQOrder(takerPrivateKey, rfqOrder, SignatureValidator.SignatureType.EIP712);

        BalanceSnapshot.Snapshot memory takerTakerToken = BalanceSnapshot.take({ owner: offer.taker, token: offer.takerToken });
        BalanceSnapshot.Snapshot memory takerMakerToken = BalanceSnapshot.take({ owner: offer.taker, token: offer.makerToken });
        // maker should receive raw ETH
        BalanceSnapshot.Snapshot memory makerTakerToken = BalanceSnapshot.take({ owner: offer.maker, token: LibConstant.ETH_ADDRESS });
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
        spender.deauthorize(authListAddress);

        // maker approve tokens to RFQv2 contract directly
        approveERC20(tokens, maker, address(rfq));
        // taker approve tokens to RFQv2 contract directly
        approveERC20(tokens, taker, address(rfq));
        bytes memory tokenPermit = abi.encode(TokenCollector.Source.Token, bytes(""));

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
        bytes memory takerPermitSig = _signPermitTransferFrom(takerPrivateKey, takerPermit, address(rfq));
        bytes memory takerPermitData = encodePermitTransferFromData(takerPermit, takerPermitSig);

        IUniswapPermit2.PermitTransferFrom memory makerPermit = IUniswapPermit2.PermitTransferFrom({
            permitted: IUniswapPermit2.TokenPermissions({ token: defaultOffer.makerToken, amount: defaultOffer.makerTokenAmount }),
            nonce: 0,
            deadline: block.timestamp + 1 days
        });
        bytes memory makerPermitSig = _signPermitTransferFrom(makerPrivateKey, makerPermit, address(rfq));
        bytes memory makerPermitData = encodePermitTransferFromData(makerPermit, makerPermitSig);

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
        offer.takerToken = WETH_ADDRESS;
        offer.takerTokenAmount = 1 ether;
        RFQOrder memory rfqOrder = RFQOrder({ offer: offer, recipient: payable(recipient), feeFactor: 0 });

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
        RFQOrder memory rfqOrder = RFQOrder({ offer: defaultOffer, recipient: payable(defaultOffer.taker), feeFactor: defaultFeeFactor });
        uint256 randomPrivateKey = 5677;
        bytes memory randomSig = _signRFQOrder(randomPrivateKey, rfqOrder, SignatureValidator.SignatureType.EIP712);

        vm.expectRevert("invalid signature");
        bytes memory payload = _genFillRFQPayload(rfqOrder, defaultMakerSig, defaultPermit, randomSig, defaultPermit);
        vm.prank(defaultOffer.taker, defaultOffer.taker);
        userProxy.toRFQv2(payload);
    }

    function testCannotFillWithInvalidFeeFactor() public {
        RFQOrder memory newRFQOrder = RFQOrder({ offer: defaultOffer, recipient: payable(defaultOffer.taker), feeFactor: LibConstant.BPS_MAX });
        bytes memory takerSig = _signRFQOrder(takerPrivateKey, newRFQOrder, SignatureValidator.SignatureType.EIP712);

        vm.expectRevert("invalid fee factor");
        bytes memory payload = _genFillRFQPayload(newRFQOrder, defaultMakerSig, defaultPermit, takerSig, defaultPermit);
        vm.prank(defaultOffer.taker, defaultOffer.taker);
        userProxy.toRFQv2(payload);
    }

    function testCannotFillWithZeroRecipient() public {
        RFQOrder memory newRFQOrder = RFQOrder({ offer: defaultOffer, recipient: address(0), feeFactor: defaultFeeFactor });
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

    function _signPermitTransferFrom(
        uint256 privateKey,
        IUniswapPermit2.PermitTransferFrom memory permit,
        address spender
    ) private view returns (bytes memory) {
        bytes32 permitHash = getPermitTransferFromStructHash(permit, spender);
        bytes32 EIP712SignDigest = getEIP712Hash(permit2.DOMAIN_SEPARATOR(), permitHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, EIP712SignDigest);
        return abi.encodePacked(r, s, v);
    }
}
