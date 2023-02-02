// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

function getEIP712Hash(bytes32 domainSeparator, bytes32 structHash) pure returns (bytes32) {
    string memory EIP191_HEADER = "\x19\x01";
    return keccak256(abi.encodePacked(EIP191_HEADER, domainSeparator, structHash));
}

function computeEIP712DomainSeparator(address verifyingContract) pure returns (bytes32) {
    uint256 CHAIN_ID = 1;
    bytes32 EIP712_DOMAIN_SEPARATOR = keccak256(
        abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256(bytes("Tokenlon")),
            keccak256(bytes("v5")),
            CHAIN_ID,
            verifyingContract
        )
    );
    return EIP712_DOMAIN_SEPARATOR;
}
