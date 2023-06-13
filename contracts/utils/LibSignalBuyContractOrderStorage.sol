// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

library LibSignalBuyContractOrderStorage {
    bytes32 private constant STORAGE_SLOT = 0x1360fb69f36f46eb45cf50ca3a6184b38e4ef3bde9e5aff734dccec027d7b9f7;
    /// @dev Storage bucket for this feature.
    struct Storage {
        // Has the fill been executed.
        mapping(bytes32 => bool) fillSeen;
        // Has the allowFill been executed.
        mapping(bytes32 => bool) allowFillSeen;
        // How much maker token has been filled in order.
        mapping(bytes32 => uint256) orderHashToUserTokenFilledAmount;
        // Whether order is cancelled or not.
        mapping(bytes32 => bool) orderHashToCancelled;
    }

    /// @dev Get the storage bucket for this contract.
    function getStorage() internal pure returns (Storage storage stor) {
        assert(STORAGE_SLOT == bytes32(uint256(keccak256("signalbuycontract.order.storage")) - 1));

        // Dip into assembly to change the slot pointed to by the local
        // variable `stor`.
        // See https://solidity.readthedocs.io/en/v0.6.8/assembly.html?highlight=slot#access-to-external-variables-functions-and-libraries
        assembly {
            stor.slot := STORAGE_SLOT
        }
    }
}
