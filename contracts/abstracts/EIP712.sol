// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title EIP712 Contract
/// @author imToken Labs
/// @notice This contract implements the EIP-712 standard for structured data hashing and signing.
/// @dev This contract provides functions to handle EIP-712 domain separator and hash calculation.
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

    /// @notice Initialize the original chain ID and domain separator.
    /// @dev Constructor to set the initial originalChainId and the originalEIP712DomainSeparator.
    constructor() {
        originalChainId = block.chainid;
        originalEIP712DomainSeparator = _buildDomainSeparator();
    }

    /// @notice Internal function to build the EIP712 domain separator hash.
    /// @dev Constructs the EIP712 domain separator hash based on the current contract's parameters.
    /// @return The EIP712 domain separator hash.
    function _buildDomainSeparator() private view returns (bytes32) {
        return keccak256(abi.encode(EIP712_TYPE_HASH, EIP712_HASHED_NAME, EIP712_HASHED_VERSION, block.chainid, address(this)));
    }

    /// @notice Internal function to get the current EIP712 domain separator.
    /// @dev Retrieves the current EIP712 domain separator hash, either the original one or the updated one if chain ID changes.
    /// @return The current EIP712 domain separator.
    function _getDomainSeparator() private view returns (bytes32) {
        if (block.chainid == originalChainId) {
            return originalEIP712DomainSeparator;
        } else {
            return _buildDomainSeparator();
        }
    }

    /// @notice Calculate the EIP712 hash of a structured data hash.
    /// @dev Calculates the EIP712 hash by hashing the EIP191 header, domain separator, and structured data hash.
    /// @param structHash The hash of the structured data.
    /// @return The EIP712 hash of the structured data.
    function getEIP712Hash(bytes32 structHash) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(EIP191_HEADER, _getDomainSeparator(), structHash));
    }

    /// @notice Get the current EIP712 domain separator.
    /// @dev Retrieves the current EIP712 domain separator hash.
    /// @return The current EIP712 domain separator.
    function EIP712_DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _getDomainSeparator();
    }
}
