// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";
import { Tokens } from "test/utils/Tokens.sol";
import { BalanceUtil } from "test/utils/BalanceUtil.sol";
import { RFQOffer, getRFQOfferHash } from "contracts/libraries/RFQOffer.sol";
import { RFQTx, getRFQTxHash } from "contracts/libraries/RFQTx.sol";
import { IGenericSwap } from "contracts/interfaces/IGenericSwap.sol";
import { ISmartOrderStrategy } from "contracts/interfaces/ISmartOrderStrategy.sol";
import { GenericSwapData, getGSDataHash } from "contracts/libraries/GenericSwapData.sol";
import { IRFQ } from "contracts/interfaces/IRFQ.sol";
import { SigHelper } from "test/utils/SigHelper.sol";
import { Permit2Helper } from "test/utils/Permit2Helper.sol";

contract GenRFQData is Test, Tokens, BalanceUtil, SigHelper, Permit2Helper {
    // address deployedGS = 0xa7e96Bf2735BD33750Bb504C3Cc63e3770668dd4;
    // address deployedSOR = 0x0E67fD506Db5C6199C5D2b2b54380DEB414E2431;
    // address deployedRFQ = 0xC6e1074113a954340277aE6F309aF2AF6e259283;
    address deployedGS;
    address deployedSOR;
    address deployedRFQ;

    uint256 takerKey = uint256(7414);
    address taker = vm.addr(takerKey);
    uint256 makerKey = uint256(94530678);
    address maker = vm.addr(makerKey);

    function setUp() public {
        deployedGS = vm.envAddress("GS");
        deployedSOR = vm.envAddress("SOR");
        deployedRFQ = vm.envAddress("RFQ");

        BalanceUtil.setTokenBalanceAndApprove(taker, deployedGS, tokens, 1000000000000);
        BalanceUtil.setTokenBalanceAndApprove(taker, deployedRFQ, tokens, 1000000000000);
        BalanceUtil.setTokenBalanceAndApprove(maker, deployedRFQ, tokens, 1000000000000);
    }

    function test_gen_RFQ_data_called_from_GS() public {
        address testTakerToken = vm.envAddress("TAKER_TOKEN");
        address testMakerToken = vm.envAddress("MAKER_TOKEN");

        uint256 testTakerTokenAmount = 5000000;
        uint256 testMakerTokenAmount = 20000000;

        RFQOffer memory rfqOffer = RFQOffer({
            taker: deployedSOR,
            takerToken: testTakerToken,
            takerTokenAmount: testTakerTokenAmount,
            maker: payable(maker),
            makerToken: testMakerToken,
            makerTokenAmount: testMakerTokenAmount,
            expiry: 2 ** 256 - 1,
            feeFactor: 0,
            flags: 86844066927987146567678238756515930889952488499230423029593188005934847229952,
            salt: 55688
        });
        RFQTx memory rfqTx = RFQTx({ rfqOffer: rfqOffer, takerRequestAmount: testTakerTokenAmount, recipient: payable(deployedSOR) });
        bytes memory makerSig = signRFQOffer(makerKey, rfqOffer, address(deployedRFQ));

        ISmartOrderStrategy.Operation memory ops1 = ISmartOrderStrategy.Operation({
            dest: deployedRFQ,
            inputToken: testTakerToken,
            ratioNumerator: 0,
            ratioDenominator: 0,
            dataOffset: 0,
            value: 0,
            data: abi.encodeCall(IRFQ.fillRFQ, (rfqTx, makerSig, hex"01", hex"01"))
            // data: abi.encodeWithSelector(IRFQ.fillRFQ.selector, rfqTx, makerSig, hex"01", hex"01")
        });
        ISmartOrderStrategy.Operation[] memory operations = new ISmartOrderStrategy.Operation[](1);
        operations[0] = ops1;

        GenericSwapData memory defaultGSData = GenericSwapData({
            maker: payable(address(deployedSOR)),
            takerToken: testTakerToken,
            takerTokenAmount: testTakerTokenAmount,
            makerToken: testMakerToken,
            makerTokenAmount: testMakerTokenAmount,
            minMakerTokenAmount: 0,
            expiry: 2 ** 256 - 1,
            salt: 5678,
            recipient: payable(taker),
            strategyData: abi.encode(operations)
        });

        bytes memory gsCalldata = abi.encodeWithSelector(IGenericSwap.executeSwap.selector, defaultGSData, hex"01");

        console.log("taker:", taker);
        console.log("maker:", rfqOffer.maker);
        console.log("takerToken:", testTakerToken);
        console.log("makerToken:", testMakerToken);
        console.logBytes(gsCalldata);

        // vm.prank(taker, taker);
        // IGenericSwap(deployedGS).executeSwap(defaultGSData, hex"01");
    }

    function test_gen_RFQ_data_Permit_01_from_EOA() public {
        address testTakerToken = vm.envAddress("TAKER_TOKEN");
        address testMakerToken = vm.envAddress("MAKER_TOKEN");

        RFQOffer memory rfqOffer = RFQOffer({
            taker: taker,
            takerToken: testTakerToken,
            takerTokenAmount: 5000000,
            maker: payable(maker),
            makerToken: testMakerToken,
            makerTokenAmount: 20000000000,
            expiry: 2 ** 256 - 1,
            feeFactor: 100, // NOTE: if taker fills order solely on RFQ, we charge fee through setting a non-zero feeFactor
            flags: 86844066927987146567678238756515930889952488499230423029593188005934847229952,
            salt: 55688
        });
        RFQTx memory rfqTx = RFQTx({ rfqOffer: rfqOffer, takerRequestAmount: 5000000, recipient: payable(taker) });
        bytes memory makerSig = signRFQOffer(makerKey, rfqOffer, address(deployedRFQ));

        bytes memory rfqCalldata = abi.encodeCall(IRFQ.fillRFQ, (rfqTx, makerSig, hex"01", hex"01"));

        console.log("taker:", taker);
        console.log("maker:", rfqOffer.maker);
        console.log("takerToken:", testTakerToken);
        console.log("makerToken:", testMakerToken);
        console.logBytes(rfqCalldata);

        // vm.prank(taker, taker);
        // IRFQ(deployedRFQ).fillRFQ(rfqTx, makerSig, hex"01", hex"01");
    }

    function test_gen_RFQ_data_Permit_03_from_EOA() public {
        address testTakerToken = vm.envAddress("TAKER_TOKEN");
        address testMakerToken = vm.envAddress("MAKER_TOKEN");

        BalanceUtil.setTokenBalanceAndApprove(taker, address(permit2), tokens, 1000000000000);

        RFQOffer memory rfqOffer = RFQOffer({
            taker: taker,
            takerToken: testTakerToken,
            takerTokenAmount: 5000000,
            maker: payable(maker),
            makerToken: testMakerToken,
            makerTokenAmount: 20000000000,
            expiry: 2 ** 256 - 1,
            feeFactor: 100, // NOTE: if taker fills order solely on RFQ, we charge fee through setting a non-zero feeFactor
            flags: 86844066927987146567678238756515930889952488499230423029593188005934847229952,
            salt: 55688
        });
        RFQTx memory rfqTx = RFQTx({ rfqOffer: rfqOffer, takerRequestAmount: 5000000, recipient: payable(taker) });
        bytes memory makerSig = signRFQOffer(makerKey, rfqOffer, address(deployedRFQ));
        bytes memory takerPermit = getTokenlonPermit2DataWithExpiry(taker, takerKey, testTakerToken, deployedRFQ, 2 ** 48 - 1);

        bytes memory rfqCalldata = abi.encodeCall(IRFQ.fillRFQ, (rfqTx, makerSig, hex"01", takerPermit));

        console.log("taker:", taker);
        console.log("maker:", rfqOffer.maker);
        console.log("takerToken:", testTakerToken);
        console.log("makerToken:", testMakerToken);
        console.logBytes(rfqCalldata);

        // vm.prank(taker, taker);
        // IRFQ(deployedRFQ).fillRFQ(rfqTx, makerSig, hex"01", takerPermit);
    }
}
