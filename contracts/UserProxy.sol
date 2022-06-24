// SPDX-License-Identifier: MIT

pragma solidity ^0.6.5;

import "./utils/lib_storage/UserProxyStorage.sol";

/**
 * @dev UserProxy contract
 */
contract UserProxy {
    // Below are the variables which consume storage slots.
    address public operator;
    string public version;  // Current version of the contract

    // Operator events
    event TransferOwnership(address newOperator);
    event SetAMMStatus(bool enable);
    event UpgradeAMMWrapper(address newAMMWrapper);
    event SetPMMStatus(bool enable);
    event UpgradePMM(address newPMM);
    event SetRFQStatus(bool enable);
    event UpgradeRFQ(address newRFQ);

    receive() external payable {}


    /************************************************************
    *          Access control and ownership management          *
    *************************************************************/
    modifier onlyOperator() {
        require(operator == msg.sender, "UserProxy: not the operator");
        _;
    }

    function transferOwnership(address _newOperator) external onlyOperator {
        require(_newOperator != address(0), "UserProxy: operator can not be zero address");
        operator = _newOperator;

        emit TransferOwnership(_newOperator);
    }


    /************************************************************
    *              Constructor and init functions               *
    *************************************************************/
    /// @dev Replacing constructor and initialize the contract. This function should only be called once.
    function initialize(address _rfqAddr, address _newAMMWrapperAddr) external {
        require(_rfqAddr != address(0), "UserProxy: _rfqAddr should not be 0");
        require(_newAMMWrapperAddr != address(0), "UserProxy: _newAMMWrapperAddr should not be 0");
        require(
            keccak256(abi.encodePacked(version)) == keccak256(abi.encodePacked("5.0.0")),
            "UserProxy: not upgrading from version 5.0.0"
        );

        // Set RFQ
        RFQStorage.getStorage().rfqAddr = _rfqAddr;
        RFQStorage.getStorage().isEnabled = true;

        // Set new AMMWrapper
        AMMWrapperStorage.getStorage().ammWrapperAddr = _newAMMWrapperAddr;
        AMMWrapperStorage.getStorage().isEnabled = true;

        // Upgrade version
        version = "5.2.0";
    }

    /************************************************************
    *                     Getter functions                      *
    *************************************************************/
    function ammWrapperAddr() public view returns (address) {
        return AMMWrapperStorage.getStorage().ammWrapperAddr;
    }

    function isAMMEnabled() public view returns (bool) {
        return AMMWrapperStorage.getStorage().isEnabled;
    }

    function pmmAddr() public view returns (address) {
        return PMMStorage.getStorage().pmmAddr;
    }

    function isPMMEnabled() public view returns (bool) {
        return PMMStorage.getStorage().isEnabled;
    }

    function rfqAddr() public view returns (address) {
        return RFQStorage.getStorage().rfqAddr;
    }

    function isRFQEnabled() public view returns (bool) {
        return RFQStorage.getStorage().isEnabled;
    }

    /************************************************************
    *           Management functions for Operator               *
    *************************************************************/
    function setAMMStatus(bool _enable) public onlyOperator {
        AMMWrapperStorage.getStorage().isEnabled = _enable;

        emit SetAMMStatus(_enable);
    }

    /**
     * @dev Update AMMWrapper contract address. Used only when ABI of AMMWrapeer remain unchanged.
     * Otherwise, UserProxy contract should be upgraded altogether.
     */
    function upgradeAMMWrapper(address _newAMMWrapperAddr, bool _enable) external onlyOperator {
        AMMWrapperStorage.getStorage().ammWrapperAddr = _newAMMWrapperAddr;
        AMMWrapperStorage.getStorage().isEnabled = _enable;

        emit UpgradeAMMWrapper(_newAMMWrapperAddr);
        emit SetAMMStatus(_enable);
    }

    function setPMMStatus(bool _enable) public onlyOperator {
        PMMStorage.getStorage().isEnabled = _enable;

        emit SetPMMStatus(_enable);
    }

    /**
     * @dev Update PMM contract address. Used only when ABI of PMM remain unchanged.
     * Otherwise, UserProxy contract should be upgraded altogether.
     */
    function upgradePMM(address _newPMMAddr, bool _enable) external onlyOperator {
        PMMStorage.getStorage().pmmAddr = _newPMMAddr;
        PMMStorage.getStorage().isEnabled = _enable;

        emit UpgradePMM(_newPMMAddr);
        emit SetPMMStatus(_enable);
    }

    function setRFQStatus(bool _enable) public onlyOperator {
        RFQStorage.getStorage().isEnabled = _enable;

        emit SetRFQStatus(_enable);
    }

    /**
     * @dev Update RFQ contract address. Used only when ABI of RFQ remain unchanged.
     * Otherwise, UserProxy contract should be upgraded altogether.
     */
    function upgradeRFQ(address _newRFQAddr, bool _enable) external onlyOperator {
        RFQStorage.getStorage().rfqAddr = _newRFQAddr;
        RFQStorage.getStorage().isEnabled = _enable;

        emit UpgradeRFQ(_newRFQAddr);
        emit SetRFQStatus(_enable);
    }


    /************************************************************
    *                   External functions                      *
    *************************************************************/
    /**
     * @dev proxy the call to AMM
     */
    function toAMM(bytes calldata _payload) external payable {
        require(isAMMEnabled(), "UserProxy: AMM is disabled");

        (bool callSucceed,) = ammWrapperAddr().call{value: msg.value}(_payload);
        if (callSucceed == false) {
            // Get the error message returned
            assembly {
                let ptr := mload(0x40)
                let size := returndatasize()
                returndatacopy(ptr, 0, size)
                revert(ptr, size)
            }
        }
    }

    /**
     * @dev proxy the call to PMM
     */
    function toPMM(bytes calldata _payload) external payable {
        require(isPMMEnabled(), "UserProxy: PMM is disabled");

        (bool callSucceed,) = pmmAddr().call{value: msg.value}(_payload);
        if (callSucceed == false) {
            // Get the error message returned
            assembly {
                let ptr := mload(0x40)
                let size := returndatasize()
                returndatacopy(ptr, 0, size)
                revert(ptr, size)
            }
        }
    }

    /**
     * @dev proxy the call to RFQ
     */
    function toRFQ(bytes calldata _payload) external payable {
        require(isRFQEnabled(), "UserProxy: RFQ is disabled");

        (bool callSucceed,) = rfqAddr().call{value: msg.value}(_payload);
        if (callSucceed == false) {
            // Get the error message returned
            assembly {
                let ptr := mload(0x40)
                let size := returndatasize()
                returndatacopy(ptr, 0, size)
                revert(ptr, size)
            }
        }
    }
}
