// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import { TestSignatureValidator, NonStandard1271Wallet } from "./Setup.t.sol";
import { validateSignature, SignatureType } from "contracts/utils/SignatureValidator.sol";
import { MockZX1271Wallet } from "test/mocks/MockZX1271Wallet.sol";

contract TestWallet is TestSignatureValidator {
    uint8 public constant sigType = uint8(SignatureType.ZX1271);

    uint256 walletAdminPrivateKey = 5678;
    MockZX1271Wallet mockZX1271Wallet;

    function setUp() public {
        mockZX1271Wallet = new MockZX1271Wallet(vm.addr(walletAdminPrivateKey));
    }

    function testWalletWithDifferentSigner() public {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v, sigType);
        vm.expectRevert("MockZX1271Wallet: invalid signature");
        validateSignature(address(mockZX1271Wallet), digest, signature);
    }

    function testWalletWithWrongReturnValue() public {
        NonStandard1271Wallet nonWallet = new NonStandard1271Wallet();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(walletAdminPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v, sigType);
        assertFalse(validateSignature(address(nonWallet), digest, signature));
    }

    function testWalletWithNon1271Wallet() public {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(walletAdminPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v, sigType);
        vm.expectRevert();
        validateSignature(address(this), digest, signature);
    }

    function testWallet() public {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(walletAdminPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v, sigType);
        assertTrue(validateSignature(address(mockZX1271Wallet), digest, signature));
    }

    // regression test using known valid signature data, may failed if signer changed
    function testPartnerWallet() public {
        address partnerWallet = 0xB3C839dbde6B96D37C56ee4f9DAd3390D49310Aa;
        bytes32 dataHash = hex"25509214720fa604326a244c278f72a5c5cf3ddc0d182921f6ad97c2dc65ab16";
        bytes
            memory rawSig = hex"1cc59b2744dde0eee0d8f7e45e664fea0118ec0a632e1cc8f38928e183fe7c0b2c247c9d657aad49730573226fab25aa7689e4d199adbd3210c20e4e9e7e29946be88ba07ed95488553c0fd946f9f1445875b5c9b80012";
        bytes memory signature = abi.encodePacked(rawSig, sigType);
        assertTrue(validateSignature(partnerWallet, dataHash, signature));
    }

    // regression test using known valid signature data, may failed if signer changed
    function testBTCDealerWallet() public {
        address BTCDealerWallet = 0x3b938E9525e14361091ee464D8AceC291b3caE50;
        bytes32 dataHash = hex"acf81582c20f1545dda4144cb51d3418f472667770a23d889673a07d8df4f0b7";
        bytes
            memory rawSig = hex"1b87437e2fcf5c46939b8ca861efe0a5b3966fd5aeaf22bee708b4edaa9476b9493a85a56f1e2d7c1297e9a4dc15ec2863d278c2c5d7272f9b60d4197a4a5c7fd2c810943ab2035be0fef0b0859883677e26a19910000a";
        bytes memory signature = abi.encodePacked(rawSig, sigType);
        assertTrue(validateSignature(BTCDealerWallet, dataHash, signature));
    }
}
