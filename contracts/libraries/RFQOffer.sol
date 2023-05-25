// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

string constant RFQ_OFFER_TYPESTRING = "RFQOffer(address taker,address maker,address takerToken,uint256 takerTokenAmount,address makerToken,uint256 makerTokenAmount,uint256 flags,uint256 expiry,uint256 salt)";

bytes32 constant RFQ_OFFER_DATA_TYPEHASH = 0xe2fe0e2c4154e37bc6f98de59b8832a363aa7411c6b9a90825f10e229c52a7f8;
// keccak256(RFQ_OFFER_TYPESTRING);

struct RFQOffer {
    address taker;
    address payable maker;
    address takerToken;
    uint256 takerTokenAmount;
    address makerToken;
    uint256 makerTokenAmount;
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
                rfqOffer.flags,
                rfqOffer.expiry,
                rfqOffer.salt
            )
        );
}
