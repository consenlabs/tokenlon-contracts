// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import { TestSignatureValidator } from "./Setup.t.sol";

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
        assertFalse(isValidSignature(vm.addr(userPrivateKey), digest, bytes(""), signature));
    }

    function testEthSignWithWrongHash() public {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, eip191Message);
        bytes memory signature = abi.encodePacked(r, s, v, sigType);
        bytes32 otherDigest = keccak256("other data other data");
        assertFalse(isValidSignature(vm.addr(userPrivateKey), otherDigest, bytes(""), signature));
    }

    function testEthSignWithWrongSignatureLength() public {
        uint256 r = 1;
        bytes memory signature = abi.encodePacked(r, sigType);
        // should have 33 bytes signature
        assertEq(signature.length, 33);
        vm.expectRevert("SignatureValidator#isValidSignature: length 65 or 97 required");
        isValidSignature(vm.addr(userPrivateKey), digest, bytes(""), signature);
    }

    function testEthSign() public {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, eip191Message);
        bytes memory signature = abi.encodePacked(r, s, v, sigType);
        assertTrue(isValidSignature(vm.addr(userPrivateKey), digest, bytes(""), signature));
    }
}
