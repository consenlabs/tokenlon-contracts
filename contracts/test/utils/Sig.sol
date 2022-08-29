// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

function getEIP712Hash(bytes32 domainSeparator, bytes32 structHash) pure returns (bytes32) {
    string memory EIP191_HEADER = "\x19\x01";
    return keccak256(abi.encodePacked(EIP191_HEADER, domainSeparator, structHash));
}
