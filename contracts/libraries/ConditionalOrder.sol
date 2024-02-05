// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

string constant CONORDER_TYPESTRING = "ConOrder(address taker,address maker,address recipient,address takerToken,uint256 totalTakerTokenAmount,address makerToken,uint256 minMakerTokenAmount,uint256 flagsAndPeriod,uint256 expiry,uint256 salt)";

bytes32 constant CONORDER_DATA_TYPEHASH = keccak256(bytes(CONORDER_TYPESTRING));

// @note remember to modify the CONORDER_TYPESTRING if modify the conOrder struct
struct ConOrder {
    address taker;
    address payable maker; // only maker can fill this ConOrder
    address payable recipient;
    address takerToken; // from user to maker
    uint256 totalTakerTokenAmount;
    address makerToken; // from maker to recipient
    uint256 minMakerTokenAmount;
    uint256 flagsAndPeriod; // first 16 bytes as flags, rest as period duration
    uint256 expiry;
    uint256 salt;
}

// solhint-disable-next-line func-visibility
function getConOrderHash(ConOrder calldata order) pure returns (bytes32) {
    return
        keccak256(
            abi.encode(
                CONORDER_DATA_TYPEHASH,
                order.taker,
                order.maker,
                order.recipient,
                order.takerToken,
                order.totalTakerTokenAmount,
                order.makerToken,
                order.minMakerTokenAmount,
                order.flagsAndPeriod,
                order.expiry,
                order.salt
            )
        );
}
