// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import { TestSignatureValidator, NonStandard1271Wallet } from "./Setup.t.sol";
import { MockZX1271Wallet } from "test/mocks/MockZX1271Wallet.sol";

contract TestWallet is TestSignatureValidator {
    uint8 public constant sigType = uint8(SignatureType.Wallet);

    uint256 walletAdminPrivateKey = 5678;
    MockZX1271Wallet mockZX1271Wallet;

    function setUp() public {
        mockZX1271Wallet = new MockZX1271Wallet(vm.addr(walletAdminPrivateKey));
    }

    function testWalletWithDifferentSigner() public {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v, sigType);
        // MockZX1271Wallet will revert directly but SignatureValidator will revert again using `WALLET_ERROR`
        vm.expectRevert();
        vm.expectRevert("WALLET_ERROR");
        isValidSignature(address(mockZX1271Wallet), digest, bytes(""), signature);
    }

    function testWalletWithWrongReturnValue() public {
        NonStandard1271Wallet nonWallet = new NonStandard1271Wallet();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(walletAdminPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v, sigType);
        assertFalse(isValidSignature(address(nonWallet), digest, bytes(""), signature));
    }

    function testWalletWithNon1271Wallet() public {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(walletAdminPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v, sigType);
        // function mismatch will revert directly but SignatureValidator will revert again using `WALLET_ERROR`
        vm.expectRevert();
        vm.expectRevert("WALLET_ERROR");
        isValidSignature(address(this), digest, bytes(""), signature);
    }

    function testWallet() public {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(walletAdminPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v, sigType);
        assertTrue(isValidSignature(address(mockZX1271Wallet), digest, bytes(""), signature));
    }
}
