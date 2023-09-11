// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import { IERC1271Wallet } from "../interfaces/IERC1271Wallet.sol";
import { LibBytes } from "./LibBytes.sol";
import { ECDSA } from "@openzeppelin/contracts/cryptography/ECDSA.sol";

// 0x1626ba7e
bytes4 constant ERC1271_MAGICVALUE = bytes4(keccak256("isValidSignature(bytes32,bytes)"));

// 0xb0671381
bytes4 constant ZX1271_MAGICVALUE = bytes4(keccak256("isValidWalletSignature(bytes32,address,bytes)"));

enum SignatureType {
    Illegal, // 0x00, default as illegal
    Invalid, // 0x01
    EIP712, // 0x02 standard EIP-712 signature
    EthSign, // 0x03 signed using web3.eth_sign() or Ethers wallet.signMessage()
    WalletBytes, // 0x04 DEPRECATED, never used
    Standard1271, // 0x05 standard EIP-1271 wallet type
    ZX1271 // 0x06 zero ex non-standard 1271 version
}

/**
 * @dev Verifies that a hash has been signed by the given signer.
 * @param _signerAddress  Address that should have signed the given hash.
 * @param _hash           Hash of the data.
 * @param _sig            Proof that the hash has been signed by signer.
 * @return isValid        True if the address recovered from the provided signature matches the input signer address.
 */
// solhint-disable-next-line func-visibility
function validateSignature(
    address _signerAddress,
    bytes32 _hash,
    bytes memory _sig
) view returns (bool isValid) {
    require(_sig.length > 0, "SignatureValidator: length greater than 0 required");
    require(_signerAddress != address(0), "SignatureValidator: invalid signer");

    // Pop last byte off of signature byte array.
    uint8 signatureTypeRaw = uint8(LibBytes.popLastByte(_sig));

    // Ensure signature is supported
    require(signatureTypeRaw <= uint8(SignatureType.ZX1271), "SignatureValidator: unsupported signature");

    // Extract signature type
    SignatureType signatureType = SignatureType(signatureTypeRaw);

    if (signatureType == SignatureType.Illegal) {
        // Always illegal signature.
        // This is always an implicit option since a signer can create a
        // signature array with invalid type or length. We may as well make
        // it an explicit option. This aids testing and analysis. It is
        // also the initialization value for the enum type.

        revert("SignatureValidator#isValidSignature: illegal signature");
    } else if (signatureType == SignatureType.EIP712) {
        // In ealier version, an extra bytes32 is packed with (v,r,s) but the field was never used.
        // So the _sig was in 97 bytes before.
        // In order to support standard 65 bytes ECDSA signature and legacy format, still spliting _sig here
        // instead of passing _sig directly to OZ ECDSA lib.

        bytes32 r = LibBytes.readBytes32(_sig, 0);
        bytes32 s = LibBytes.readBytes32(_sig, 32);
        uint8 v = uint8(_sig[64]);
        address recovered = ECDSA.recover(_hash, v, r, s);
        return _signerAddress == recovered;
    } else if (signatureType == SignatureType.EthSign) {
        // In ealier version, an extra bytes32 is packed with (v,r,s) but the field was never used.
        // So the _sig was in 97 bytes before.
        // In order to support standard 65 bytes ECDSA signature and legacy format, still spliting _sig here
        // instead of passing _sig directly to OZ ECDSA lib.

        bytes32 r = LibBytes.readBytes32(_sig, 0);
        bytes32 s = LibBytes.readBytes32(_sig, 32);
        uint8 v = uint8(_sig[64]);
        address recovered = ECDSA.recover(keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", _hash)), v, r, s);
        return _signerAddress == recovered;
    } else if (signatureType == SignatureType.Standard1271) {
        return ERC1271_MAGICVALUE == IERC1271Wallet(_signerAddress).isValidSignature(_hash, _sig);
    } else if (signatureType == SignatureType.ZX1271) {
        return ZX1271_MAGICVALUE == IERC1271Wallet(_signerAddress).isValidSignature(_hash, _sig);
    }

    // Anything else is illegal (We do not return false because
    // the signature may actually be valid, just not in a format
    // that we currently support. In this case returning false
    // may lead the caller to incorrectly believe that the
    // signature was invalid.)
    revert("SignatureValidator: unsupported signature");
}
