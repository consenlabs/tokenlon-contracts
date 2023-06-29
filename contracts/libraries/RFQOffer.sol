// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

string constant RFQ_OFFER_TYPESTRING = "RFQOffer(address taker,address maker,address takerToken,uint256 takerTokenAmount,address makerToken,uint256 makerTokenAmount,uint256 feeFactor,uint256 flags,uint256 expiry,uint256 salt)";

bytes32 constant RFQ_OFFER_DATA_TYPEHASH = 0x4b43f8e0f7a19a08c96469eb0679ca2da9fab62fb18a10e34e5e0c4ae0248a1c;
// keccak256(RFQ_OFFER_TYPESTRING);

struct RFQOffer {
    address taker;
    address payable maker;
    address takerToken;
    uint256 takerTokenAmount;
    address makerToken;
    uint256 makerTokenAmount;
    uint256 feeFactor;
    uint256 flags;
    uint256 expiry;
    uint256 salt;
}

// solhint-disable-next-line func-visibility
function getRFQOfferHash(RFQOffer memory rfqOffer) pure returns (bytes32) {
    return
        keccak256(
            abi.encode(
                RFQ_OFFER_DATA_TYPEHASH,
                rfqOffer.taker,
                rfqOffer.maker,
                rfqOffer.takerToken,
                rfqOffer.takerTokenAmount,
                rfqOffer.makerToken,
                rfqOffer.makerTokenAmount,
                rfqOffer.feeFactor,
                rfqOffer.flags,
                rfqOffer.expiry,
                rfqOffer.salt
            )
        );
}
