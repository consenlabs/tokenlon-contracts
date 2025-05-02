// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "@openzeppelin/contracts/cryptography/ECDSA.sol";

contract MockERC7702Wallet {
    // bytes4(keccak256("isValidSignature(bytes32,bytes)"))
    bytes4 internal constant ERC1271_MAGICVALUE_BYTES32 = 0x1626ba7e;

    receive() external payable {}

    function isValidSignature(bytes32 _hash, bytes calldata _signature) external view returns (bytes4 magicValue) {
        require(address(this) == ECDSA.recover(_hash, _signature), "MockERC7702Wallet: invalid signature");
        return ERC1271_MAGICVALUE_BYTES32;
    }
}
