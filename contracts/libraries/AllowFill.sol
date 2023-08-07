// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

string constant ALLOWFILL_TYPESTRING = "AllowFill(bytes32 orderHash,address taker,uint256 fillAmount,uint256 expiry,uint256 salt)";

bytes32 constant ALLOWFILL_DATA_TYPEHASH = keccak256(bytes(ALLOWFILL_TYPESTRING));

struct AllowFill {
    bytes32 orderHash;
    address taker;
    uint256 fillAmount;
    uint256 expiry;
    uint256 salt;
}

// solhint-disable-next-line func-visibility
function getAllowFillHash(AllowFill memory allowFill) pure returns (bytes32) {
    return keccak256(abi.encode(ALLOWFILL_DATA_TYPEHASH, allowFill.orderHash, allowFill.taker, allowFill.fillAmount, allowFill.expiry, allowFill.salt));
}
