// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

library LibOrderStorage {
    bytes32 private constant STORAGE_SLOT = 0x341a85fd45142738553ca9f88acd66d751d05662e7332a1dd940f22830435fb4;
    /// @dev Storage bucket for this feature.
    struct Storage {
        // How much taker token has been filled in order.
        mapping(bytes32 => uint256) orderHashToTakerTokenFilledAmount;
        // Whether order is cancelled or not.
        mapping(bytes32 => bool) orderHashToCancelled;
    }

    /// @dev Get the storage bucket for this contract.
    function getStorage() internal pure returns (Storage storage stor) {
        assert(STORAGE_SLOT == bytes32(uint256(keccak256("limitorder.order.storage")) - 1));

        // Dip into assembly to change the slot pointed to by the local
        // variable `stor`.
        // See https://solidity.readthedocs.io/en/v0.6.8/assembly.html?highlight=slot#access-to-external-variables-functions-and-libraries
        assembly {
            stor.slot := STORAGE_SLOT
        }
    }
}
