// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

string constant LIMITORDER_TYPESTRING = "LimitOrder(address taker,address maker,address takerToken,uint256 takerTokenAmount,address makerToken,uint256 makerTokenAmount,bytes makerTokenPermit,uint256 feeFactor,uint256 expiry,uint256 salt)";

bytes32 constant LIMITORDER_DATA_TYPEHASH = 0x793a151d40717ec9661de4a7eba1a45e7313a08e4184d5383e3f9ff838fbcab6;
// keccak256(LIMITORDER_TYPESTRING);

struct LimitOrder {
    address taker;
    address payable maker;
    address takerToken;
    uint256 takerTokenAmount;
    address makerToken;
    uint256 makerTokenAmount;
    bytes makerTokenPermit;
    uint256 feeFactor;
    uint256 expiry;
    uint256 salt;
}

// solhint-disable-next-line func-visibility
function getLimitOrderHash(LimitOrder memory limitOrder) pure returns (bytes32) {
    return
        keccak256(
            abi.encode(
                LIMITORDER_DATA_TYPEHASH,
                limitOrder.taker,
                limitOrder.maker,
                limitOrder.takerToken,
                limitOrder.takerTokenAmount,
                limitOrder.makerToken,
                limitOrder.makerTokenAmount,
                keccak256(limitOrder.makerTokenPermit),
                limitOrder.feeFactor,
                limitOrder.expiry,
                limitOrder.salt
            )
        );
}
