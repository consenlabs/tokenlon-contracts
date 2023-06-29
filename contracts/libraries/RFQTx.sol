// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { RFQOffer, getRFQOfferHash, RFQ_OFFER_TYPESTRING } from "./RFQOffer.sol";

string constant RFQ_TX_TYPESTRING = string(abi.encodePacked("RFQTx(RFQOffer rfqOffer,address recipient,uint256 takerRequestAmount)", RFQ_OFFER_TYPESTRING));

bytes32 constant RFQ_TX_TYPEHASH = 0x97972dc666c2aa8c659018f15b9a82f6ef40f271eebb1ab163a310eca758f29f;
// keccak256(RFQ_TX_TYPESTRING);

struct RFQTx {
    RFQOffer rfqOffer;
    address payable recipient;
    uint256 takerRequestAmount;
}

// solhint-disable-next-line func-visibility
function getRFQTxHash(RFQTx memory rfqTx) pure returns (bytes32 rfqOfferHash, bytes32 rfqTxHash) {
    rfqOfferHash = getRFQOfferHash(rfqTx.rfqOffer);
    rfqTxHash = keccak256(abi.encode(RFQ_TX_TYPEHASH, rfqOfferHash, rfqTx.recipient, rfqTx.takerRequestAmount));
}
