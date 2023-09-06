// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import { TestSignatureValidator, NonStandard1271Wallet } from "./Setup.t.sol";
import { SignatureValidator } from "contracts/utils/SignatureValidator.sol";
import { MockERC1271Wallet } from "test/mocks/MockERC1271Wallet.sol";

contract TestWalletBytes32 is TestSignatureValidator {
    uint8 public constant sigType = uint8(SignatureValidator.SignatureType.WalletBytes32);

    uint256 walletAdminPrivateKey = 5678;
    MockERC1271Wallet mockERC1271Wallet;

    function setUp() public {
        mockERC1271Wallet = new MockERC1271Wallet(vm.addr(walletAdminPrivateKey));
    }

    function testWalletBytes32WithDifferentSigner() public {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v, sigType);
        // MockERC1271Wallet will revert directly
        vm.expectRevert("MockERC1271Wallet: invalid signature");
        sv.isValidSignature(address(mockERC1271Wallet), digest, bytes(""), signature);
    }

    function testWalletBytes32WithWrongReturnValue() public {
        NonStandard1271Wallet nonWallet = new NonStandard1271Wallet();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(walletAdminPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v, sigType);
        assertFalse(sv.isValidSignature(address(nonWallet), digest, bytes(""), signature));
    }

    function testWalletBytes32WithNon1271Wallet() public {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(walletAdminPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v, sigType);
        vm.expectRevert();
        sv.isValidSignature(address(this), digest, bytes(""), signature);
    }

    function testWalletBytes32() public {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(walletAdminPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v, sigType);
        assertTrue(sv.isValidSignature(address(mockERC1271Wallet), digest, bytes(""), signature));
    }
}
