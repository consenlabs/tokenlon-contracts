pragma solidity ^0.6.5;
pragma experimental ABIEncoderV2;

library AMMWrapperStorage {
    bytes32 private constant STORAGE_SLOT = 0xbf49677e3150252dfa801a673d2d5ec21eaa360a4674864e55e79041e3f65a6b;


    /// @dev Storage bucket for proxy contract.
    struct Storage {
        // The address of the AMMWrapper contract.
        address ammWrapperAddr;
        // Is AMM enabled
        bool isEnabled;
    }

    /// @dev Get the storage bucket for this contract.
    function getStorage() internal pure returns (Storage storage stor) {
        assert(STORAGE_SLOT == bytes32(uint256(keccak256("userproxy.ammwrapper.storage")) - 1));
        bytes32 slot = STORAGE_SLOT;

        // Dip into assembly to change the slot pointed to by the local
        // variable `stor`.
        // See https://solidity.readthedocs.io/en/v0.6.8/assembly.html?highlight=slot#access-to-external-variables-functions-and-libraries
        assembly { stor_slot := slot }
    }
}

library PMMStorage {
    bytes32 private constant STORAGE_SLOT = 0x8f135983375ba6442123d61647e7325c1753eabc2e038e44d3b888a970def89a;


    /// @dev Storage bucket for proxy contract.
    struct Storage {
        // The address of the PMM contract.
        address pmmAddr;
        // Is PMM enabled
        bool isEnabled;
    }

    /// @dev Get the storage bucket for this contract.
    function getStorage() internal pure returns (Storage storage stor) {
        assert(STORAGE_SLOT == bytes32(uint256(keccak256("userproxy.pmm.storage")) - 1));
        bytes32 slot = STORAGE_SLOT;

        // Dip into assembly to change the slot pointed to by the local
        // variable `stor`.
        // See https://solidity.readthedocs.io/en/v0.6.8/assembly.html?highlight=slot#access-to-external-variables-functions-and-libraries
        assembly { stor_slot := slot }
    }
}

library RFQStorage {
    bytes32 private constant STORAGE_SLOT = 0x857df08bd185dc66e3cc5e11acb4e1dd65290f3fee6426f52f84e8faccf229cf;


    /// @dev Storage bucket for proxy contract.
    struct Storage {
        // The address of the RFQ contract.
        address rfqAddr;
        // Is RFQ enabled
        bool isEnabled;
    }

    /// @dev Get the storage bucket for this contract.
    function getStorage() internal pure returns (Storage storage stor) {
        assert(STORAGE_SLOT == bytes32(uint256(keccak256("userproxy.rfq.storage")) - 1));
        bytes32 slot = STORAGE_SLOT;

        // Dip into assembly to change the slot pointed to by the local
        // variable `stor`.
        // See https://solidity.readthedocs.io/en/v0.6.8/assembly.html?highlight=slot#access-to-external-variables-functions-and-libraries
        assembly { stor_slot := slot }
    }
}