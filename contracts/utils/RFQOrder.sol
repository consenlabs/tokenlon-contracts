// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

import { Offer, getOfferHash, OFFER_TYPESTRING } from "./Offer.sol";

string constant RFQ_ORDER_TYPESTRING = string(abi.encodePacked("RFQOrder(Offer offer,address recipient,uint256 feeFactor)", OFFER_TYPESTRING));

bytes32 constant RFQ_ORDER_TYPEHASH = keccak256(bytes(RFQ_ORDER_TYPESTRING));

struct RFQOrder {
    Offer offer;
    address payable recipient;
    uint256 feeFactor;
}

// solhint-disable-next-line func-visibility
function getRFQOrderHash(RFQOrder memory rfqOrder) pure returns (bytes32 offerHash, bytes32 orderHash) {
    offerHash = getOfferHash(rfqOrder.offer);
    orderHash = keccak256(abi.encode(RFQ_ORDER_TYPEHASH, offerHash, rfqOrder.recipient, rfqOrder.feeFactor));
}
