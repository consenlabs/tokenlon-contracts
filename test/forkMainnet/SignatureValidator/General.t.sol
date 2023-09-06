// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import { TestSignatureValidator } from "./Setup.t.sol";
import { SignatureValidator } from "contracts/utils/SignatureValidator.sol";

contract TestGeneral is TestSignatureValidator {
    function testEmptySignature() public {
        bytes memory signature;
        vm.expectRevert("SignatureValidator#isValidSignature: length greater than 0 required");
        sv.isValidSignature(vm.addr(userPrivateKey), digest, bytes(""), signature);
    }

    function testZeroAddressSigner() public {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v, uint8(SignatureValidator.SignatureType.EIP712));
        vm.expectRevert("SignatureValidator#isValidSignature: invalid signer");
        sv.isValidSignature(address(0), digest, bytes(""), signature);
    }

    function testInvalidSignatureType() public {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v, uint8(8));
        vm.expectRevert("SignatureValidator#isValidSignature: unsupported signature");
        sv.isValidSignature(vm.addr(userPrivateKey), digest, bytes(""), signature);
    }
}
