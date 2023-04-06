// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import { StrategySharedSetup } from "test/utils/StrategySharedSetup.sol";
import { BalanceSnapshot } from "test/utils/BalanceSnapshot.sol";
import { getEIP712Hash } from "test/utils/Sig.sol";
import { getPermitTransferFromStructHash, encodePermitTransferFromData } from "test/utils/Permit2.sol";
import { RFQv2 } from "contracts/RFQv2.sol";
import { TokenCollector } from "contracts/utils/TokenCollector.sol";
import { Offer, getOfferHash } from "contracts/utils/Offer.sol";
import { RFQOrder, getRFQOrderHash } from "contracts/utils/RFQOrder.sol";
import { LibConstant } from "contracts/utils/LibConstant.sol";
import { IUniswapPermit2 } from "contracts/interfaces/IUniswapPermit2.sol";

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
    bytes defaulttakerSig;
    IUniswapPermit2 permit2 = IUniswapPermit2(UNISWAP_PERMIT2_ADDRESS);
    Offer defaultOffer;
    RFQOrder defaultOrder;
    RFQv2 rfq;

    function setUp() public {
        // Setup
        setUpSystemContracts();

        deal(maker, 100 ether);
        setEOABalanceAndApprove(maker, tokens, 100000);
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
            minMakerTokenAmount: 10,
            expiry: defaultExpiry,
            salt: defaultSalt
        });

        defaultMakerSig = _signOffer(makerPrivateKey, defaultOffer);

        defaultOrder = RFQOrder({ offer: defaultOffer, recipient: payable(recipient), feeFactor: defaultFeeFactor });
        defaulttakerSig = _signRFQOrder(takerPrivateKey, defaultOrder);

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

        bytes memory payload = _genFillRFQPayload(defaultOrder, defaultMakerSig, defaultPermit, defaulttakerSig, defaultPermit);
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

    function testFillRFQWithMakerDirectlyApprove() public {
        // maker approve tokens to RFQ contract directly
        approveERC20(tokens, maker, address(rfq));
        bytes memory tokenPermit = abi.encode(TokenCollector.Source.Token, bytes(""));

        bytes memory payload = _genFillRFQPayload(defaultOrder, defaultMakerSig, tokenPermit, defaulttakerSig, defaultPermit);
        userProxy.toRFQv2(payload);
    }

    function testFillRFQWithTakerDirectlyApprove() public {
        // taker approve tokens to RFQ contract directly
        approveERC20(tokens, taker, address(rfq));
        bytes memory tokenPermit = abi.encode(TokenCollector.Source.Token, bytes(""));

        bytes memory payload = _genFillRFQPayload(defaultOrder, defaultMakerSig, defaultPermit, defaulttakerSig, tokenPermit);
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

        bytes memory payload = _genFillRFQPayload(defaultOrder, defaultMakerSig, makerPermitData, defaulttakerSig, takerPermitData);
        userProxy.toRFQv2(payload);
    }

    function testCannotFillExpiredOffer() public {
        vm.warp(defaultOffer.expiry + 1);

        vm.expectRevert("offer expired");
        bytes memory payload = _genFillRFQPayload(defaultOrder, defaultMakerSig, defaultPermit, defaulttakerSig, defaultPermit);
        userProxy.toRFQv2(payload);
    }

    function testCannotFillAlreadyFilledOffer() public {
        bytes memory payload = _genFillRFQPayload(defaultOrder, defaultMakerSig, defaultPermit, defaulttakerSig, defaultPermit);
        userProxy.toRFQv2(payload);

        vm.expectRevert("PermanentStorage: offer already filled");
        userProxy.toRFQv2(payload);
    }

    function testCannotFillRFQByIncorrectMakerSig() public {
        uint256 randomPrivateKey = 5677;
        bytes memory randomMakerSig = _signOffer(randomPrivateKey, defaultOffer);

        vm.expectRevert("invalid signature");
        bytes memory payload = _genFillRFQPayload(defaultOrder, randomMakerSig, defaultPermit, defaulttakerSig, defaultPermit);
        userProxy.toRFQv2(payload);
    }

    function testCannotFillRFQByIncorrectTakerSig() public {
        RFQOrder memory rfqOrder = RFQOrder({ offer: defaultOffer, recipient: payable(defaultOffer.taker), feeFactor: defaultFeeFactor });
        uint256 randomPrivateKey = 5677;
        bytes memory randomSig = _signRFQOrder(randomPrivateKey, rfqOrder);

        vm.expectRevert("invalid signature");
        bytes memory payload = _genFillRFQPayload(rfqOrder, defaultMakerSig, defaultPermit, randomSig, defaultPermit);
        userProxy.toRFQv2(payload);
    }

    function testCannotFillWithInvalidFeeFactor() public {
        RFQOrder memory newRFQOrder = RFQOrder({ offer: defaultOffer, recipient: payable(defaultOffer.taker), feeFactor: LibConstant.BPS_MAX + 1 });
        bytes memory takerSig = _signRFQOrder(takerPrivateKey, newRFQOrder);

        vm.expectRevert("invalid fee factor");
        bytes memory payload = _genFillRFQPayload(newRFQOrder, defaultMakerSig, defaultPermit, takerSig, defaultPermit);
        userProxy.toRFQv2(payload);
    }

    function _signOffer(uint256 _privateKey, Offer memory _offer) private view returns (bytes memory sig) {
        bytes32 offerHash = getOfferHash(_offer);
        bytes32 EIP712SignDigest = getEIP712Hash(rfq.EIP712_DOMAIN_SEPARATOR(), offerHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, EIP712SignDigest);
        return abi.encodePacked(r, s, v);
    }

    function _signRFQOrder(uint256 _privateKey, RFQOrder memory _rfqOrder) private view returns (bytes memory sig) {
        (, bytes32 rfqOrderHash) = getRFQOrderHash(_rfqOrder);
        bytes32 EIP712SignDigest = getEIP712Hash(rfq.EIP712_DOMAIN_SEPARATOR(), rfqOrderHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, EIP712SignDigest);
        return abi.encodePacked(r, s, v);
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
