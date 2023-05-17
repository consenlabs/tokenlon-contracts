// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";
import { Tokens } from "test/utils/Tokens.sol";
import { BalanceUtil } from "test/utils/BalanceUtil.sol";
import { BalanceSnapshot, Snapshot } from "test/utils/BalanceSnapshot.sol";
import { getEIP712Hash } from "test/utils/Sig.sol";
import { MockERC1271Wallet } from "test/mocks/MockERC1271Wallet.sol";
import { RFQ } from "contracts/RFQ.sol";
import { IRFQ } from "contracts/interfaces/IRFQ.sol";
import { IWETH } from "contracts/interfaces/IWETH.sol";
import { TokenCollector } from "contracts/abstracts/TokenCollector.sol";
import { Offer, getOfferHash } from "contracts/libraries/Offer.sol";
import { RFQOrder, getRFQOrderHash } from "contracts/libraries/RFQOrder.sol";
import { Constant } from "contracts/libraries/Constant.sol";

// FIXME add taker = eoa + spender & maker = contract + directly approval
contract RFQTest is Test, Tokens, BalanceUtil {
    using BalanceSnapshot for Snapshot;

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
    event SetFeeCollector(address newFeeCollector);

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
    Offer defaultOffer;
    RFQ rfq;

    function setUp() public {
        rfq = new RFQ(rfqOwner, UNISWAP_PERMIT2_ADDRESS, IWETH(WETH_ADDRESS), feeCollector);

        deal(maker, 100 ether);
        setTokenBalanceAndApprove(maker, address(rfq), tokens, 100000);
        deal(taker, 100 ether);
        setTokenBalanceAndApprove(taker, address(rfq), tokens, 100000);
        defaultPermit = abi.encode(TokenCollector.Source.Token, bytes(""));

        defaultOffer = Offer({
            taker: taker,
            maker: maker,
            takerToken: USDT_ADDRESS,
            takerTokenAmount: 10 * 1e6,
            makerToken: LON_ADDRESS,
            makerTokenAmount: 10,
            minMakerTokenAmount: 10,
            allowContractSender: true,
            expiry: defaultExpiry,
            salt: defaultSalt
        });

        defaultMakerSig = _signOffer(makerPrivateKey, defaultOffer);

        vm.label(taker, "taker");
        vm.label(maker, "maker");
        vm.label(address(rfq), "rfq");
    }

    function testCannotSetFeeCollectorByNotOwner() public {
        address newFeeCollector = makeAddr("newFeeCollector");
        vm.prank(newFeeCollector);
        vm.expectRevert("not owner");
        rfq.setFeeCollector(payable(newFeeCollector));
    }

    function testCannotSetFeeCollectorToZero() public {
        vm.prank(rfqOwner, rfqOwner);
        vm.expectRevert(IRFQ.ZeroAddress.selector);
        rfq.setFeeCollector(payable(address(0)));
    }

    function testSetFeeCollector() public {
        address newFeeCollector = makeAddr("newFeeCollector");
        vm.prank(rfqOwner, rfqOwner);
        rfq.setFeeCollector(payable(newFeeCollector));
        emit SetFeeCollector(newFeeCollector);
        assertEq(rfq.feeCollector(), newFeeCollector);
    }

    function testFillRFQ() public {
        Snapshot memory takerTakerToken = BalanceSnapshot.take({ owner: defaultOffer.taker, token: defaultOffer.takerToken });
        Snapshot memory takerMakerToken = BalanceSnapshot.take({ owner: defaultOffer.taker, token: defaultOffer.makerToken });
        Snapshot memory makerTakerToken = BalanceSnapshot.take({ owner: defaultOffer.maker, token: defaultOffer.takerToken });
        Snapshot memory makerMakerToken = BalanceSnapshot.take({ owner: defaultOffer.maker, token: defaultOffer.makerToken });
        Snapshot memory recTakerToken = BalanceSnapshot.take({ owner: recipient, token: defaultOffer.takerToken });
        Snapshot memory recMakerToken = BalanceSnapshot.take({ owner: recipient, token: defaultOffer.makerToken });

        vm.expectEmit(true, true, true, true);
        emit FilledRFQ(
            getOfferHash(defaultOffer),
            defaultOffer.taker,
            defaultOffer.maker,
            defaultOffer.takerToken,
            defaultOffer.takerTokenAmount,
            defaultOffer.makerToken,
            defaultOffer.makerTokenAmount,
            recipient,
            defaultOffer.makerTokenAmount,
            0
        );

        vm.prank(defaultOffer.taker);
        rfq.fillRFQ(defaultOffer, defaultMakerSig, defaultPermit, defaultPermit, recipient);

        takerTakerToken.assertChange(-int256(defaultOffer.takerTokenAmount));
        takerMakerToken.assertChange(int256(0));
        makerTakerToken.assertChange(int256(defaultOffer.takerTokenAmount));
        makerMakerToken.assertChange(-int256(defaultOffer.makerTokenAmount));
        recTakerToken.assertChange(int256(0));
        recMakerToken.assertChange(int256(defaultOffer.makerTokenAmount));
    }

    function testFillRFQWithRawETH() public {
        // case : taker token is ETH
        Offer memory offer = defaultOffer;
        offer.takerToken = Constant.ZERO_ADDRESS;
        offer.takerTokenAmount = 1 ether;

        bytes memory makerSig = _signOffer(makerPrivateKey, offer);

        Snapshot memory takerTakerToken = BalanceSnapshot.take({ owner: offer.taker, token: offer.takerToken });
        Snapshot memory takerMakerToken = BalanceSnapshot.take({ owner: offer.taker, token: offer.makerToken });
        Snapshot memory makerTakerToken = BalanceSnapshot.take({ owner: offer.maker, token: offer.takerToken });
        Snapshot memory makerMakerToken = BalanceSnapshot.take({ owner: offer.maker, token: offer.makerToken });
        Snapshot memory recTakerToken = BalanceSnapshot.take({ owner: recipient, token: offer.takerToken });
        Snapshot memory recMakerToken = BalanceSnapshot.take({ owner: recipient, token: offer.makerToken });

        vm.prank(defaultOffer.taker);
        rfq.fillRFQ{ value: offer.takerTokenAmount }(offer, makerSig, defaultPermit, defaultPermit, recipient);

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

        bytes memory makerSig = _signOffer(makerPrivateKey, offer);

        Snapshot memory takerTakerToken = BalanceSnapshot.take({ owner: offer.taker, token: offer.takerToken });
        Snapshot memory takerMakerToken = BalanceSnapshot.take({ owner: offer.taker, token: offer.makerToken });
        Snapshot memory makerTakerToken = BalanceSnapshot.take({ owner: offer.maker, token: offer.takerToken });
        Snapshot memory makerMakerToken = BalanceSnapshot.take({ owner: offer.maker, token: offer.makerToken });
        // recipient should receive raw ETH
        Snapshot memory recTakerToken = BalanceSnapshot.take({ owner: recipient, token: offer.takerToken });
        Snapshot memory recMakerToken = BalanceSnapshot.take({ owner: recipient, token: Constant.ZERO_ADDRESS });

        vm.prank(defaultOffer.taker);
        rfq.fillRFQ(offer, makerSig, defaultPermit, defaultPermit, recipient);

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

        bytes memory makerSig = _signOffer(makerPrivateKey, offer);

        Snapshot memory takerTakerToken = BalanceSnapshot.take({ owner: offer.taker, token: offer.takerToken });
        Snapshot memory takerMakerToken = BalanceSnapshot.take({ owner: offer.taker, token: offer.makerToken });
        // maker should receive raw ETH
        Snapshot memory makerTakerToken = BalanceSnapshot.take({ owner: offer.maker, token: Constant.ZERO_ADDRESS });
        Snapshot memory makerMakerToken = BalanceSnapshot.take({ owner: offer.maker, token: offer.makerToken });
        Snapshot memory recTakerToken = BalanceSnapshot.take({ owner: recipient, token: offer.takerToken });
        Snapshot memory recMakerToken = BalanceSnapshot.take({ owner: recipient, token: offer.makerToken });

        vm.prank(defaultOffer.taker);
        rfq.fillRFQ(offer, makerSig, defaultPermit, defaultPermit, recipient);

        takerTakerToken.assertChange(-int256(offer.takerTokenAmount));
        takerMakerToken.assertChange(int256(0));
        makerTakerToken.assertChange(int256(offer.takerTokenAmount));
        makerMakerToken.assertChange(-int256(offer.makerTokenAmount));
        recTakerToken.assertChange(int256(0));
        recMakerToken.assertChange(int256(offer.makerTokenAmount));
    }

    function testCannotFillExpiredRFQOrder() public {
        vm.warp(defaultOffer.expiry + 1);

        vm.expectRevert(IRFQ.ExpiredOffer.selector);
        vm.prank(defaultOffer.taker);
        rfq.fillRFQ(defaultOffer, defaultMakerSig, defaultPermit, defaultPermit, recipient);
    }

    function testCannotFillAlreadyFillRFQOrder() public {
        vm.prank(defaultOffer.taker);
        rfq.fillRFQ(defaultOffer, defaultMakerSig, defaultPermit, defaultPermit, recipient);

        vm.expectRevert(IRFQ.FilledOffer.selector);
        vm.prank(defaultOffer.taker);
        rfq.fillRFQ(defaultOffer, defaultMakerSig, defaultPermit, defaultPermit, recipient);
    }

    function testCannotFillRFQByIncorrectMakerSig() public {
        uint256 randomPrivateKey = 5677;
        bytes memory randomMakerSig = _signOffer(randomPrivateKey, defaultOffer);

        vm.expectRevert(IRFQ.InvalidSignature.selector);
        vm.prank(defaultOffer.taker);
        rfq.fillRFQ(defaultOffer, randomMakerSig, defaultPermit, defaultPermit, recipient);
    }

    function testFillRFQByTakerSig() public {
        Snapshot memory takerTakerToken = BalanceSnapshot.take({ owner: defaultOffer.taker, token: defaultOffer.takerToken });
        Snapshot memory takerMakerToken = BalanceSnapshot.take({ owner: defaultOffer.taker, token: defaultOffer.makerToken });
        Snapshot memory makerTakerToken = BalanceSnapshot.take({ owner: defaultOffer.maker, token: defaultOffer.takerToken });
        Snapshot memory makerMakerToken = BalanceSnapshot.take({ owner: defaultOffer.maker, token: defaultOffer.makerToken });
        Snapshot memory recTakerToken = BalanceSnapshot.take({ owner: recipient, token: defaultOffer.takerToken });
        Snapshot memory recMakerToken = BalanceSnapshot.take({ owner: recipient, token: defaultOffer.makerToken });

        RFQOrder memory rfqOrder = RFQOrder({ offer: defaultOffer, recipient: payable(recipient), feeFactor: defaultFeeFactor });
        bytes memory takerSig = _signRFQOrder(takerPrivateKey, rfqOrder);

        uint256 fee = (defaultOffer.makerTokenAmount * rfqOrder.feeFactor) / Constant.BPS_MAX;
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
            rfqOrder.recipient,
            amountAfterFee,
            rfqOrder.feeFactor
        );

        rfq.fillRFQ(rfqOrder, defaultMakerSig, defaultPermit, defaultPermit, takerSig);

        takerTakerToken.assertChange(-int256(defaultOffer.takerTokenAmount));
        takerMakerToken.assertChange(int256(0));
        makerTakerToken.assertChange(int256(defaultOffer.takerTokenAmount));
        makerMakerToken.assertChange(-int256(defaultOffer.makerTokenAmount));
        recTakerToken.assertChange(int256(0));
        // recipient gets less than original makerTokenAmount because of the fee for relayer
        recMakerToken.assertChange(int256(amountAfterFee));
    }

    function testCannotFillRFQByIncorrectTakerSig() public {
        RFQOrder memory rfqOrder = RFQOrder({ offer: defaultOffer, recipient: payable(defaultOffer.taker), feeFactor: defaultFeeFactor });
        uint256 randomPrivateKey = 5677;
        bytes memory randomSig = _signRFQOrder(randomPrivateKey, rfqOrder);

        vm.expectRevert(IRFQ.InvalidSignature.selector);
        rfq.fillRFQ(rfqOrder, defaultMakerSig, defaultPermit, defaultPermit, randomSig);
    }

    function testCannotFillWithInvalidFeeFactor() public {
        RFQOrder memory newRFQOrder = RFQOrder({ offer: defaultOffer, recipient: payable(defaultOffer.taker), feeFactor: Constant.BPS_MAX + 1 });
        bytes memory takerSig = _signRFQOrder(takerPrivateKey, newRFQOrder);

        vm.expectRevert(IRFQ.InvalidFeeFactor.selector);
        rfq.fillRFQ(newRFQOrder, defaultMakerSig, defaultPermit, defaultPermit, takerSig);
    }

    function testCannotFillWithContractIfNotAllowed() public {
        Offer memory offer = defaultOffer;
        offer.allowContractSender = false;
        RFQOrder memory newRFQOrder = RFQOrder({ offer: offer, recipient: payable(defaultOffer.taker), feeFactor: defaultFeeFactor });
        bytes memory takerSig = _signRFQOrder(takerPrivateKey, newRFQOrder);

        vm.expectRevert(IRFQ.ForbidContract.selector);
        rfq.fillRFQ(newRFQOrder, defaultMakerSig, defaultPermit, defaultPermit, takerSig);
    }

    function _signOffer(uint256 _privateKey, Offer memory _offer) internal view returns (bytes memory sig) {
        bytes32 offerHash = getOfferHash(_offer);
        bytes32 EIP712SignDigest = getEIP712Hash(rfq.EIP712_DOMAIN_SEPARATOR(), offerHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, EIP712SignDigest);
        return abi.encodePacked(r, s, v);
    }

    function _signRFQOrder(uint256 _privateKey, RFQOrder memory _rfqOrder) internal view returns (bytes memory sig) {
        (, bytes32 rfqOrderHash) = getRFQOrderHash(_rfqOrder);
        bytes32 EIP712SignDigest = getEIP712Hash(rfq.EIP712_DOMAIN_SEPARATOR(), rfqOrderHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, EIP712SignDigest);
        return abi.encodePacked(r, s, v);
    }
}
