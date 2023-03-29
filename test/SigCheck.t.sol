// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import { Test } from "forge-std/Test.sol";
import { IERC1271Wallet } from "contracts/interfaces/IERC1271Wallet.sol";
import { SigCheck } from "contracts/utils/SigCheck.sol";
import { MockERC1271Wallet } from "test/mocks/MockERC1271Wallet.sol";
import { ECDSA } from "@openzeppelin/contracts/cryptography/ECDSA.sol";

contract SigCheckTest is Test {
    uint256 userPrivateKey = 1234;
    uint256 walletAdminPrivateKey = 5678;
    bytes32 digest = keccak256("EIP-712 data");
    MockERC1271Wallet mockERC1271Wallet;

    function setUp() public {
        mockERC1271Wallet = new MockERC1271Wallet(vm.addr(walletAdminPrivateKey));
    }

    function testEIP712Signature() public {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);
        assertTrue(SigCheck.isValidSignature(vm.addr(userPrivateKey), digest, signature));
    }

    function testEIP712WithDifferentSigner() public {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);
        assertFalse(SigCheck.isValidSignature(vm.addr(walletAdminPrivateKey), digest, signature));
    }

    function testEIP712WithWrongHash() public {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);
        bytes32 otherDigest = keccak256("other data other data");
        assertFalse(SigCheck.isValidSignature(vm.addr(walletAdminPrivateKey), otherDigest, signature));
    }

    function testEIP712WithWrongSignatureLength() public {
        uint256 v = 1;
        uint256 r = 2;
        uint256 s = 3;
        // should have 96 bytes signature
        bytes memory signature = abi.encodePacked(r, s, v);
        // will be reverted in OZ ECDSA lib
        vm.expectRevert("ECDSA: invalid signature length");
        SigCheck.isValidSignature(vm.addr(userPrivateKey), digest, signature);
    }

    function testEIP712WithEmptySignature() public {
        bytes memory signature;
        // will be reverted in OZ ECDSA lib
        vm.expectRevert("ECDSA: invalid signature length");
        SigCheck.isValidSignature(vm.addr(userPrivateKey), digest, signature);
    }

    function testEIP1271Signature() public {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(walletAdminPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);
        assertTrue(SigCheck.isValidSignature(address(mockERC1271Wallet), digest, signature));
    }

    function testEIP1271WithDifferentSigner() public {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);
        vm.expectRevert("MockERC1271Wallet: invalid signature");
        SigCheck.isValidSignature(address(mockERC1271Wallet), digest, signature);
    }

    function testEIP1271WithZeroAddressSigner() public {
        (, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);
        // change the value of v so ecrecover will return address(0)
        bytes memory signature = abi.encodePacked(r, s, uint8(10));
        // OZ ECDSA lib will handle the zero address case and throw error instead
        // so the zero address will never be matched
        vm.expectRevert("ECDSA: invalid signature 'v' value");
        SigCheck.isValidSignature(address(0), digest, signature);
    }

    function testEIP1271WithWrongReturnValue() public {
        NonStandard1271Wallet nonWallet = new NonStandard1271Wallet();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(walletAdminPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);
        assertFalse(SigCheck.isValidSignature(address(nonWallet), digest, signature));
    }

    function testEIP1271WithNon1271Wallet() public {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(walletAdminPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);
        vm.expectRevert();
        SigCheck.isValidSignature(address(this), digest, signature);
    }
}

contract NonStandard1271Wallet is IERC1271Wallet {
    bytes4 public constant nonStandardReturnVal = 0x12345678;

    function isValidSignature(bytes32 _hash, bytes calldata _signature) external pure override returns (bytes4) {
        ECDSA.recover(_hash, _signature);
        return nonStandardReturnVal;
    }

    //  To be deprecated
    function isValidSignature(bytes calldata _data, bytes calldata _signature) external pure override returns (bytes4) {
        ECDSA.recover(keccak256(_data), _signature);
        return nonStandardReturnVal;
    }
}
