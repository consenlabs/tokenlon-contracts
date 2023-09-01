// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import { Test } from "forge-std/Test.sol";
import { SignatureValidator } from "contracts/utils/SignatureValidator.sol";
import { IERC1271Wallet } from "contracts/interfaces/IERC1271Wallet.sol";
import { ECDSA } from "@openzeppelin/contracts/cryptography/ECDSA.sol";

contract TestSignatureValidator is Test {
    uint256 userPrivateKey = 1234;
    uint256 otherPrivateKey = 9875;
    bytes32 digest = keccak256("EIP-712 data");
    SignatureValidator sv = new SignatureValidator();
}

contract NonStandard1271Wallet is IERC1271Wallet {
    bytes4 public constant WRONG_MAGIC = 0x12345678;

    function isValidSignature(bytes32 _hash, bytes calldata _signature) external pure override returns (bytes4) {
        ECDSA.recover(_hash, _signature);
        return WRONG_MAGIC;
    }

    function isValidSignature(bytes calldata _data, bytes calldata _signature) external view override returns (bytes4 magicValue) {
        ECDSA.recover(keccak256(_data), _signature);
        return WRONG_MAGIC;
    }
}
