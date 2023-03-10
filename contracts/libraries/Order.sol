// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

string constant ORDER_TYPESTRING = "Order(address taker,address maker,address takerToken,uint256 takerTokenAmount,address makerToken,uint256 makerTokenAmount,uint256 minMakerTokenAmount,address recipient,uint256 expiry,uint256 salt)";

bytes32 constant ORDER_DATA_TYPEHASH = 0x1c5438cede24381f652038abfc93d5dc94f8ab47e14a8bb1cd7c1cd1d0c6fad2;
// keccak256(ORDER_TYPESTRING);

struct Order {
    address taker;
    address payable maker;
    address takerToken;
    uint256 takerTokenAmount;
    address makerToken;
    uint256 makerTokenAmount;
    uint256 minMakerTokenAmount;
    address payable recipient;
    uint256 expiry;
    uint256 salt;
}

// solhint-disable-next-line func-visibility
function getOrderHash(Order memory order) pure returns (bytes32) {
    return
        keccak256(
            abi.encode(
                ORDER_DATA_TYPEHASH,
                order.taker,
                order.maker,
                order.takerToken,
                order.takerTokenAmount,
                order.makerToken,
                order.makerTokenAmount,
                order.minMakerTokenAmount,
                order.recipient,
                order.expiry,
                order.salt
            )
        );
}
