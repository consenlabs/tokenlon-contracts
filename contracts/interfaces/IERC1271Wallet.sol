// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC1271Wallet {
    /// @notice Checks if a signature is valid for a given hash.
    /// @param _hash The hash that was signed.
    /// @param _signature The signature bytes.
    /// @return magicValue The ERC-1271 magic value (0x1626ba7e) if the signature is valid, otherwise returns an error.
    function isValidSignature(bytes32 _hash, bytes calldata _signature) external view returns (bytes4 magicValue);
}
