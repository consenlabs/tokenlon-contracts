// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { RFQOffer, getRFQOfferHash, RFQ_OFFER_TYPESTRING } from "./RFQOffer.sol";

string constant RFQ_TX_TYPESTRING = string(
    abi.encodePacked("RFQTx(RFQOffer rfqOffer,address recipient,uint256 takerRequestAmount,uint256 feeFactor)", RFQ_OFFER_TYPESTRING)
);

bytes32 constant RFQ_TX_TYPEHASH = 0x7d40e2c76ab47417bfc78e9a557a4669eec8ffea20951e6f764826b0e6f82f5e;
// keccak256(RFQ_TX_TYPESTRING);

struct RFQTx {
    RFQOffer rfqOffer;
    address payable recipient;
    uint256 takerRequestAmount;
    uint256 feeFactor;
}

// solhint-disable-next-line func-visibility
function getRFQTxHash(RFQTx memory rfqTx) pure returns (bytes32 rfqOfferHash, bytes32 rfqTxHash) {
    rfqOfferHash = getRFQOfferHash(rfqTx.rfqOffer);
    rfqTxHash = keccak256(abi.encode(RFQ_TX_TYPEHASH, rfqOfferHash, rfqTx.recipient, rfqTx.takerRequestAmount, rfqTx.feeFactor));
}
