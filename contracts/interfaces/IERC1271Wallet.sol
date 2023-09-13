// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;

interface IERC1271Wallet {
    function isValidSignature(bytes32 _hash, bytes calldata _signature) external view returns (bytes4 magicValue);
}
