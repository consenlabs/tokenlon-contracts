// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

library LibPionexContractOrderStorage {
    bytes32 private constant STORAGE_SLOT = 0x95a5390854dc73a7f7b647527d9be60908d60f6434dd66098c304c2918e6d1a1;
    /// @dev Storage bucket for this feature.
    struct Storage {
        // How much maker token has been filled in order.
        mapping(bytes32 => uint256) orderHashToMakerTokenFilledAmount;
        // Whether order is cancelled or not.
        mapping(bytes32 => bool) orderHashToCancelled;
    }

    /// @dev Get the storage bucket for this contract.
    function getStorage() internal pure returns (Storage storage stor) {
        assert(STORAGE_SLOT == bytes32(uint256(keccak256("pionexcontract.order.storage")) - 1));

        // Dip into assembly to change the slot pointed to by the local
        // variable `stor`.
        // See https://solidity.readthedocs.io/en/v0.6.8/assembly.html?highlight=slot#access-to-external-variables-functions-and-libraries
        assembly {
            stor.slot := STORAGE_SLOT
        }
    }
}
