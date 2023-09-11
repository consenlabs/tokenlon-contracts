// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import { TestSignatureValidator, NonStandard1271Wallet } from "./Setup.t.sol";
import { validateSignature, SignatureType } from "contracts/utils/SignatureValidator.sol";
import { MockERC1271Wallet } from "test/mocks/MockERC1271Wallet.sol";

contract TestWalletBytes32 is TestSignatureValidator {
    uint8 public constant sigType = uint8(SignatureType.Standard1271);

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
        validateSignature(address(mockERC1271Wallet), digest, signature);
    }

    function testWalletBytes32WithWrongReturnValue() public {
        NonStandard1271Wallet nonWallet = new NonStandard1271Wallet();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(walletAdminPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v, sigType);
        assertFalse(validateSignature(address(nonWallet), digest, signature));
    }

    function testWalletBytes32WithNon1271Wallet() public {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(walletAdminPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v, sigType);
        vm.expectRevert();
        validateSignature(address(this), digest, signature);
    }

    function testWalletBytes32() public {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(walletAdminPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v, sigType);
        assertTrue(validateSignature(address(mockERC1271Wallet), digest, signature));
    }
}
