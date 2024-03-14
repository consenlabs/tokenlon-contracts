// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

string constant CONORDER_TYPESTRING = "ConOrder(address taker,address maker,address recipient,address takerToken,uint256 takerTokenAmount,address makerToken,uint256 makerTokenAmount,bytes takerTokenPermit,uint256 flagsAndPeriod,uint256 expiry,uint256 salt)";

bytes32 constant CONORDER_DATA_TYPEHASH = keccak256(bytes(CONORDER_TYPESTRING));

// @note remember to modify the CONORDER_TYPESTRING if modify the ConOrder struct
struct ConOrder {
    address taker;
    address payable maker; // only maker can fill this ConOrder
    address payable recipient;
    address takerToken; // from user to maker
    uint256 takerTokenAmount;
    address makerToken; // from maker to recipient
    uint256 makerTokenAmount;
    bytes takerTokenPermit;
    uint256 flagsAndPeriod; // first 16 bytes as flags, rest as period duration
    uint256 expiry;
    uint256 salt;
}

// solhint-disable-next-line func-visibility
function getConOrderHash(ConOrder memory order) pure returns (bytes32 conOrderHash) {
    conOrderHash = keccak256(
        abi.encode(
            CONORDER_DATA_TYPEHASH,
            order.taker,
            order.maker,
            order.recipient,
            order.takerToken,
            order.takerTokenAmount,
            order.makerToken,
            order.makerTokenAmount,
            keccak256(order.takerTokenPermit),
            order.flagsAndPeriod,
            order.expiry,
            order.salt
        )
    );
}
