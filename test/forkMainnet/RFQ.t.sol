// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";
import { Tokens } from "test/utils/Tokens.sol";
import { BalanceUtil } from "test/utils/BalanceUtil.sol";
import { BalanceSnapshot, Snapshot } from "test/utils/BalanceSnapshot.sol";
import { getEIP712Hash } from "test/utils/Sig.sol";
import { MockERC1271Wallet } from "test/mocks/MockERC1271Wallet.sol";
import { computeContractAddress } from "test/utils/Addresses.sol";
import { Permit2Helper } from "test/utils/Permit2Helper.sol";
import { RFQ } from "contracts/RFQ.sol";
import { AllowanceTarget } from "contracts/AllowanceTarget.sol";
import { IRFQ } from "contracts/interfaces/IRFQ.sol";
import { IWETH } from "contracts/interfaces/IWETH.sol";
import { IUniswapPermit2 } from "contracts/interfaces/IUniswapPermit2.sol";
import { TokenCollector } from "contracts/abstracts/TokenCollector.sol";
import { RFQOffer, getRFQOfferHash } from "contracts/libraries/RFQOffer.sol";
import { RFQTx, getRFQTxHash } from "contracts/libraries/RFQTx.sol";
import { Constant } from "contracts/libraries/Constant.sol";

