// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { RFQOffer, getRFQOfferHash, RFQ_OFFER_TYPESTRING } from "./RFQOffer.sol";

string constant RFQ_TX_TYPESTRING = string(
    abi.encodePacked("RFQTx(RFQOffer rfqOffer,bytes32 offerHash,address recipient,uint256 feeFactor)", RFQ_OFFER_TYPESTRING)
);

bytes32 constant RFQ_TX_TYPEHASH = 0x28da3d83da9c2baded56bfc240708e868698f435291c4afed01a8821b1e65702;
// keccak256(RFQ_TX_TYPESTRING);

struct RFQTx {
    RFQOffer rfqOffer;
    address payable recipient;
    uint256 feeFactor;
}

// solhint-disable-next-line func-visibility
function getRFQTxHash(RFQTx memory rfqTx) pure returns (bytes32 rfqOfferHash, bytes32 rfqTxHash) {
    rfqOfferHash = getRFQOfferHash(rfqTx.rfqOffer);
    rfqTxHash = keccak256(abi.encode(RFQ_TX_TYPEHASH, rfqOfferHash, rfqTx.recipient, rfqTx.feeFactor));
}
