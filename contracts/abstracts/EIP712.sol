// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title EIP712 Contract
/// @author imToken Labs
/// @notice This contract implements the EIP-712 standard for structured data hashing and signing.
/// @dev This contract provides functions to handle EIP-712 domain separator and hash calculation.
abstract contract EIP712 {
    // EIP-712 Domain
    string public constant EIP712_NAME = "Tokenlon";
    string public constant EIP712_VERSION = "v6";
    bytes32 public constant EIP712_TYPE_HASH = keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant EIP712_HASHED_NAME = keccak256(bytes(EIP712_NAME));
    bytes32 private constant EIP712_HASHED_VERSION = keccak256(bytes(EIP712_VERSION));

    uint256 public immutable originalChainId;
    bytes32 public immutable originalEIP712DomainSeparator;

    /// @notice Initialize the original chain ID and domain separator.
    constructor() {
        originalChainId = block.chainid;
        originalEIP712DomainSeparator = _buildDomainSeparator();
    }

    /// @notice Internal function to build the EIP712 domain separator hash.
    /// @return The EIP712 domain separator hash.
    function _buildDomainSeparator() private view returns (bytes32) {
        return keccak256(abi.encode(EIP712_TYPE_HASH, EIP712_HASHED_NAME, EIP712_HASHED_VERSION, block.chainid, address(this)));
    }

    /// @notice Internal function to get the current EIP712 domain separator.
    /// @return The current EIP712 domain separator.
    function _getDomainSeparator() private view returns (bytes32) {
        if (block.chainid == originalChainId) {
            return originalEIP712DomainSeparator;
        } else {
            return _buildDomainSeparator();
        }
    }

    /// @notice Calculate the EIP712 hash of a structured data hash.
    /// @param structHash The hash of the structured data.
    /// @return digest The EIP712 hash of the structured data.
    function getEIP712Hash(bytes32 structHash) internal view returns (bytes32 digest) {
        // return keccak256(abi.encodePacked("\x19\x01", _getDomainSeparator(), structHash));

        digest = _getDomainSeparator();

        // solhint-disable no-inline-assembly
        assembly {
            // Compute the digest.
            mstore(0x00, 0x1901000000000000000000000000000000000000000000000000000000000000) // Store "\x19\x01".
            mstore(0x02, digest) // Store the domain separator.
            mstore(0x22, structHash) // Store the struct hash.
            digest := keccak256(0x0, 0x42)
            mstore(0x22, 0) // Restore the part of the free memory slot that was overwritten.
        }
    }

    /// @notice Get the current EIP712 domain separator.
    /// @return The current EIP712 domain separator.
    function EIP712_DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _getDomainSeparator();
    }
}
