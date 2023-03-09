// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

bytes32 constant ORDER_DATA_TYPEHASH = 0xc504a4b52a554e816ce9776f48b79578cb4662dfb598d100bffef2eea538c5a5;

string constant ORDER_TYPESTRING = "Order(address maker,address taker,address inputToken,bytes inputTokenPermit,address outputToken,bytes outputTokenPermit,uint256 inputAmount,uint256 outputAmount,uint256 minOutputAmount,address recipient,uint256 expiry,uint256 salt";

/*
    keccak256(
        abi.encodePacked(
            "Order(",
            "address maker,",
            "address taker,",
            "address inputToken,",
            "bytes inputTokenPermit,",
            "address outputToken,",
            "bytes outputTokenPermit,",
            "uint256 inputAmount,",
            "uint256 outputAmount,",
            "uint256 minOutputAmount,",
            "address recipient,",
            "uint256 expiry,",
            "uint256 salt",
            ")"
        )
    );
    */

struct Order {
    address payable maker;
    address taker;
    address inputToken;
    bytes inputTokenPermit;
    address outputToken;
    bytes outputTokenPermit;
    uint256 inputAmount;
    uint256 outputAmount;
    uint256 minOutputAmount;
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
                order.maker,
                order.taker,
                order.inputToken,
                order.inputTokenPermit,
                order.outputToken,
                order.outputTokenPermit,
                order.inputAmount,
                order.outputAmount,
                order.minOutputAmount,
                order.recipient,
                order.expiry,
                order.salt
            )
        );
}
