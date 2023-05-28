// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { RFQOffer, getRFQOfferHash, RFQ_OFFER_TYPESTRING } from "./RFQOffer.sol";

string constant RFQ_TX_TYPESTRING = string(
    abi.encodePacked("RFQTx(RFQOffer rfqOffer,bytes32 offerHash,address recipient,uint256 takerRequestAmount,uint256 feeFactor)", RFQ_OFFER_TYPESTRING)
);

bytes32 constant RFQ_TX_TYPEHASH = 0x410ccbc4921380ed48f5d0e99274c601d8216ae398d0eb7e1ac71ffe81a62750;
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