contract RFQTest is Test, Tokens, BalanceUtil, Permit2Helper {
    using BalanceSnapshot for Snapshot;

    uint256 private constant FLG_ALLOW_CONTRACT_SENDER = 1 << 255;
    uint256 private constant FLG_ALLOW_PARTIAL_FILL = 1 << 254;

    event FilledRFQ(
        bytes32 indexed rfqOfferHash,
        address indexed user,
        address indexed maker,
        address takerToken,
        uint256 takerTokenUserAmount,
        address makerToken,
        uint256 makerTokenUserAmount,
        address recipient,
        uint256 fee
    );
    event SetFeeCollector(address newFeeCollector);
    event CancelRFQOffer(bytes32 indexed rfqOfferHash, address indexed maker);

    address rfqOwner = makeAddr("rfqOwner");
    address allowanceTargetOwner = makeAddr("allowanceTargetOwner");
    uint256 makerSignerPrivateKey = uint256(9021);
    address makerSigner = vm.addr(makerSignerPrivateKey);
    address payable maker = payable(address(new MockERC1271Wallet(makerSigner)));
    uint256 takerPrivateKey = uint256(9022);
    address taker = vm.addr(takerPrivateKey);
    address takerWalletContract = address(new MockERC1271Wallet(taker));
    address payable recipient = payable(makeAddr("recipient"));
    address payable feeCollector = payable(makeAddr("feeCollector"));
    address txRelayer = makeAddr("txRelayer");
    uint256 defaultExpiry = block.timestamp + 1;
    uint256 defaultSalt = 1234;
    uint256 defaultFeeFactor = 100;
    bytes defaultMakerPermit = abi.encodePacked(TokenCollector.Source.Token);
    bytes defaultTakerPermit;
    bytes defaultMakerSig;
    RFQOffer defaultRFQOffer;
    RFQTx defaultRFQTx;
    RFQ rfq;
    AllowanceTarget allowanceTarget;

    function setUp() public {
        // deploy allowance target
        address[] memory trusted = new address[](1);
        // pre-compute RFQ address since the whitelist of allowance target is immutable
        // NOTE: this assumes RFQ is deployed right next to Allowance Target
        trusted[0] = computeContractAddress(address(this), uint8(vm.getNonce(address(this)) + 1));
        allowanceTarget = new AllowanceTarget(allowanceTargetOwner, trusted);

        rfq = new RFQ(rfqOwner, UNISWAP_PERMIT2_ADDRESS, address(allowanceTarget), IWETH(WETH_ADDRESS), feeCollector);

        deal(maker, 100 ether);
        setTokenBalanceAndApprove(maker, address(rfq), tokens, 100000);
        deal(taker, 100 ether);
        setTokenBalanceAndApprove(taker, UNISWAP_PERMIT2_ADDRESS, tokens, 100000);
        deal(takerWalletContract, 100 ether);
        setTokenBalanceAndApprove(takerWalletContract, UNISWAP_PERMIT2_ADDRESS, tokens, 100000);

        defaultRFQOffer = RFQOffer({
            taker: taker,
            maker: maker,
            takerToken: USDT_ADDRESS,
            takerTokenAmount: 10 * 1e6,
            makerToken: LON_ADDRESS,
            makerTokenAmount: 1000 ether,
            feeFactor: defaultFeeFactor,
            flags: 0,
            expiry: defaultExpiry,
            salt: defaultSalt
        });
        defaultRFQTx = RFQTx({ rfqOffer: defaultRFQOffer, takerRequestAmount: defaultRFQOffer.takerTokenAmount, recipient: payable(recipient) });

        defaultMakerSig = _signRFQOffer(makerSignerPrivateKey, defaultRFQOffer);

        defaultTakerPermit = getTokenlonPermit2Data(taker, takerPrivateKey, defaultRFQOffer.takerToken, address(rfq));

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
        Snapshot memory takerTakerToken = BalanceSnapshot.take({ owner: defaultRFQOffer.taker, token: defaultRFQOffer.takerToken });
        Snapshot memory takerMakerToken = BalanceSnapshot.take({ owner: defaultRFQOffer.taker, token: defaultRFQOffer.makerToken });
        Snapshot memory makerTakerToken = BalanceSnapshot.take({ owner: defaultRFQOffer.maker, token: defaultRFQOffer.takerToken });
        Snapshot memory makerMakerToken = BalanceSnapshot.take({ owner: defaultRFQOffer.maker, token: defaultRFQOffer.makerToken });
        Snapshot memory recTakerToken = BalanceSnapshot.take({ owner: recipient, token: defaultRFQOffer.takerToken });
        Snapshot memory recMakerToken = BalanceSnapshot.take({ owner: recipient, token: defaultRFQOffer.makerToken });
        Snapshot memory fcMakerToken = BalanceSnapshot.take({ owner: feeCollector, token: defaultRFQOffer.makerToken });

        uint256 fee = (defaultRFQOffer.makerTokenAmount * defaultFeeFactor) / Constant.BPS_MAX;
        uint256 amountAfterFee = defaultRFQOffer.makerTokenAmount - fee;
        vm.expectEmit(true, true, true, true);
        emit FilledRFQ(
            getRFQOfferHash(defaultRFQOffer),
            defaultRFQOffer.taker,
            defaultRFQOffer.maker,
            defaultRFQOffer.takerToken,
            defaultRFQOffer.takerTokenAmount,
            defaultRFQOffer.makerToken,
            amountAfterFee,
            recipient,
            fee
        );

        vm.prank(defaultRFQOffer.taker, defaultRFQOffer.taker);
        rfq.fillRFQ(defaultRFQTx, defaultMakerSig, defaultMakerPermit, defaultTakerPermit);
        takerTakerToken.assertChange(-int256(defaultRFQOffer.takerTokenAmount));
        takerMakerToken.assertChange(int256(0));
        makerTakerToken.assertChange(int256(defaultRFQOffer.takerTokenAmount));
        makerMakerToken.assertChange(-int256(defaultRFQOffer.makerTokenAmount));
        recTakerToken.assertChange(int256(0));
        // recipient gets less than original makerTokenAmount because of the fee
        recMakerToken.assertChange(int256(amountAfterFee));
        fcMakerToken.assertChange(int256(fee));
    }

    function testFillRFQWithTakerApproveAllowanceTarget() public {
        setTokenBalanceAndApprove(taker, address(allowanceTarget), tokens, 100000);

        bytes memory takerPermit = abi.encodePacked(TokenCollector.Source.TokenlonAllowanceTarget);

        vm.prank(defaultRFQOffer.taker, defaultRFQOffer.taker);
        rfq.fillRFQ(defaultRFQTx, defaultMakerSig, defaultMakerPermit, takerPermit);
    }

    function testFillRFQWithZeroFee() public {
        Snapshot memory takerTakerToken = BalanceSnapshot.take({ owner: defaultRFQOffer.taker, token: defaultRFQOffer.takerToken });
        Snapshot memory takerMakerToken = BalanceSnapshot.take({ owner: defaultRFQOffer.taker, token: defaultRFQOffer.makerToken });
        Snapshot memory makerTakerToken = BalanceSnapshot.take({ owner: defaultRFQOffer.maker, token: defaultRFQOffer.takerToken });
        Snapshot memory makerMakerToken = BalanceSnapshot.take({ owner: defaultRFQOffer.maker, token: defaultRFQOffer.makerToken });
        Snapshot memory recTakerToken = BalanceSnapshot.take({ owner: recipient, token: defaultRFQOffer.takerToken });
        Snapshot memory recMakerToken = BalanceSnapshot.take({ owner: recipient, token: defaultRFQOffer.makerToken });

        RFQOffer memory rfqOffer = defaultRFQOffer;
        rfqOffer.feeFactor = 0;
        RFQTx memory rfqTx = defaultRFQTx;
        rfqTx.rfqOffer = rfqOffer;
        bytes memory makerSig = _signRFQOffer(makerSignerPrivateKey, rfqTx.rfqOffer);

        vm.expectEmit(true, true, true, true);
        emit FilledRFQ(
            getRFQOfferHash(rfqOffer),
            defaultRFQOffer.taker,
            defaultRFQOffer.maker,
            defaultRFQOffer.takerToken,
            defaultRFQOffer.takerTokenAmount,
            defaultRFQOffer.makerToken,
            defaultRFQOffer.makerTokenAmount,
            recipient,
            0
        );

        vm.prank(defaultRFQOffer.taker, defaultRFQOffer.taker);
        rfq.fillRFQ(rfqTx, makerSig, defaultMakerPermit, defaultTakerPermit);

        takerTakerToken.assertChange(-int256(defaultRFQOffer.takerTokenAmount));
        takerMakerToken.assertChange(int256(0));
        makerTakerToken.assertChange(int256(defaultRFQOffer.takerTokenAmount));
        makerMakerToken.assertChange(-int256(defaultRFQOffer.makerTokenAmount));
        recTakerToken.assertChange(int256(0));
        recMakerToken.assertChange(int256(defaultRFQOffer.makerTokenAmount));
    }

    function testFillRFQWithRawETH() public {
        // case : taker token is ETH
        RFQOffer memory rfqOffer = defaultRFQOffer;
        rfqOffer.takerToken = Constant.ZERO_ADDRESS;
        rfqOffer.takerTokenAmount = 1 ether;

        bytes memory makerSig = _signRFQOffer(makerSignerPrivateKey, rfqOffer);

        Snapshot memory takerTakerToken = BalanceSnapshot.take({ owner: rfqOffer.taker, token: rfqOffer.takerToken });
        Snapshot memory takerMakerToken = BalanceSnapshot.take({ owner: rfqOffer.taker, token: rfqOffer.makerToken });
        Snapshot memory makerTakerToken = BalanceSnapshot.take({ owner: rfqOffer.maker, token: rfqOffer.takerToken });
        Snapshot memory makerMakerToken = BalanceSnapshot.take({ owner: rfqOffer.maker, token: rfqOffer.makerToken });
        Snapshot memory recTakerToken = BalanceSnapshot.take({ owner: recipient, token: rfqOffer.takerToken });
        Snapshot memory recMakerToken = BalanceSnapshot.take({ owner: recipient, token: rfqOffer.makerToken });
        Snapshot memory fcMakerToken = BalanceSnapshot.take({ owner: feeCollector, token: rfqOffer.makerToken });

        uint256 fee = (rfqOffer.makerTokenAmount * defaultFeeFactor) / Constant.BPS_MAX;
        uint256 amountAfterFee = rfqOffer.makerTokenAmount - fee;

        RFQTx memory rfqTx = defaultRFQTx;
        rfqTx.rfqOffer = rfqOffer;
        rfqTx.takerRequestAmount = rfqOffer.takerTokenAmount;

        vm.prank(rfqOffer.taker, rfqOffer.taker);
        rfq.fillRFQ{ value: rfqOffer.takerTokenAmount }(rfqTx, makerSig, defaultMakerPermit, defaultTakerPermit);

        takerTakerToken.assertChange(-int256(rfqOffer.takerTokenAmount));
        takerMakerToken.assertChange(int256(0));
        makerTakerToken.assertChange(int256(rfqOffer.takerTokenAmount));
        makerMakerToken.assertChange(-int256(rfqOffer.makerTokenAmount));
        recTakerToken.assertChange(int256(0));
        // recipient gets less than original makerTokenAmount because of the fee
        recMakerToken.assertChange(int256(amountAfterFee));
        fcMakerToken.assertChange(int256(fee));
    }

    function testFillRFQTakerGetRawETH() public {
        // case : maker token is WETH
        RFQOffer memory rfqOffer = defaultRFQOffer;
        rfqOffer.makerToken = WETH_ADDRESS;
        rfqOffer.makerTokenAmount = 1 ether;

        bytes memory makerSig = _signRFQOffer(makerSignerPrivateKey, rfqOffer);

        Snapshot memory takerTakerToken = BalanceSnapshot.take({ owner: rfqOffer.taker, token: rfqOffer.takerToken });
        Snapshot memory takerMakerToken = BalanceSnapshot.take({ owner: rfqOffer.taker, token: rfqOffer.makerToken });
        Snapshot memory makerTakerToken = BalanceSnapshot.take({ owner: rfqOffer.maker, token: rfqOffer.takerToken });
        Snapshot memory makerMakerToken = BalanceSnapshot.take({ owner: rfqOffer.maker, token: rfqOffer.makerToken });
        // recipient should receive raw ETH
        Snapshot memory recTakerToken = BalanceSnapshot.take({ owner: recipient, token: rfqOffer.takerToken });
        Snapshot memory recMakerToken = BalanceSnapshot.take({ owner: recipient, token: Constant.ZERO_ADDRESS });
        Snapshot memory fcMakerToken = BalanceSnapshot.take({ owner: feeCollector, token: Constant.ZERO_ADDRESS });

        uint256 fee = (rfqOffer.makerTokenAmount * defaultFeeFactor) / Constant.BPS_MAX;
        uint256 amountAfterFee = rfqOffer.makerTokenAmount - fee;

        RFQTx memory rfqTx = defaultRFQTx;
        rfqTx.rfqOffer = rfqOffer;

        vm.prank(rfqOffer.taker, rfqOffer.taker);
        rfq.fillRFQ(rfqTx, makerSig, defaultMakerPermit, defaultTakerPermit);

        takerTakerToken.assertChange(-int256(rfqOffer.takerTokenAmount));
        takerMakerToken.assertChange(int256(0));
        makerTakerToken.assertChange(int256(rfqOffer.takerTokenAmount));
        makerMakerToken.assertChange(-int256(rfqOffer.makerTokenAmount));
        recTakerToken.assertChange(int256(0));
        // recipient gets less than original makerTokenAmount because of the fee
        recMakerToken.assertChange(int256(amountAfterFee));
        fcMakerToken.assertChange(int256(fee));
    }

    function testFillRFQWithWETH() public {
        // case : taker token is WETH
        RFQOffer memory rfqOffer = defaultRFQOffer;
        rfqOffer.takerToken = WETH_ADDRESS;
        rfqOffer.takerTokenAmount = 1 ether;

        bytes memory makerSig = _signRFQOffer(makerSignerPrivateKey, rfqOffer);

        Snapshot memory takerTakerToken = BalanceSnapshot.take({ owner: rfqOffer.taker, token: rfqOffer.takerToken });
        Snapshot memory takerMakerToken = BalanceSnapshot.take({ owner: rfqOffer.taker, token: rfqOffer.makerToken });
        // maker should receive raw ETH
        Snapshot memory makerTakerToken = BalanceSnapshot.take({ owner: rfqOffer.maker, token: Constant.ZERO_ADDRESS });
        Snapshot memory makerMakerToken = BalanceSnapshot.take({ owner: rfqOffer.maker, token: rfqOffer.makerToken });
        Snapshot memory recTakerToken = BalanceSnapshot.take({ owner: recipient, token: rfqOffer.takerToken });
        Snapshot memory recMakerToken = BalanceSnapshot.take({ owner: recipient, token: rfqOffer.makerToken });
        Snapshot memory fcMakerToken = BalanceSnapshot.take({ owner: feeCollector, token: rfqOffer.makerToken });

        uint256 fee = (rfqOffer.makerTokenAmount * defaultFeeFactor) / Constant.BPS_MAX;
        uint256 amountAfterFee = rfqOffer.makerTokenAmount - fee;

        RFQTx memory rfqTx = defaultRFQTx;
        rfqTx.rfqOffer = rfqOffer;
        rfqTx.takerRequestAmount = rfqOffer.takerTokenAmount;

        bytes memory takerPermit = getTokenlonPermit2Data(taker, takerPrivateKey, rfqOffer.takerToken, address(rfq));

        vm.prank(rfqOffer.taker, rfqOffer.taker);
        rfq.fillRFQ(rfqTx, makerSig, defaultMakerPermit, takerPermit);

        takerTakerToken.assertChange(-int256(rfqOffer.takerTokenAmount));
        takerMakerToken.assertChange(int256(0));
        makerTakerToken.assertChange(int256(rfqOffer.takerTokenAmount));
        makerMakerToken.assertChange(-int256(rfqOffer.makerTokenAmount));
        recTakerToken.assertChange(int256(0));
        recMakerToken.assertChange(int256(amountAfterFee));
        fcMakerToken.assertChange(int256(fee));
    }

    function testFillWithContract() public {
        RFQOffer memory rfqOffer = defaultRFQOffer;
        rfqOffer.flags |= FLG_ALLOW_CONTRACT_SENDER;
        rfqOffer.taker = takerWalletContract;
        bytes memory makerSig = _signRFQOffer(makerSignerPrivateKey, rfqOffer);

        RFQTx memory rfqTx = defaultRFQTx;
        rfqTx.rfqOffer = rfqOffer;

        // the owner should be takerWalletContract but the signer is taker
        // permit2 will validate sig using EIP-1271
        bytes memory takerPermit = getTokenlonPermit2Data(takerWalletContract, takerPrivateKey, defaultRFQOffer.takerToken, address(rfq));

        // tx.origin is an EOA, msg.sender is a contract
        vm.prank(takerWalletContract, makeAddr("anyAddr"));
        rfq.fillRFQ(rfqTx, makerSig, defaultMakerPermit, takerPermit);
    }

    function testPartialFill() public {
        RFQOffer memory rfqOffer = defaultRFQOffer;
        rfqOffer.flags |= FLG_ALLOW_PARTIAL_FILL;

        bytes memory makerSig = _signRFQOffer(makerSignerPrivateKey, rfqOffer);

        Snapshot memory takerTakerToken = BalanceSnapshot.take({ owner: rfqOffer.taker, token: rfqOffer.takerToken });
        Snapshot memory takerMakerToken = BalanceSnapshot.take({ owner: rfqOffer.taker, token: rfqOffer.makerToken });
        Snapshot memory makerTakerToken = BalanceSnapshot.take({ owner: rfqOffer.maker, token: rfqOffer.takerToken });
        Snapshot memory makerMakerToken = BalanceSnapshot.take({ owner: rfqOffer.maker, token: rfqOffer.makerToken });
        Snapshot memory recTakerToken = BalanceSnapshot.take({ owner: recipient, token: rfqOffer.takerToken });
        Snapshot memory recMakerToken = BalanceSnapshot.take({ owner: recipient, token: rfqOffer.makerToken });
        Snapshot memory fcMakerToken = BalanceSnapshot.take({ owner: feeCollector, token: rfqOffer.makerToken });

        RFQTx memory rfqTx = defaultRFQTx;
        rfqTx.rfqOffer = rfqOffer;
        rfqTx.takerRequestAmount = rfqOffer.takerTokenAmount / 2;

        vm.prank(rfqOffer.taker, rfqOffer.taker);
        rfq.fillRFQ(rfqTx, makerSig, defaultMakerPermit, defaultTakerPermit);

        {
            uint256 makerActualAmount = rfqOffer.makerTokenAmount / 2;
            uint256 fee = (makerActualAmount * defaultFeeFactor) / Constant.BPS_MAX;
            uint256 amountAfterFee = makerActualAmount - fee;

            takerTakerToken.assertChange(-int256(rfqTx.takerRequestAmount));
            takerMakerToken.assertChange(int256(0));
            makerTakerToken.assertChange(int256(rfqTx.takerRequestAmount));
            makerMakerToken.assertChange(-int256(makerActualAmount));
            recTakerToken.assertChange(int256(0));
            recMakerToken.assertChange(int256(amountAfterFee));
            fcMakerToken.assertChange(int256(fee));
        }
    }

    function testCannotPartialFillWithDisallowedOffer() public {
        RFQTx memory rfqTx = defaultRFQTx;
        rfqTx.takerRequestAmount = defaultRFQOffer.takerTokenAmount / 2;

        vm.expectRevert(IRFQ.ForbidPartialFill.selector);
        vm.prank(defaultRFQOffer.taker, defaultRFQOffer.taker);
        rfq.fillRFQ(rfqTx, defaultMakerSig, defaultMakerPermit, defaultTakerPermit);
    }

    function testCannotPartialFillWithInvalidAmount() public {
        RFQOffer memory rfqOffer = defaultRFQOffer;
        rfqOffer.flags |= FLG_ALLOW_PARTIAL_FILL;

        bytes memory makerSig = _signRFQOffer(makerSignerPrivateKey, rfqOffer);

        // case : takerRequestAmount > offer.takerTokenAmount
        RFQTx memory rfqTx = defaultRFQTx;
        rfqTx.rfqOffer = rfqOffer;
        rfqTx.takerRequestAmount = defaultRFQOffer.takerTokenAmount * 2;
        vm.expectRevert(IRFQ.InvalidTakerAmount.selector);
        vm.prank(rfqOffer.taker, rfqOffer.taker);
        rfq.fillRFQ(rfqTx, makerSig, defaultMakerPermit, defaultTakerPermit);

        // case : takerRequestAmount = 0
        RFQTx memory rfqTx1 = defaultRFQTx;
        rfqTx1.rfqOffer = rfqOffer;
        rfqTx1.takerRequestAmount = 0;
        vm.expectRevert(IRFQ.InvalidTakerAmount.selector);
        vm.prank(rfqOffer.taker, rfqOffer.taker);
        rfq.fillRFQ(rfqTx1, makerSig, defaultMakerPermit, defaultTakerPermit);
    }

    function testCannotFillExpiredRFQTx() public {
        vm.warp(defaultRFQOffer.expiry + 1);

        vm.expectRevert(IRFQ.ExpiredRFQOffer.selector);
        vm.prank(defaultRFQOffer.taker, defaultRFQOffer.taker);
        rfq.fillRFQ(defaultRFQTx, defaultMakerSig, defaultMakerPermit, defaultTakerPermit);
    }

    function testCannotFillAlreadyFillRFQTx() public {
        vm.prank(defaultRFQOffer.taker, defaultRFQOffer.taker);
        rfq.fillRFQ(defaultRFQTx, defaultMakerSig, defaultMakerPermit, defaultTakerPermit);

        vm.expectRevert(IRFQ.FilledRFQOffer.selector);
        vm.prank(defaultRFQOffer.taker, defaultRFQOffer.taker);
        rfq.fillRFQ(defaultRFQTx, defaultMakerSig, defaultMakerPermit, defaultTakerPermit);
    }

    function testCannotFillRFQWithIncorrectMakerSig() public {
        uint256 randomPrivateKey = 5677;
        bytes memory randomMakerSig = _signRFQOffer(randomPrivateKey, defaultRFQOffer);

        vm.expectRevert(IRFQ.InvalidSignature.selector);
        vm.prank(defaultRFQOffer.taker, defaultRFQOffer.taker);
        rfq.fillRFQ(defaultRFQTx, randomMakerSig, defaultMakerPermit, defaultTakerPermit);
    }

    function testCannotFillWithZeroRecipient() public {
        RFQTx memory rfqTx = defaultRFQTx;
        rfqTx.recipient = payable(address(0));

        vm.expectRevert(IRFQ.ZeroAddress.selector);
        vm.prank(defaultRFQOffer.taker, defaultRFQOffer.taker);
        rfq.fillRFQ(rfqTx, defaultMakerSig, defaultMakerPermit, defaultTakerPermit);
    }

    function testCannotFillWithIncorrectMsgValue() public {
        // case : takerToken is normal ERC20
        vm.prank(defaultRFQOffer.taker, defaultRFQOffer.taker);
        vm.expectRevert(IRFQ.InvalidMsgValue.selector);
        rfq.fillRFQ{ value: 1 ether }(defaultRFQTx, defaultMakerSig, defaultMakerPermit, defaultTakerPermit);

        // case : takerToken is WETH
        RFQOffer memory rfqOffer = defaultRFQOffer;
        rfqOffer.takerToken = WETH_ADDRESS;
        rfqOffer.takerTokenAmount = 1 ether;
        RFQTx memory rfqTx = defaultRFQTx;
        rfqTx.rfqOffer = rfqOffer;
        rfqTx.takerRequestAmount = rfqOffer.takerTokenAmount;
        bytes memory makerSig = _signRFQOffer(makerSignerPrivateKey, rfqOffer);

        vm.prank(defaultRFQOffer.taker, defaultRFQOffer.taker);
        vm.expectRevert(IRFQ.InvalidMsgValue.selector);
        rfq.fillRFQ{ value: 2 ether }(rfqTx, makerSig, defaultMakerPermit, defaultTakerPermit);

        // case : takerToken is raw ETH
        RFQOffer memory rfqOffer1 = defaultRFQOffer;
        rfqOffer1.takerToken = Constant.ZERO_ADDRESS;
        rfqOffer1.takerTokenAmount = 1 ether;
        RFQTx memory rfqTx1 = defaultRFQTx;
        rfqTx1.rfqOffer = rfqOffer1;
        rfqTx1.takerRequestAmount = rfqOffer1.takerTokenAmount;
        bytes memory makerSig1 = _signRFQOffer(makerSignerPrivateKey, rfqOffer1);

        vm.prank(defaultRFQOffer.taker, defaultRFQOffer.taker);
        vm.expectRevert(IRFQ.InvalidMsgValue.selector);
        rfq.fillRFQ{ value: 2 ether }(rfqTx1, makerSig1, defaultMakerPermit, defaultTakerPermit);
    }

    function testFillRFQByTakerSig() public {
        Snapshot memory takerTakerToken = BalanceSnapshot.take({ owner: defaultRFQOffer.taker, token: defaultRFQOffer.takerToken });
        Snapshot memory takerMakerToken = BalanceSnapshot.take({ owner: defaultRFQOffer.taker, token: defaultRFQOffer.makerToken });
        Snapshot memory makerTakerToken = BalanceSnapshot.take({ owner: defaultRFQOffer.maker, token: defaultRFQOffer.takerToken });
        Snapshot memory makerMakerToken = BalanceSnapshot.take({ owner: defaultRFQOffer.maker, token: defaultRFQOffer.makerToken });
        Snapshot memory recTakerToken = BalanceSnapshot.take({ owner: recipient, token: defaultRFQOffer.takerToken });
        Snapshot memory recMakerToken = BalanceSnapshot.take({ owner: recipient, token: defaultRFQOffer.makerToken });
        Snapshot memory fcMakerToken = BalanceSnapshot.take({ owner: feeCollector, token: defaultRFQOffer.makerToken });

        bytes memory takerSig = _signRFQTx(takerPrivateKey, defaultRFQTx);

        uint256 fee = (defaultRFQOffer.makerTokenAmount * defaultFeeFactor) / Constant.BPS_MAX;
        uint256 amountAfterFee = defaultRFQOffer.makerTokenAmount - fee;
        vm.expectEmit(true, true, true, true);
        emit FilledRFQ(
            getRFQOfferHash(defaultRFQOffer),
            defaultRFQOffer.taker,
            defaultRFQOffer.maker,
            defaultRFQOffer.takerToken,
            defaultRFQOffer.takerTokenAmount,
            defaultRFQOffer.makerToken,
            amountAfterFee,
            recipient,
            fee
        );

        vm.prank(txRelayer, txRelayer);
        rfq.fillRFQ(defaultRFQTx, defaultMakerSig, defaultMakerPermit, defaultTakerPermit, takerSig);

        takerTakerToken.assertChange(-int256(defaultRFQOffer.takerTokenAmount));
        takerMakerToken.assertChange(int256(0));
        makerTakerToken.assertChange(int256(defaultRFQOffer.takerTokenAmount));
        makerMakerToken.assertChange(-int256(defaultRFQOffer.makerTokenAmount));
        recTakerToken.assertChange(int256(0));
        // recipient gets less than original makerTokenAmount because of the fee
        recMakerToken.assertChange(int256(amountAfterFee));
        fcMakerToken.assertChange(int256(fee));
    }

    function testCannotFillRFQByIncorrectTakerSig() public {
        uint256 randomPrivateKey = 5677;
        bytes memory randomSig = _signRFQTx(randomPrivateKey, defaultRFQTx);

        vm.expectRevert(IRFQ.InvalidSignature.selector);
        vm.prank(txRelayer, txRelayer);
        rfq.fillRFQ(defaultRFQTx, defaultMakerSig, defaultMakerPermit, defaultTakerPermit, randomSig);
    }

    function testCannotFillWithInvalidFeeFactor() public {
        RFQTx memory rfqTx = defaultRFQTx;
        rfqTx.rfqOffer.feeFactor = Constant.BPS_MAX + 1;
        bytes memory takerSig = _signRFQTx(takerPrivateKey, rfqTx);

        vm.expectRevert(IRFQ.InvalidFeeFactor.selector);
        vm.prank(txRelayer, txRelayer);
        rfq.fillRFQ(rfqTx, defaultMakerSig, defaultMakerPermit, defaultTakerPermit, takerSig);
    }

    function testCannotFillIfMakerAmountIsZero() public {
        // create an offer with an extreme exchange ratio
        RFQOffer memory rfqOffer = RFQOffer({
            taker: taker,
            maker: maker,
            takerToken: USDT_ADDRESS,
            takerTokenAmount: 100000 * 1e6,
            makerToken: LON_ADDRESS,
            makerTokenAmount: 100,
            feeFactor: defaultFeeFactor,
            flags: FLG_ALLOW_PARTIAL_FILL,
            expiry: defaultExpiry,
            salt: defaultSalt
        });
        RFQTx memory rfqTx = RFQTx({ rfqOffer: rfqOffer, takerRequestAmount: 1, recipient: payable(recipient) });
        bytes memory makerSig = _signRFQOffer(makerSignerPrivateKey, rfqOffer);

        vm.prank(rfqOffer.taker, rfqOffer.taker);
        vm.expectRevert(IRFQ.InvalidMakerAmount.selector);
        rfq.fillRFQ(rfqTx, makerSig, defaultMakerPermit, defaultTakerPermit);
    }

    function testCancelRFQOffer() public {
        vm.prank(defaultRFQOffer.maker, defaultRFQOffer.maker);
        rfq.cancelRFQOffer(defaultRFQOffer);

        emit CancelRFQOffer(getRFQOfferHash(defaultRFQOffer), defaultRFQOffer.maker);
    }

    function testCannotCancelRFQOfferIfNotMaker() public {
        vm.expectRevert(IRFQ.NotOfferMaker.selector);
        rfq.cancelRFQOffer(defaultRFQOffer);
    }

    function testCannotCancelRFQOfferIfFilledOrCancelled() public {
        vm.startPrank(defaultRFQOffer.maker, defaultRFQOffer.maker);
        rfq.cancelRFQOffer(defaultRFQOffer);

        // cannot cancel an offer twice
        vm.expectRevert(IRFQ.FilledRFQOffer.selector);
        rfq.cancelRFQOffer(defaultRFQOffer);

        vm.stopPrank();
    }

    function _signRFQOffer(uint256 _privateKey, RFQOffer memory _rfqOffer) internal view returns (bytes memory sig) {
        bytes32 rfqOfferHash = getRFQOfferHash(_rfqOffer);
        bytes32 EIP712SignDigest = getEIP712Hash(rfq.EIP712_DOMAIN_SEPARATOR(), rfqOfferHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, EIP712SignDigest);
        return abi.encodePacked(r, s, v);
    }

    function _signRFQTx(uint256 _privateKey, RFQTx memory _rfqTx) internal view returns (bytes memory sig) {
        (, bytes32 rfqTxHash) = getRFQTxHash(_rfqTx);
        bytes32 EIP712SignDigest = getEIP712Hash(rfq.EIP712_DOMAIN_SEPARATOR(), rfqTxHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, EIP712SignDigest);
        return abi.encodePacked(r, s, v);
    }
}
