// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Offer, getOfferHash, OFFER_TYPESTRING } from "./Offer.sol";

string constant GS_DATA_TYPESTRING = string(abi.encodePacked("GenericSwapData(Offer offer,address recipient,bytes strategyData)", OFFER_TYPESTRING));

bytes32 constant GS_DATA_TYPEHASH = 0x2b85d2440f3929b7e7ef5a98f4a456bd412909e1eebfe4aa973e60e845e9d2b9;
// keccak256(GS_DATA_TYPESTRING);

struct GenericSwapData {
    Offer offer;
    address payable recipient;
    bytes strategyData;
}

// solhint-disable-next-line func-visibility
function getGSDataHash(GenericSwapData memory gsData) pure returns (bytes32) {
    bytes32 offerHash = getOfferHash(gsData.offer);
    return keccak256(abi.encode(GS_DATA_TYPEHASH, offerHash, gsData.recipient, gsData.strategyData));
}
