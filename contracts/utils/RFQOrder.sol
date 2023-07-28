// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

import { Offer, getOfferHash, OFFER_TYPESTRING } from "./Offer.sol";

string constant RFQ_ORDER_TYPESTRING = string(abi.encodePacked("RFQOrder(Offer offer,address recipient)", OFFER_TYPESTRING));

bytes32 constant RFQ_ORDER_TYPEHASH = 0x1f9d9481d60f1cf20fbfc13ea99ded28208ec732cd67ebf09e631efb84af9c5a;
// keccak256(RFQ_ORDER_TYPESTRING);

struct RFQOrder {
    Offer offer;
    address payable recipient;
}

// solhint-disable-next-line func-visibility
function getRFQOrderHash(RFQOrder memory rfqOrder) pure returns (bytes32 offerHash, bytes32 orderHash) {
    offerHash = getOfferHash(rfqOrder.offer);
    orderHash = keccak256(abi.encode(RFQ_ORDER_TYPEHASH, offerHash, rfqOrder.recipient));
}
