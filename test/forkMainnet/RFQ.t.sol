// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";

import { AllowanceTarget } from "contracts/AllowanceTarget.sol";
import { RFQ } from "contracts/RFQ.sol";
import { Ownable } from "contracts/abstracts/Ownable.sol";
import { TokenCollector } from "contracts/abstracts/TokenCollector.sol";
import { IRFQ } from "contracts/interfaces/IRFQ.sol";
import { IWETH } from "contracts/interfaces/IWETH.sol";
import { Constant } from "contracts/libraries/Constant.sol";
import { RFQOffer, getRFQOfferHash } from "contracts/libraries/RFQOffer.sol";
import { RFQTx } from "contracts/libraries/RFQTx.sol";

import { MockERC1271Wallet } from "test/mocks/MockERC1271Wallet.sol";
import { computeContractAddress } from "test/utils/Addresses.sol";
import { BalanceSnapshot, Snapshot } from "test/utils/BalanceSnapshot.sol";
import { BalanceUtil } from "test/utils/BalanceUtil.sol";
import { Permit2Helper } from "test/utils/Permit2Helper.sol";
import { SigHelper } from "test/utils/SigHelper.sol";
import { Tokens } from "test/utils/Tokens.sol";

contract RFQTest is Test, Tokens, BalanceUtil, Permit2Helper, SigHelper {
    using BalanceSnapshot for Snapshot;

    uint256 private constant FLG_ALLOW_CONTRACT_SENDER = 1 << 255;
    uint256 private constant FLG_ALLOW_PARTIAL_FILL = 1 << 254;
    uint256 private constant FLG_MAKER_RECEIVES_WETH = 1 << 253;

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

        defaultMakerSig = signRFQOffer(makerSignerPrivateKey, defaultRFQOffer, address(rfq));

        defaultTakerPermit = getTokenlonPermit2Data(taker, takerPrivateKey, defaultRFQOffer.takerToken, address(rfq));

        vm.label(taker, "taker");
        vm.label(maker, "maker");
        vm.label(address(rfq), "rfq");
    }

    function testRFQInitialState() public {
        rfq = new RFQ(rfqOwner, UNISWAP_PERMIT2_ADDRESS, address(allowanceTarget), IWETH(WETH_ADDRESS), feeCollector);

        assertEq(rfq.owner(), rfqOwner);
        assertEq(rfq.permit2(), UNISWAP_PERMIT2_ADDRESS);
        assertEq(rfq.allowanceTarget(), address(allowanceTarget));
        assertEq(address(rfq.weth()), WETH_ADDRESS);
        assertEq(rfq.feeCollector(), feeCollector);
    }

    function testCannotNewRFQWithZeroAddressFeeCollector() public {
        vm.expectRevert(IRFQ.ZeroAddress.selector);
        new RFQ(rfqOwner, UNISWAP_PERMIT2_ADDRESS, address(allowanceTarget), IWETH(WETH_ADDRESS), payable(address(0)));
    }

    function testCannotSetFeeCollectorByNotOwner() public {
        address newFeeCollector = makeAddr("newFeeCollector");
        vm.startPrank(newFeeCollector);
        vm.expectRevert(Ownable.NotOwner.selector);
        rfq.setFeeCollector(payable(newFeeCollector));
        vm.stopPrank();
    }

    function testCannotSetFeeCollectorToZero() public {
        vm.startPrank(rfqOwner);
        vm.expectRevert(IRFQ.ZeroAddress.selector);
        rfq.setFeeCollector(payable(address(0)));
        vm.stopPrank();
    }

    function testSetFeeCollector() public {
        address newFeeCollector = makeAddr("newFeeCollector");

        vm.expectEmit(false, false, false, true);
        emit IRFQ.SetFeeCollector(newFeeCollector);

        vm.startPrank(rfqOwner);
        rfq.setFeeCollector(payable(newFeeCollector));
        vm.stopPrank();
        vm.snapshotGasLastCall("RFQ", "setFeeCollector(): testSetFeeCollector");
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
        emit IRFQ.FilledRFQ(
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

        vm.startPrank(defaultRFQOffer.taker, defaultRFQOffer.taker);
        rfq.fillRFQ(defaultRFQTx, defaultMakerSig, defaultMakerPermit, defaultTakerPermit);
        vm.stopPrank();
        vm.snapshotGasLastCall("RFQ", "fillRFQ(): testFillRFQ");

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

        vm.startPrank(defaultRFQOffer.taker, defaultRFQOffer.taker);
        rfq.fillRFQ(defaultRFQTx, defaultMakerSig, defaultMakerPermit, takerPermit);
        vm.stopPrank();
        vm.snapshotGasLastCall("RFQ", "fillRFQ(): testFillRFQWithTakerApproveAllowanceTarget");
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
        bytes memory makerSig = signRFQOffer(makerSignerPrivateKey, rfqTx.rfqOffer, address(rfq));

        vm.expectEmit(true, true, true, true);
        emit IRFQ.FilledRFQ(
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

        vm.startPrank(defaultRFQOffer.taker, defaultRFQOffer.taker);
        rfq.fillRFQ(rfqTx, makerSig, defaultMakerPermit, defaultTakerPermit);
        vm.stopPrank();
        vm.snapshotGasLastCall("RFQ", "fillRFQ(): testFillRFQWithZeroFee");

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

        bytes memory makerSig = signRFQOffer(makerSignerPrivateKey, rfqOffer, address(rfq));

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

        vm.startPrank(rfqOffer.taker, rfqOffer.taker);
        rfq.fillRFQ{ value: rfqOffer.takerTokenAmount }(rfqTx, makerSig, defaultMakerPermit, defaultTakerPermit);
        vm.stopPrank();
        vm.snapshotGasLastCall("RFQ", "fillRFQ(): testFillRFQWithRawETH");

        takerTakerToken.assertChange(-int256(rfqOffer.takerTokenAmount));
        takerMakerToken.assertChange(int256(0));
        makerTakerToken.assertChange(int256(rfqOffer.takerTokenAmount));
        makerMakerToken.assertChange(-int256(rfqOffer.makerTokenAmount));
        recTakerToken.assertChange(int256(0));
        // recipient gets less than original makerTokenAmount because of the fee
        recMakerToken.assertChange(int256(amountAfterFee));
        fcMakerToken.assertChange(int256(fee));
    }

    function testFillRFQWithRawETHAndReceiveWETH() public {
        // case : taker token is ETH
        RFQOffer memory rfqOffer = defaultRFQOffer;
        rfqOffer.takerToken = Constant.ZERO_ADDRESS;
        rfqOffer.takerTokenAmount = 1 ether;
        rfqOffer.flags |= FLG_MAKER_RECEIVES_WETH;

        bytes memory makerSig = signRFQOffer(makerSignerPrivateKey, rfqOffer, address(rfq));

        Snapshot memory takerTakerToken = BalanceSnapshot.take({ owner: rfqOffer.taker, token: rfqOffer.takerToken });
        Snapshot memory takerMakerToken = BalanceSnapshot.take({ owner: rfqOffer.taker, token: rfqOffer.makerToken });
        // maker should receive WETH
        Snapshot memory makerWETHToken = BalanceSnapshot.take({ owner: rfqOffer.maker, token: address(weth) });
        Snapshot memory makerMakerToken = BalanceSnapshot.take({ owner: rfqOffer.maker, token: rfqOffer.makerToken });
        Snapshot memory recTakerToken = BalanceSnapshot.take({ owner: recipient, token: rfqOffer.takerToken });
        Snapshot memory recMakerToken = BalanceSnapshot.take({ owner: recipient, token: rfqOffer.makerToken });
        Snapshot memory fcMakerToken = BalanceSnapshot.take({ owner: feeCollector, token: rfqOffer.makerToken });

        uint256 fee = (rfqOffer.makerTokenAmount * defaultFeeFactor) / Constant.BPS_MAX;
        uint256 amountAfterFee = rfqOffer.makerTokenAmount - fee;

        RFQTx memory rfqTx = defaultRFQTx;
        rfqTx.rfqOffer = rfqOffer;
        rfqTx.takerRequestAmount = rfqOffer.takerTokenAmount;

        vm.startPrank(rfqOffer.taker, rfqOffer.taker);
        rfq.fillRFQ{ value: rfqOffer.takerTokenAmount }(rfqTx, makerSig, defaultMakerPermit, defaultTakerPermit);
        vm.stopPrank();
        vm.snapshotGasLastCall("RFQ", "fillRFQ(): testFillRFQWithRawETHAndReceiveWETH");

        takerTakerToken.assertChange(-int256(rfqOffer.takerTokenAmount));
        takerMakerToken.assertChange(int256(0));
        makerWETHToken.assertChange(int256(rfqOffer.takerTokenAmount));
        makerMakerToken.assertChange(-int256(rfqOffer.makerTokenAmount));
        recTakerToken.assertChange(int256(0));
        // recipient gets less than original makerTokenAmount because of the fee
        recMakerToken.assertChange(int256(amountAfterFee));
        fcMakerToken.assertChange(int256(fee));
    }

    function testFillRFQTakerGetRawETH() public {
        RFQOffer memory rfqOffer = defaultRFQOffer;
        rfqOffer.makerToken = Constant.ETH_ADDRESS;
        rfqOffer.makerTokenAmount = 1 ether;

        bytes memory makerSig = signRFQOffer(makerSignerPrivateKey, rfqOffer, address(rfq));

        Snapshot memory takerTakerToken = BalanceSnapshot.take({ owner: rfqOffer.taker, token: rfqOffer.takerToken });
        Snapshot memory takerMakerToken = BalanceSnapshot.take({ owner: rfqOffer.taker, token: rfqOffer.makerToken });
        Snapshot memory makerTakerToken = BalanceSnapshot.take({ owner: rfqOffer.maker, token: rfqOffer.takerToken });
        // market maker only receives WETH
        Snapshot memory makerMakerToken = BalanceSnapshot.take({ owner: rfqOffer.maker, token: WETH_ADDRESS });
        // recipient should receive raw ETH
        Snapshot memory recTakerToken = BalanceSnapshot.take({ owner: recipient, token: rfqOffer.takerToken });
        Snapshot memory recMakerToken = BalanceSnapshot.take({ owner: recipient, token: rfqOffer.makerToken });
        Snapshot memory fcMakerToken = BalanceSnapshot.take({ owner: feeCollector, token: rfqOffer.makerToken });

        uint256 fee = (rfqOffer.makerTokenAmount * defaultFeeFactor) / Constant.BPS_MAX;
        uint256 amountAfterFee = rfqOffer.makerTokenAmount - fee;

        RFQTx memory rfqTx = defaultRFQTx;
        rfqTx.rfqOffer = rfqOffer;

        vm.startPrank(rfqOffer.taker, rfqOffer.taker);
        rfq.fillRFQ(rfqTx, makerSig, defaultMakerPermit, defaultTakerPermit);
        vm.stopPrank();
        vm.snapshotGasLastCall("RFQ", "fillRFQ(): testFillRFQTakerGetRawETH");

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

        bytes memory makerSig = signRFQOffer(makerSignerPrivateKey, rfqOffer, address(rfq));

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

        vm.startPrank(rfqOffer.taker, rfqOffer.taker);
        rfq.fillRFQ(rfqTx, makerSig, defaultMakerPermit, takerPermit);
        vm.stopPrank();
        vm.snapshotGasLastCall("RFQ", "fillRFQ(): testFillRFQWithWETH");

        takerTakerToken.assertChange(-int256(rfqOffer.takerTokenAmount));
        takerMakerToken.assertChange(int256(0));
        makerTakerToken.assertChange(int256(rfqOffer.takerTokenAmount));
        makerMakerToken.assertChange(-int256(rfqOffer.makerTokenAmount));
        recTakerToken.assertChange(int256(0));
        recMakerToken.assertChange(int256(amountAfterFee));
        fcMakerToken.assertChange(int256(fee));
    }

    function testFillRFQWithWETHAndReceiveWETH() public {
        // case : taker token is WETH
        RFQOffer memory rfqOffer = defaultRFQOffer;
        rfqOffer.takerToken = WETH_ADDRESS;
        rfqOffer.takerTokenAmount = 1 ether;
        rfqOffer.flags |= FLG_MAKER_RECEIVES_WETH;

        bytes memory makerSig = signRFQOffer(makerSignerPrivateKey, rfqOffer, address(rfq));

        Snapshot memory takerTakerToken = BalanceSnapshot.take({ owner: rfqOffer.taker, token: rfqOffer.takerToken });
        Snapshot memory takerMakerToken = BalanceSnapshot.take({ owner: rfqOffer.taker, token: rfqOffer.makerToken });
        // maker should receive WETH
        Snapshot memory makerWETHToken = BalanceSnapshot.take({ owner: rfqOffer.maker, token: address(weth) });
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

        vm.startPrank(rfqOffer.taker, rfqOffer.taker);
        rfq.fillRFQ(rfqTx, makerSig, defaultMakerPermit, takerPermit);
        vm.stopPrank();
        vm.snapshotGasLastCall("RFQ", "fillRFQ(): testFillRFQWithWETHAndReceiveWETH");

        takerTakerToken.assertChange(-int256(rfqOffer.takerTokenAmount));
        takerMakerToken.assertChange(int256(0));
        makerWETHToken.assertChange(int256(rfqOffer.takerTokenAmount));
        makerMakerToken.assertChange(-int256(rfqOffer.makerTokenAmount));
        recTakerToken.assertChange(int256(0));
        recMakerToken.assertChange(int256(amountAfterFee));
        fcMakerToken.assertChange(int256(fee));
    }

    function testFillWithContract() public {
        RFQOffer memory rfqOffer = defaultRFQOffer;
        rfqOffer.flags |= FLG_ALLOW_CONTRACT_SENDER;
        rfqOffer.taker = takerWalletContract;
        bytes memory makerSig = signRFQOffer(makerSignerPrivateKey, rfqOffer, address(rfq));

        RFQTx memory rfqTx = defaultRFQTx;
        rfqTx.rfqOffer = rfqOffer;

        // the owner should be takerWalletContract but the signer is taker
        // permit2 will validate sig using EIP-1271
        bytes memory takerPermit = getTokenlonPermit2Data(takerWalletContract, takerPrivateKey, defaultRFQOffer.takerToken, address(rfq));

        // tx.origin is an EOA, msg.sender is a contract
        vm.startPrank(takerWalletContract, makeAddr("anyAddr"));
        rfq.fillRFQ(rfqTx, makerSig, defaultMakerPermit, takerPermit);
        vm.stopPrank();
        vm.snapshotGasLastCall("RFQ", "fillRFQ(): testFillWithContract");
    }

    function testPartialFill() public {
        RFQOffer memory rfqOffer = defaultRFQOffer;
        rfqOffer.flags |= FLG_ALLOW_PARTIAL_FILL;

        bytes memory makerSig = signRFQOffer(makerSignerPrivateKey, rfqOffer, address(rfq));

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

        vm.startPrank(rfqOffer.taker, rfqOffer.taker);
        rfq.fillRFQ(rfqTx, makerSig, defaultMakerPermit, defaultTakerPermit);
        vm.stopPrank();
        vm.snapshotGasLastCall("RFQ", "fillRFQ(): testPartialFill");

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

        vm.startPrank(defaultRFQOffer.taker, defaultRFQOffer.taker);
        vm.expectRevert(IRFQ.ForbidPartialFill.selector);
        rfq.fillRFQ(rfqTx, defaultMakerSig, defaultMakerPermit, defaultTakerPermit);
        vm.stopPrank();
    }

    function testCannotPartialFillWithInvalidAmount() public {
        RFQOffer memory rfqOffer = defaultRFQOffer;
        rfqOffer.flags |= FLG_ALLOW_PARTIAL_FILL;

        bytes memory makerSig = signRFQOffer(makerSignerPrivateKey, rfqOffer, address(rfq));

        // case : takerRequestAmount > offer.takerTokenAmount
        RFQTx memory rfqTx = defaultRFQTx;
        rfqTx.rfqOffer = rfqOffer;
        rfqTx.takerRequestAmount = defaultRFQOffer.takerTokenAmount * 2;

        vm.startPrank(rfqOffer.taker, rfqOffer.taker);
        vm.expectRevert(IRFQ.InvalidTakerAmount.selector);
        rfq.fillRFQ(rfqTx, makerSig, defaultMakerPermit, defaultTakerPermit);
        vm.stopPrank();

        // case : takerRequestAmount = 0
        RFQTx memory rfqTx1 = defaultRFQTx;
        rfqTx1.rfqOffer = rfqOffer;
        rfqTx1.takerRequestAmount = 0;

        vm.startPrank(rfqOffer.taker, rfqOffer.taker);
        vm.expectRevert(IRFQ.InvalidTakerAmount.selector);
        rfq.fillRFQ(rfqTx1, makerSig, defaultMakerPermit, defaultTakerPermit);
        vm.stopPrank();
    }

    function testCannotFillWithContractWhenNotAllowContractSender() public {
        RFQTx memory rfqTx = defaultRFQTx;
        address mockContract = makeAddr("mockContract");

        vm.startPrank(mockContract, defaultRFQOffer.taker);
        vm.expectRevert(IRFQ.ForbidContract.selector);
        rfq.fillRFQ(rfqTx, defaultMakerSig, defaultMakerPermit, defaultTakerPermit);
        vm.stopPrank();
    }

    function testCannotFillExpiredRFQTx() public {
        vm.warp(defaultRFQOffer.expiry + 1);

        vm.startPrank(defaultRFQOffer.taker, defaultRFQOffer.taker);
        vm.expectRevert(IRFQ.ExpiredRFQOffer.selector);
        rfq.fillRFQ(defaultRFQTx, defaultMakerSig, defaultMakerPermit, defaultTakerPermit);
        vm.stopPrank();
    }

    function testCannotFillAlreadyFillRFQTx() public {
        vm.startPrank(defaultRFQOffer.taker, defaultRFQOffer.taker);
        rfq.fillRFQ(defaultRFQTx, defaultMakerSig, defaultMakerPermit, defaultTakerPermit);
        vm.stopPrank();

        vm.startPrank(defaultRFQOffer.taker, defaultRFQOffer.taker);
        vm.expectRevert(IRFQ.FilledRFQOffer.selector);
        rfq.fillRFQ(defaultRFQTx, defaultMakerSig, defaultMakerPermit, defaultTakerPermit);
        vm.stopPrank();
    }

    function testCannotFillRFQWithIncorrectMakerSig() public {
        uint256 randomPrivateKey = 5677;
        bytes memory randomMakerSig = signRFQOffer(randomPrivateKey, defaultRFQOffer, address(rfq));

        vm.startPrank(defaultRFQOffer.taker, defaultRFQOffer.taker);
        vm.expectRevert(IRFQ.InvalidSignature.selector);
        rfq.fillRFQ(defaultRFQTx, randomMakerSig, defaultMakerPermit, defaultTakerPermit);
        vm.stopPrank();
    }

    function testCannotFillWithZeroRecipient() public {
        RFQTx memory rfqTx = defaultRFQTx;
        rfqTx.recipient = payable(address(0));

        vm.startPrank(defaultRFQOffer.taker, defaultRFQOffer.taker);
        vm.expectRevert(IRFQ.ZeroAddress.selector);
        rfq.fillRFQ(rfqTx, defaultMakerSig, defaultMakerPermit, defaultTakerPermit);
        vm.stopPrank();
    }

    function testCannotFillWithIncorrectMsgValue() public {
        // case : takerToken is normal ERC20
        vm.startPrank(defaultRFQOffer.taker, defaultRFQOffer.taker);
        vm.expectRevert(IRFQ.InvalidMsgValue.selector);
        rfq.fillRFQ{ value: 1 ether }(defaultRFQTx, defaultMakerSig, defaultMakerPermit, defaultTakerPermit);
        vm.stopPrank();

        // case : takerToken is WETH
        RFQOffer memory rfqOffer = defaultRFQOffer;
        rfqOffer.takerToken = WETH_ADDRESS;
        rfqOffer.takerTokenAmount = 1 ether;
        RFQTx memory rfqTx = defaultRFQTx;
        rfqTx.rfqOffer = rfqOffer;
        rfqTx.takerRequestAmount = rfqOffer.takerTokenAmount;
        bytes memory makerSig = signRFQOffer(makerSignerPrivateKey, rfqOffer, address(rfq));

        vm.startPrank(defaultRFQOffer.taker, defaultRFQOffer.taker);
        vm.expectRevert(IRFQ.InvalidMsgValue.selector);
        rfq.fillRFQ{ value: 2 ether }(rfqTx, makerSig, defaultMakerPermit, defaultTakerPermit);
        vm.stopPrank();

        // case : takerToken is raw ETH
        RFQOffer memory rfqOffer1 = defaultRFQOffer;
        rfqOffer1.takerToken = Constant.ZERO_ADDRESS;
        rfqOffer1.takerTokenAmount = 1 ether;
        RFQTx memory rfqTx1 = defaultRFQTx;
        rfqTx1.rfqOffer = rfqOffer1;
        rfqTx1.takerRequestAmount = rfqOffer1.takerTokenAmount;
        bytes memory makerSig1 = signRFQOffer(makerSignerPrivateKey, rfqOffer1, address(rfq));

        vm.startPrank(defaultRFQOffer.taker, defaultRFQOffer.taker);
        vm.expectRevert(IRFQ.InvalidMsgValue.selector);
        rfq.fillRFQ{ value: 2 ether }(rfqTx1, makerSig1, defaultMakerPermit, defaultTakerPermit);
        vm.stopPrank();
    }

    function testFillRFQByTakerSig() public {
        Snapshot memory takerTakerToken = BalanceSnapshot.take({ owner: defaultRFQOffer.taker, token: defaultRFQOffer.takerToken });
        Snapshot memory takerMakerToken = BalanceSnapshot.take({ owner: defaultRFQOffer.taker, token: defaultRFQOffer.makerToken });
        Snapshot memory makerTakerToken = BalanceSnapshot.take({ owner: defaultRFQOffer.maker, token: defaultRFQOffer.takerToken });
        Snapshot memory makerMakerToken = BalanceSnapshot.take({ owner: defaultRFQOffer.maker, token: defaultRFQOffer.makerToken });
        Snapshot memory recTakerToken = BalanceSnapshot.take({ owner: recipient, token: defaultRFQOffer.takerToken });
        Snapshot memory recMakerToken = BalanceSnapshot.take({ owner: recipient, token: defaultRFQOffer.makerToken });
        Snapshot memory fcMakerToken = BalanceSnapshot.take({ owner: feeCollector, token: defaultRFQOffer.makerToken });

        bytes memory takerSig = signRFQTx(takerPrivateKey, defaultRFQTx, address(rfq));
        uint256 fee = (defaultRFQOffer.makerTokenAmount * defaultFeeFactor) / Constant.BPS_MAX;
        uint256 amountAfterFee = defaultRFQOffer.makerTokenAmount - fee;

        vm.expectEmit(true, true, true, true);
        emit IRFQ.FilledRFQ(
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

        vm.startPrank(txRelayer, txRelayer);
        rfq.fillRFQWithSig(defaultRFQTx, defaultMakerSig, defaultMakerPermit, defaultTakerPermit, takerSig);
        vm.stopPrank();
        vm.snapshotGasLastCall("RFQ", "fillRFQWithSig(): testFillRFQByTakerSig");

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
        bytes memory randomSig = signRFQTx(randomPrivateKey, defaultRFQTx, address(rfq));

        vm.startPrank(txRelayer, txRelayer);
        vm.expectRevert(IRFQ.InvalidSignature.selector);
        rfq.fillRFQWithSig(defaultRFQTx, defaultMakerSig, defaultMakerPermit, defaultTakerPermit, randomSig);
        vm.stopPrank();
    }

    function testCannotFillWithInvalidFeeFactor() public {
        RFQTx memory rfqTx = defaultRFQTx;
        rfqTx.rfqOffer.feeFactor = Constant.BPS_MAX + 1;
        bytes memory takerSig = signRFQTx(takerPrivateKey, rfqTx, address(rfq));

        vm.startPrank(txRelayer, txRelayer);
        vm.expectRevert(IRFQ.InvalidFeeFactor.selector);
        rfq.fillRFQWithSig(rfqTx, defaultMakerSig, defaultMakerPermit, defaultTakerPermit, takerSig);
        vm.stopPrank();
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
        bytes memory makerSig = signRFQOffer(makerSignerPrivateKey, rfqOffer, address(rfq));

        vm.startPrank(rfqOffer.taker, rfqOffer.taker);
        vm.expectRevert(IRFQ.InvalidMakerAmount.selector);
        rfq.fillRFQ(rfqTx, makerSig, defaultMakerPermit, defaultTakerPermit);
        vm.stopPrank();
    }

    function testCancelRFQOffer() public {
        vm.expectEmit(true, true, false, false);
        emit IRFQ.CancelRFQOffer(getRFQOfferHash(defaultRFQOffer), defaultRFQOffer.maker);

        vm.startPrank(defaultRFQOffer.maker);
        rfq.cancelRFQOffer(defaultRFQOffer);
        vm.stopPrank();
        vm.snapshotGasLastCall("RFQ", "cancelRFQOffer(): testCancelRFQOffer");
    }

    function testCannotCancelRFQOfferIfNotMaker() public {
        vm.startPrank(makeAddr("not offer maker"));
        vm.expectRevert(IRFQ.NotOfferMaker.selector);
        rfq.cancelRFQOffer(defaultRFQOffer);
        vm.stopPrank();
    }

    function testCannotCancelRFQOfferIfFilled() public {
        vm.startPrank(defaultRFQOffer.taker, defaultRFQOffer.taker);
        rfq.fillRFQ(defaultRFQTx, defaultMakerSig, defaultMakerPermit, defaultTakerPermit);
        vm.stopPrank();

        vm.startPrank(defaultRFQOffer.maker);
        vm.expectRevert(IRFQ.FilledRFQOffer.selector);
        rfq.cancelRFQOffer(defaultRFQOffer);
        vm.stopPrank();
    }

    function testCannotCancelRFQOfferTwice() public {
        vm.startPrank(defaultRFQOffer.maker);
        rfq.cancelRFQOffer(defaultRFQOffer);
        vm.stopPrank();

        vm.startPrank(defaultRFQOffer.maker);
        vm.expectRevert(IRFQ.FilledRFQOffer.selector);
        rfq.cancelRFQOffer(defaultRFQOffer);
        vm.stopPrank();
    }
}
