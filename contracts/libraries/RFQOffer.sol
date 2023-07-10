// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

string constant RFQ_OFFER_TYPESTRING = "RFQOffer(address taker,address maker,address takerToken,uint256 takerTokenAmount,address makerToken,uint256 makerTokenAmount,uint256 feeFactor,uint256 flags,uint256 expiry,uint256 salt)";

bytes32 constant RFQ_OFFER_DATA_TYPEHASH = keccak256(bytes(RFQ_OFFER_TYPESTRING));

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
