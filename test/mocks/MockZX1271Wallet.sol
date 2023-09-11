// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "@openzeppelin/contracts/cryptography/ECDSA.sol";
import "contracts/interfaces/IERC1271Wallet.sol";

contract MockZX1271Wallet is IERC1271Wallet {
    bytes4 public constant ZX1271_MAGICVALUE = bytes4(keccak256("isValidWalletSignature(bytes32,address,bytes)"));

    address public operator;

    constructor(address _operator) {
        operator = _operator;
    }

    function isValidSignature(bytes32 _hash, bytes calldata _signature) external view override returns (bytes4 magicValue) {
        require(operator == ECDSA.recover(_hash, _signature), "MockZX1271Wallet: invalid signature");
        return ZX1271_MAGICVALUE;
    }
}
