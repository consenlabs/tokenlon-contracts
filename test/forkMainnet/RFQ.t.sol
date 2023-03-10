// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";
import { Tokens } from "test/utils/Tokens.sol";
import { BalanceUtil } from "test/utils/BalanceUtil.sol";
import { getEIP712Hash } from "test/utils/Sig.sol";
import { RFQ } from "contracts/RFQ.sol";
import { IRFQ } from "contracts/interfaces/IRFQ.sol";
import { IWETH } from "contracts/interfaces/IWeth.sol";
import { TokenCollector } from "contracts/abstracts/TokenCollector.sol";
import { Order, getOrderHash } from "contracts/libraries/Order.sol";
import { Constant } from "contracts/libraries/Constant.sol";

contract RFQTest is Test, Tokens, BalanceUtil {
    event FilledRFQ(
        bytes32 indexed rfqOrderHash,
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
    IRFQ.RFQOrder defaultRFQOrder;
    RFQ rfq;

    function setUp() public {
        rfq = new RFQ(rfqOwner, UNISWAP_PERMIT2_ADDRESS, IWETH(WETH_ADDRESS), feeCollector);

        deal(maker, 100 ether);
        setEOABalanceAndApprove(maker, address(rfq), tokens, 100000);
        deal(taker, 100 ether);
        setEOABalanceAndApprove(taker, address(rfq), tokens, 100000);
        defaultPermit = abi.encode(TokenCollector.Source.Token, bytes(""));

        defaultRFQOrder = IRFQ.RFQOrder({
            order: Order({
                taker: taker,
                maker: maker,
                takerToken: USDT_ADDRESS,
                takerTokenAmount: 10 * 1e6,
                makerToken: LON_ADDRESS,
                makerTokenAmount: 10,
                minMakerTokenAmount: 10,
                recipient: recipient,
                expiry: defaultExpiry,
                salt: defaultSalt
            }),
            feeFactor: defaultFeeFactor
        });

        defaultMakerSig = _signRFQOrder(makerPrivateKey, defaultRFQOrder);

        vm.label(taker, "taker");
        vm.label(maker, "maker");
        vm.label(address(rfq), "rfq");
    }

    function testFillRFQ() public {
        Order memory _order = defaultRFQOrder.order;
        uint256 fee = (_order.makerTokenAmount * defaultRFQOrder.feeFactor) / Constant.BPS_MAX;
        uint256 amountAfterFee = _order.makerTokenAmount - fee;
        vm.expectEmit(true, true, true, true);
        emit FilledRFQ(
            _getRFQOrderHash(defaultRFQOrder),
            _order.taker,
            _order.maker,
            _order.takerToken,
            _order.takerTokenAmount,
            _order.makerToken,
            _order.makerTokenAmount,
            _order.recipient,
            amountAfterFee,
            defaultRFQOrder.feeFactor
        );

        vm.prank(_order.taker);
        rfq.fillRFQ(defaultRFQOrder, defaultMakerSig, defaultPermit, defaultPermit);
    }

    function testCannotFillExpiredRFQOrder() public {
        vm.warp(defaultRFQOrder.order.expiry + 1);

        vm.expectRevert(IRFQ.ExpiredOrder.selector);
        vm.prank(defaultRFQOrder.order.taker);
        rfq.fillRFQ(defaultRFQOrder, defaultMakerSig, defaultPermit, defaultPermit);
    }

    function testCannotFillWithInvalidFeeFactor() public {
        IRFQ.RFQOrder memory newRFQOrder = defaultRFQOrder;
        newRFQOrder.feeFactor = Constant.BPS_MAX + 1;
        bytes memory newMakerSig = _signRFQOrder(makerPrivateKey, newRFQOrder);

        vm.expectRevert(IRFQ.InvalidFeeFactor.selector);
        vm.prank(newRFQOrder.order.taker);
        rfq.fillRFQ(newRFQOrder, newMakerSig, defaultPermit, defaultPermit);
    }

    function testCannotFillAlreadyFillRFQOrder() public {
        vm.prank(defaultRFQOrder.order.taker);
        rfq.fillRFQ(defaultRFQOrder, defaultMakerSig, defaultPermit, defaultPermit);

        vm.expectRevert(IRFQ.FilledOrder.selector);
        vm.prank(defaultRFQOrder.order.taker);
        rfq.fillRFQ(defaultRFQOrder, defaultMakerSig, defaultPermit, defaultPermit);
    }

    function testFillRFQByTakerSig() public {
        bytes memory takerSig = _signRFQOrder(takerPrivateKey, defaultRFQOrder);

        address claimedTaker = defaultRFQOrder.order.taker;
        rfq.fillRFQ(defaultRFQOrder, defaultMakerSig, defaultPermit, defaultPermit, takerSig, claimedTaker);
    }

    function testCannotFillRFQByIncorrectTakerSig() public {
        uint256 randomPrivateKey = 5677;
        bytes memory randomSig = _signRFQOrder(randomPrivateKey, defaultRFQOrder);

        vm.expectRevert(IRFQ.InvalidSignature.selector);
        address claimedTaker = defaultRFQOrder.order.taker;
        rfq.fillRFQ(defaultRFQOrder, defaultMakerSig, defaultPermit, defaultPermit, randomSig, claimedTaker);
    }

    function _signRFQOrder(uint256 _privateKey, IRFQ.RFQOrder memory _rfqOrder) internal view returns (bytes memory sig) {
        bytes32 rfqOrderHash = _getRFQOrderHash(_rfqOrder);
        bytes32 EIP712SignDigest = getEIP712Hash(rfq.EIP712_DOMAIN_SEPARATOR(), rfqOrderHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, EIP712SignDigest);
        return abi.encodePacked(r, s, v);
    }

    function _getRFQOrderHash(IRFQ.RFQOrder memory rfqOrder) private view returns (bytes32) {
        bytes32 orderHash = getOrderHash(rfqOrder.order);
        return keccak256(abi.encode(rfq.RFQ_ORDER_TYPEHASH(), orderHash, rfqOrder.feeFactor));
    }
}
