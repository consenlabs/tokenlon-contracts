// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { IERC1271Wallet } from "contracts/interfaces/IERC1271Wallet.sol";

library SignatureValidator {
    error InvalidSignatureLength();
    error InvalidSigner();

    // bytes4(keccak256("isValidSignature(bytes32,bytes)"))
    bytes4 internal constant ERC1271_MAGICVALUE = 0x1626ba7e;

    // Allowed signature types.
    enum SignatureType {
        EIP712, // 0x00 Signature using EIP712
        EthSign, // 0x01 Signed using web3.eth_sign() or Ethers wallet.signMessage()
        ContractWallet // 0x02 Standard 1271 wallet type
    }

    /**
     * @dev Verifies that a hash has been signed by the given signer.
     * @param _signerAddress  Address that should have signed the given hash.
     * @param _hash           Hash of the EIP-712 encoded data
     * @param _type           Full EIP-712 data structure that was hashed and signed
     * @param _signature      Proof that the hash has been signed by signer.
     * @return isValid True if the address recovered from the provided signature matches the input signer address.
     */
    function isValidSignature(
        address _signerAddress,
        bytes32 _hash,
        SignatureType _type,
        bytes memory _signature
    ) public view returns (bool isValid) {
        if (_signature.length != 65) {
            revert InvalidSignatureLength();
        }
        if (_signerAddress == address(0)) {
            revert InvalidSigner();
        }

        address recovered;
        if (_type == SignatureType.EIP712) {
            recovered = ECDSA.recover(_hash, _signature);
            return _signerAddress == recovered;
        } else if (_type == SignatureType.EthSign) {
            recovered = ECDSA.recover(keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", _hash)), _signature);
            return _signerAddress == recovered;
        } else {
            return ERC1271_MAGICVALUE == IERC1271Wallet(_signerAddress).isValidSignature(_hash, _signature);
        }
    }
}
