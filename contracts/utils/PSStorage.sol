pragma solidity ^0.6.5;
pragma experimental ABIEncoderV2;

library PSStorage {
    bytes32 private constant STORAGE_SLOT = 0x92dd52b981a2dd69af37d8a3febca29ed6a974aede38ae66e4ef773173aba471;

    struct Storage {
        address ammWrapperAddr;
        address pmmAddr;
        address wethAddr;
        address rfqAddr;
    }

    /// @dev Get the storage bucket for this contract.
    function getStorage() internal pure returns (Storage storage stor) {
        assert(STORAGE_SLOT == bytes32(uint256(keccak256("permanent.storage.storage")) - 1));
        bytes32 slot = STORAGE_SLOT;

        // Dip into assembly to change the slot pointed to by the local
        // variable `stor`.
        // See https://solidity.readthedocs.io/en/v0.6.8/assembly.html?highlight=slot#access-to-external-variables-functions-and-libraries
        assembly { stor_slot := slot }
    }
}

library AMMWrapperStorage {
    bytes32 private constant STORAGE_SLOT = 0xd38d862c9fa97c2fa857a46e08022d272a3579c114ca4f335f1e5fcb692c045e;

    struct Storage {
        mapping(bytes32 => bool) transactionSeen;
        // curve pool => underlying token address => underlying token index
        mapping(address => mapping(address => int128)) curveTokenIndexes;
        mapping(address => bool) relayerValid;
        // 5.1.0 appended storage
        // curve pool => wrapped token address => wrapped token index
        mapping(address => mapping(address => int128)) curveWrappedTokenIndexes;
        mapping(address => bool) curveSupportGetDx;
    }

    /// @dev Get the storage bucket for this contract.
    function getStorage() internal pure returns (Storage storage stor) {
        assert(STORAGE_SLOT == bytes32(uint256(keccak256("permanent.ammwrapper.storage")) - 1));
        bytes32 slot = STORAGE_SLOT;

        // Dip into assembly to change the slot pointed to by the local
        // variable `stor`.
        // See https://solidity.readthedocs.io/en/v0.6.8/assembly.html?highlight=slot#access-to-external-variables-functions-and-libraries
        assembly { stor_slot := slot }
    }
}

library RFQStorage {
    bytes32 private constant STORAGE_SLOT = 0x9174e76494cfb023ddc1eb0effb6c12e107165382bbd0ecfddbc38ea108bbe52;

    struct Storage {
        mapping(bytes32 => bool) transactionSeen;
    }

    /// @dev Get the storage bucket for this contract.
    function getStorage() internal pure returns (Storage storage stor) {
        assert(STORAGE_SLOT == bytes32(uint256(keccak256("permanent.rfq.storage")) - 1));
        bytes32 slot = STORAGE_SLOT;

        // Dip into assembly to change the slot pointed to by the local
        // variable `stor`.
        // See https://solidity.readthedocs.io/en/v0.6.8/assembly.html?highlight=slot#access-to-external-variables-functions-and-libraries
        assembly { stor_slot := slot }
    }
}