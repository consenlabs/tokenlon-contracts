// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IERC1271Wallet Interface
/// @author imToken Labs
/// @notice Interface for contracts that support ERC-1271 signature validation.
/// @dev This interface defines a function to check the validity of a signature for a given hash.
interface IERC1271Wallet {
    /// @notice Checks if a signature is valid for a given hash.
    /// @dev Returns a magic value of 0x1626ba7e if the signature is valid, otherwise returns an error.
    /// @param _hash The hash that was signed.
    /// @param _signature The signature bytes.
    /// @return magicValue The ERC-1271 magic value (0x1626ba7e) if the signature is valid, otherwise returns an error.
    function isValidSignature(bytes32 _hash, bytes calldata _signature) external view returns (bytes4 magicValue);
}
