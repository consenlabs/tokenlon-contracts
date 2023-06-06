// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

string constant ALLOWFILL_TYPESTRING = "AllowFill(bytes32 orderHash,address taker,uint256 fillAmount,uint256 expiry,uint256 salt)";

bytes32 constant ALLOWFILL_DATA_TYPEHASH = 0xeccdf497641b27c43d174b4b41badb5c6cf370f3fd99e9a47c8fb62724bd0d49;
// keccak256(ALLOWFILL_TYPESTRING);

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
