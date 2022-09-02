// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import "./utils/UserProxyStorage.sol";
import "./utils/Multicall.sol";

/**
 * @dev UserProxy contract
 */
contract UserProxy is Multicall {
    // Below are the variables which consume storage slots.
    address public operator;
    string public version; // Current version of the contract

    // Operator events
    event TransferOwnership(address newOperator);
    event SetAMMStatus(bool enable);
    event UpgradeAMMWrapper(address newAMMWrapper);
    event SetRFQStatus(bool enable);
    event UpgradeRFQ(address newRFQ);
    event SetLimitOrderStatus(bool enable);
    event UpgradeLimitOrder(address newLimitOrder);

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
    function initialize(address _operator) external {
        require(keccak256(abi.encodePacked(version)) == keccak256(abi.encodePacked("")), "UserProxy: not upgrading from empty");
        require(_operator != address(0), "UserProxy: operator can not be zero address");
        operator = _operator;

        // Upgrade version
        version = "5.3.0";
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

    function rfqAddr() public view returns (address) {
        return RFQStorage.getStorage().rfqAddr;
    }

    function isRFQEnabled() public view returns (bool) {
        return RFQStorage.getStorage().isEnabled;
    }

    function limitOrderAddr() public view returns (address) {
        return LimitOrderStorage.getStorage().limitOrderAddr;
    }

    function isLimitOrderEnabled() public view returns (bool) {
        return LimitOrderStorage.getStorage().isEnabled;
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

    function setLimitOrderStatus(bool _enable) public onlyOperator {
        LimitOrderStorage.getStorage().isEnabled = _enable;

        emit SetLimitOrderStatus(_enable);
    }

    /**
     * @dev Update Limit Order contract address. Used only when ABI of Limit Order remain unchanged.
     * Otherwise, UserProxy contract should be upgraded altogether.
     */
    function upgradeLimitOrder(address _newLimitOrderAddr, bool _enable) external onlyOperator {
        LimitOrderStorage.getStorage().limitOrderAddr = _newLimitOrderAddr;
        LimitOrderStorage.getStorage().isEnabled = _enable;

        emit UpgradeLimitOrder(_newLimitOrderAddr);
        emit SetLimitOrderStatus(_enable);
    }

    /************************************************************
     *                   External functions                      *
     *************************************************************/
    /**
     * @dev proxy the call to AMM
     */
    function toAMM(bytes calldata _payload) external payable {
        require(isAMMEnabled(), "UserProxy: AMM is disabled");

        (bool callSucceed, ) = ammWrapperAddr().call{ value: msg.value }(_payload);
        if (!callSucceed) {
            // revert with data from last call
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
        require(msg.sender == tx.origin, "UserProxy: only EOA");

        (bool callSucceed, ) = rfqAddr().call{ value: msg.value }(_payload);
        if (!callSucceed) {
            // revert with data from last call
            assembly {
                let ptr := mload(0x40)
                let size := returndatasize()
                returndatacopy(ptr, 0, size)
                revert(ptr, size)
            }
        }
    }

    /**
     * @dev proxy the call to Limit Order
     */
    function toLimitOrder(bytes calldata _payload) external {
        require(isLimitOrderEnabled(), "UserProxy: Limit Order is disabled");
        require(msg.sender == tx.origin, "UserProxy: only EOA");

        (bool callSucceed, ) = limitOrderAddr().call(_payload);
        if (!callSucceed) {
            // revert with data from last call
            assembly {
                let ptr := mload(0x40)
                let size := returndatasize()
                returndatacopy(ptr, 0, size)
                revert(ptr, size)
            }
        }
    }
}
