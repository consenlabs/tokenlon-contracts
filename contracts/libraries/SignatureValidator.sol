// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Address } from "@openzeppelin/contracts@v5.0.2/utils/Address.sol";
import { ECDSA } from "@openzeppelin/contracts@v5.0.2/utils/cryptography/ECDSA.sol";

import { IERC1271Wallet } from "../interfaces/IERC1271Wallet.sol";

/// @title Signature Validator Library
/// @author imToken Labs
/// @notice Library for validating signatures using ECDSA and ERC1271 standards
library SignatureValidator {
    using Address for address;

    // bytes4(keccak256("isValidSignature(bytes32,bytes)"))
    bytes4 internal constant ERC1271_MAGICVALUE = 0x1626ba7e;

    /// @notice Verifies that a hash has been signed by the given signer.
    /// @dev This function verifies signatures either through ERC1271 wallets or direct ECDSA recovery.
    /// @param _signerAddress Address that should have signed the given hash.
    /// @param _hash Hash of the EIP-712 encoded data.
    /// @param _signature Proof that the hash has been signed by signer.
    /// @return True if the address recovered from the provided signature matches the input signer address.
    function validateSignature(address _signerAddress, bytes32 _hash, bytes memory _signature) internal view returns (bool) {
        if (_signerAddress.code.length > 0) {
            return ERC1271_MAGICVALUE == IERC1271Wallet(_signerAddress).isValidSignature(_hash, _signature);
        } else {
            return _signerAddress == ECDSA.recover(_hash, _signature);
        }
    }
}
