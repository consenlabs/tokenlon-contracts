// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import { TestSignatureValidator } from "./Setup.t.sol";
import { validateSignature, SignatureType } from "contracts/utils/SignatureValidator.sol";

contract TestEthSign is TestSignatureValidator {
    uint8 public constant sigType = uint8(SignatureType.EthSign);
    string public constant eip191Prefix = "\x19Ethereum Signed Message:\n32";
    bytes32 public eip191Message;

    function setUp() public {
        eip191Message = keccak256(abi.encodePacked(eip191Prefix, digest));
    }

    function testEthSignWithDifferentSigner() public {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(otherPrivateKey, eip191Message);
        bytes memory signature = abi.encodePacked(r, s, v, sigType);
        assertFalse(validateSignature(vm.addr(userPrivateKey), digest, signature));
    }

    function testEthSignWithWrongHash() public {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, eip191Message);
        bytes memory signature = abi.encodePacked(r, s, v, sigType);
        bytes32 otherDigest = keccak256("other data other data");
        assertFalse(validateSignature(vm.addr(userPrivateKey), otherDigest, signature));
    }

    function testEthSignWithWrongSignatureLength() public {
        uint256 r = 1;
        bytes memory signature = abi.encodePacked(r, sigType);
        // should have 33 bytes signature
        assertEq(signature.length, 33);
        vm.expectRevert("LibBytes#readBytes32 greater or equal to 32 length required");
        validateSignature(vm.addr(userPrivateKey), digest, signature);
    }

    /// @dev old contracts still assert sigLength == 98 so has to support this format
    /// @dev the extra bytes32 is not used at all
    function testEthSignWith98BytesSig() public {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, eip191Message);
        bytes memory signature = abi.encodePacked(r, s, v, bytes32(0), sigType);
        // standard ECDSA signature : 65 bytes
        // extra bytes32 : 32 bytes
        // signatureType : 1 byte
        // total : 98 bytes
        assertEq(signature.length, 98);
        assertTrue(validateSignature(vm.addr(userPrivateKey), digest, signature));
    }

    /// @dev standard ECDSA signature format
    function testEthSign() public {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, eip191Message);
        bytes memory signature = abi.encodePacked(r, s, v, sigType);
        // standard ECDSA signature : 65 bytes
        // signatureType : 1 byte
        // total : 66 bytes
        assertEq(signature.length, 66);
        assertTrue(validateSignature(vm.addr(userPrivateKey), digest, signature));
    }
}
