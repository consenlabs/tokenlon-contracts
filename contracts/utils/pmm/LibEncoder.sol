pragma solidity 0.7.6;

import "./LibEIP712.sol";

contract LibEncoder is LibEIP712 {
    // Hash for the EIP712 ZeroEx Transaction Schema
    bytes32 internal constant EIP712_ZEROEX_TRANSACTION_SCHEMA_HASH =
        keccak256(abi.encodePacked("ZeroExTransaction(", "uint256 salt,", "address signerAddress,", "bytes data", ")"));

    function encodeTransactionHash(
        uint256 salt,
        address signerAddress,
        bytes memory data
    ) internal view returns (bytes32 result) {
        bytes32 schemaHash = EIP712_ZEROEX_TRANSACTION_SCHEMA_HASH;
        bytes32 dataHash = keccak256(data);

        // Assembly for more efficiently computing:
        // keccak256(abi.encodePacked(
        //     EIP712_ZEROEX_TRANSACTION_SCHEMA_HASH,
        //     salt,
        //     bytes32(signerAddress),
        //     keccak256(data)
        // ));

        assembly {
            // Load free memory pointer
            let memPtr := mload(64)

            mstore(memPtr, schemaHash) // hash of schema
            mstore(add(memPtr, 32), salt) // salt
            mstore(add(memPtr, 64), and(signerAddress, 0xffffffffffffffffffffffffffffffffffffffff)) // signerAddress
            mstore(add(memPtr, 96), dataHash) // hash of data

            // Compute hash
            result := keccak256(memPtr, 128)
        }
        result = hashEIP712Message(result);
        return result;
    }
}
