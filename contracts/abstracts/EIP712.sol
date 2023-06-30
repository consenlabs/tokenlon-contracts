// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

abstract contract EIP712 {
    // EIP-191 Header
    string public constant EIP191_HEADER = "\x19\x01";

    // EIP-712 Domain
    string public constant EIP712_NAME = "Tokenlon";
    string public constant EIP712_VERSION = "v6";
    bytes32 public constant EIP712_TYPE_HASH = keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant EIP712_HASHED_NAME = keccak256(bytes(EIP712_NAME));
    bytes32 private constant EIP712_HASHED_VERSION = keccak256(bytes(EIP712_VERSION));

    uint256 public immutable originalChainId;
    bytes32 public immutable originalEIP712DomainSeparator;

    constructor() {
        originalChainId = block.chainid;
        originalEIP712DomainSeparator = _buildDomainSeparator();
    }

    function _buildDomainSeparator() private view returns (bytes32) {
        return keccak256(abi.encode(EIP712_TYPE_HASH, EIP712_HASHED_NAME, EIP712_HASHED_VERSION, block.chainid, address(this)));
    }

    function _getDomainSeparator() private view returns (bytes32) {
        if (block.chainid == originalChainId) {
            return originalEIP712DomainSeparator;
        } else {
            return _buildDomainSeparator();
        }
    }

    function getEIP712Hash(bytes32 structHash) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(EIP191_HEADER, _getDomainSeparator(), structHash));
    }

    function EIP712_DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _getDomainSeparator();
    }
}
