// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { ALLOWFILL_DATA_TYPEHASH, AllowFill } from "contracts/libraries/AllowFill.sol";
import { GS_DATA_TYPEHASH, GenericSwapData } from "contracts/libraries/GenericSwapData.sol";
import { LIMITORDER_DATA_TYPEHASH, LimitOrder } from "contracts/libraries/LimitOrder.sol";
import { RFQOffer, RFQ_OFFER_DATA_TYPEHASH } from "contracts/libraries/RFQOffer.sol";
import { RFQTx, RFQ_TX_TYPEHASH } from "contracts/libraries/RFQTx.sol";

import { SigHelper } from "test/utils/SigHelper.sol";

contract testEIP712Signing is SigHelper {
    function testAllowFillSigning() public {
        string memory allowFillPayloadJson = vm.readFile("test/utils/payload/allowFill.json");

        bytes32 typehash = abi.decode(vm.parseJson(allowFillPayloadJson, "$.typehash"), (bytes32));
        assertEq(typehash, ALLOWFILL_DATA_TYPEHASH);

        address verifyingContract = abi.decode(vm.parseJson(allowFillPayloadJson, "$.verifyingContract"), (address));
        uint256 chainId = abi.decode(vm.parseJson(allowFillPayloadJson, "$.chainId"), (uint256));
        AllowFill memory allowFill = AllowFill({
            orderHash: abi.decode(vm.parseJson(allowFillPayloadJson, "$.orderHash"), (bytes32)),
            taker: abi.decode(vm.parseJson(allowFillPayloadJson, "$.taker"), (address)),
            fillAmount: abi.decode(vm.parseJson(allowFillPayloadJson, "$.fillAmount"), (uint256)),
            expiry: abi.decode(vm.parseJson(allowFillPayloadJson, "$.expiry"), (uint256)),
            salt: abi.decode(vm.parseJson(allowFillPayloadJson, "$.salt"), (uint256))
        });
        uint256 signingKey = abi.decode(vm.parseJson(allowFillPayloadJson, "$.signingKey"), (uint256));
        bytes memory sig = signAllowFill(signingKey, allowFill, chainId, verifyingContract);

        bytes memory expectedSig = abi.decode(vm.parseJson(allowFillPayloadJson, "$.expectedSig"), (bytes));
        assertEq(sig, expectedSig);
    }

    function testGenericSwapSigning() public {
        string memory genericSwapDataPayloadJson = vm.readFile("test/utils/payload/genericSwapData.json");

        bytes32 typehash = abi.decode(vm.parseJson(genericSwapDataPayloadJson, "$.typehash"), (bytes32));
        assertEq(typehash, GS_DATA_TYPEHASH);

        address verifyingContract = abi.decode(vm.parseJson(genericSwapDataPayloadJson, "$.verifyingContract"), (address));
        uint256 chainId = abi.decode(vm.parseJson(genericSwapDataPayloadJson, "$.chainId"), (uint256));
        GenericSwapData memory genericSwapData = GenericSwapData({
            maker: abi.decode(vm.parseJson(genericSwapDataPayloadJson, "$.maker"), (address)),
            takerToken: abi.decode(vm.parseJson(genericSwapDataPayloadJson, "$.takerToken"), (address)),
            takerTokenAmount: abi.decode(vm.parseJson(genericSwapDataPayloadJson, "$.takerTokenAmount"), (uint256)),
            makerToken: abi.decode(vm.parseJson(genericSwapDataPayloadJson, "$.makerToken"), (address)),
            makerTokenAmount: abi.decode(vm.parseJson(genericSwapDataPayloadJson, "$.makerTokenAmount"), (uint256)),
            minMakerTokenAmount: abi.decode(vm.parseJson(genericSwapDataPayloadJson, "$.minMakerTokenAmount"), (uint256)),
            expiry: abi.decode(vm.parseJson(genericSwapDataPayloadJson, "$.expiry"), (uint256)),
            salt: abi.decode(vm.parseJson(genericSwapDataPayloadJson, "$.salt"), (uint256)),
            recipient: abi.decode(vm.parseJson(genericSwapDataPayloadJson, "$.recipient"), (address)),
            strategyData: abi.decode(vm.parseJson(genericSwapDataPayloadJson, "$.strategyData"), (bytes))
        });
        uint256 signingKey = abi.decode(vm.parseJson(genericSwapDataPayloadJson, "$.signingKey"), (uint256));
        bytes memory sig = signGenericSwap(signingKey, genericSwapData, chainId, verifyingContract);

        bytes memory expectedSig = abi.decode(vm.parseJson(genericSwapDataPayloadJson, "$.expectedSig"), (bytes));
        assertEq(sig, expectedSig);
    }

    function testLimitOrderSigning() public {
        string memory limitOrderPayloadJson = vm.readFile("test/utils/payload/limitOrder.json");

        bytes32 typehash = abi.decode(vm.parseJson(limitOrderPayloadJson, "$.typehash"), (bytes32));
        assertEq(typehash, LIMITORDER_DATA_TYPEHASH);

        address verifyingContract = abi.decode(vm.parseJson(limitOrderPayloadJson, "$.verifyingContract"), (address));
        uint256 chainId = abi.decode(vm.parseJson(limitOrderPayloadJson, "$.chainId"), (uint256));
        LimitOrder memory limitOrder = LimitOrder({
            taker: abi.decode(vm.parseJson(limitOrderPayloadJson, "$.taker"), (address)),
            maker: abi.decode(vm.parseJson(limitOrderPayloadJson, "$.maker"), (address)),
            takerToken: abi.decode(vm.parseJson(limitOrderPayloadJson, "$.takerToken"), (address)),
            takerTokenAmount: abi.decode(vm.parseJson(limitOrderPayloadJson, "$.takerTokenAmount"), (uint256)),
            makerToken: abi.decode(vm.parseJson(limitOrderPayloadJson, "$.makerToken"), (address)),
            makerTokenAmount: abi.decode(vm.parseJson(limitOrderPayloadJson, "$.makerTokenAmount"), (uint256)),
            makerTokenPermit: abi.decode(vm.parseJson(limitOrderPayloadJson, "$.makerTokenPermit"), (bytes)),
            feeFactor: abi.decode(vm.parseJson(limitOrderPayloadJson, "$.feeFactor"), (uint256)),
            expiry: abi.decode(vm.parseJson(limitOrderPayloadJson, "$.expiry"), (uint256)),
            salt: abi.decode(vm.parseJson(limitOrderPayloadJson, "$.salt"), (uint256))
        });

        uint256 signingKey = abi.decode(vm.parseJson(limitOrderPayloadJson, "$.signingKey"), (uint256));
        bytes memory sig = signLimitOrder(signingKey, limitOrder, chainId, verifyingContract);

        bytes memory expectedSig = abi.decode(vm.parseJson(limitOrderPayloadJson, "$.expectedSig"), (bytes));
        assertEq(sig, expectedSig);
    }

    function testRFQOfferSigning() public {
        string memory rfqOfferPayloadJson = vm.readFile("test/utils/payload/rfqOffer.json");

        bytes32 typehash = abi.decode(vm.parseJson(rfqOfferPayloadJson, "$.typehash"), (bytes32));
        assertEq(typehash, RFQ_OFFER_DATA_TYPEHASH);

        address verifyingContract = abi.decode(vm.parseJson(rfqOfferPayloadJson, "$.verifyingContract"), (address));
        uint256 chainId = abi.decode(vm.parseJson(rfqOfferPayloadJson, "$.chainId"), (uint256));
        RFQOffer memory rfqOffer = RFQOffer({
            taker: abi.decode(vm.parseJson(rfqOfferPayloadJson, "$.taker"), (address)),
            maker: abi.decode(vm.parseJson(rfqOfferPayloadJson, "$.maker"), (address)),
            takerToken: abi.decode(vm.parseJson(rfqOfferPayloadJson, "$.takerToken"), (address)),
            takerTokenAmount: abi.decode(vm.parseJson(rfqOfferPayloadJson, "$.takerTokenAmount"), (uint256)),
            makerToken: abi.decode(vm.parseJson(rfqOfferPayloadJson, "$.makerToken"), (address)),
            makerTokenAmount: abi.decode(vm.parseJson(rfqOfferPayloadJson, "$.makerTokenAmount"), (uint256)),
            feeFactor: abi.decode(vm.parseJson(rfqOfferPayloadJson, "$.feeFactor"), (uint256)),
            flags: abi.decode(vm.parseJson(rfqOfferPayloadJson, "$.flags"), (uint256)),
            expiry: abi.decode(vm.parseJson(rfqOfferPayloadJson, "$.expiry"), (uint256)),
            salt: abi.decode(vm.parseJson(rfqOfferPayloadJson, "$.salt"), (uint256))
        });

        uint256 signingKey = abi.decode(vm.parseJson(rfqOfferPayloadJson, "$.signingKey"), (uint256));
        bytes memory sig = signRFQOffer(signingKey, rfqOffer, chainId, verifyingContract);

        bytes memory expectedSig = abi.decode(vm.parseJson(rfqOfferPayloadJson, "$.expectedSig"), (bytes));
        assertEq(sig, expectedSig);
    }

    function testRFQTxSigning() public {
        string memory rfqTxPayloadJson = vm.readFile("test/utils/payload/rfqTx.json");

        bytes32 typehash = abi.decode(vm.parseJson(rfqTxPayloadJson, "$.typehash"), (bytes32));
        assertEq(typehash, RFQ_TX_TYPEHASH);

        address verifyingContract = abi.decode(vm.parseJson(rfqTxPayloadJson, "$.verifyingContract"), (address));
        uint256 chainId = abi.decode(vm.parseJson(rfqTxPayloadJson, "$.chainId"), (uint256));
        RFQOffer memory _rfqOffer = RFQOffer({
            taker: abi.decode(vm.parseJson(rfqTxPayloadJson, "$.rfqOffer.taker"), (address)),
            maker: abi.decode(vm.parseJson(rfqTxPayloadJson, "$.rfqOffer.maker"), (address)),
            takerToken: abi.decode(vm.parseJson(rfqTxPayloadJson, "$.rfqOffer.takerToken"), (address)),
            takerTokenAmount: abi.decode(vm.parseJson(rfqTxPayloadJson, "$.rfqOffer.takerTokenAmount"), (uint256)),
            makerToken: abi.decode(vm.parseJson(rfqTxPayloadJson, "$.rfqOffer.makerToken"), (address)),
            makerTokenAmount: abi.decode(vm.parseJson(rfqTxPayloadJson, "$.rfqOffer.makerTokenAmount"), (uint256)),
            feeFactor: abi.decode(vm.parseJson(rfqTxPayloadJson, "$.rfqOffer.feeFactor"), (uint256)),
            flags: abi.decode(vm.parseJson(rfqTxPayloadJson, "$.rfqOffer.flags"), (uint256)),
            expiry: abi.decode(vm.parseJson(rfqTxPayloadJson, "$.rfqOffer.expiry"), (uint256)),
            salt: abi.decode(vm.parseJson(rfqTxPayloadJson, "$.rfqOffer.salt"), (uint256))
        });
        RFQTx memory rfqTx = RFQTx({
            rfqOffer: _rfqOffer,
            recipient: abi.decode(vm.parseJson(rfqTxPayloadJson, "$.recipient"), (address)),
            takerRequestAmount: abi.decode(vm.parseJson(rfqTxPayloadJson, "$.takerRequestAmount"), (uint256))
        });

        uint256 signingKey = abi.decode(vm.parseJson(rfqTxPayloadJson, "$.signingKey"), (uint256));
        bytes memory sig = signRFQTx(signingKey, rfqTx, chainId, verifyingContract);

        bytes memory expectedSig = abi.decode(vm.parseJson(rfqTxPayloadJson, "$.expectedSig"), (bytes));
        assertEq(sig, expectedSig);
    }
}
