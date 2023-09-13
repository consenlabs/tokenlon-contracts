// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import { TestSignatureValidator } from "./Setup.t.sol";
import { validateSignature, SignatureType } from "contracts/utils/SignatureValidator.sol";

contract TestGeneral is TestSignatureValidator {
    function testEmptySignature() public {
        bytes memory signature;
        vm.expectRevert("length greater than 0 required");
        validateSignature(vm.addr(userPrivateKey), digest, signature);
    }

    function testZeroAddressSigner() public {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v, uint8(SignatureType.EIP712));
        vm.expectRevert("invalid signer");
        validateSignature(address(0), digest, signature);
    }

    function testIllegalSignatureType() public {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v, uint8(SignatureType.Illegal));
        vm.expectRevert("incorrect signature type");
        validateSignature(vm.addr(userPrivateKey), digest, signature);
    }

    function testInvalidSignatureType() public {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v, uint8(SignatureType.Invalid));
        vm.expectRevert("incorrect signature type");
        validateSignature(vm.addr(userPrivateKey), digest, signature);
    }

    function testSignatureTypeOutOfEnumRange() public {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v, uint8(8));
        vm.expectRevert("unsupported signature type");
        validateSignature(vm.addr(userPrivateKey), digest, signature);
    }
}
