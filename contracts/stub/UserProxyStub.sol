// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "../utils/Multicall.sol";

contract UserProxyStub is Multicall {
    using SafeERC20 for IERC20;

    // Constants do not have storage slot.
    uint256 private constant MAX_UINT = 2**256 - 1;
    address private constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address private constant ZERO_ADDRESS = address(0);

    /**
     * @dev Below are the variables which consume storage slots.
     */
    address public operator;
    address public weth;
    address public ammWrapperAddr;
    address public pmmAddr;
    address public rfqAddr;
    address public limitOrderAddr;
    address public l2DepositAddr;

    receive() external payable {}

    /**
     * @dev Access control and ownership management.
     */
    modifier onlyOperator() {
        require(operator == msg.sender, "UserProxyStub: not the operator");
        _;
    }

    /* End of access control and ownership management */

    /**
     * @dev Replacing constructor and initialize the contract. This function should only be called once.
     */
    constructor(address _weth) {
        operator = msg.sender;
        weth = _weth;
    }

    function upgradePMM(address _pmmAddr) external onlyOperator {
        pmmAddr = _pmmAddr;
    }

    function upgradeAMMWrapper(address _ammWrapperAddr) external onlyOperator {
        ammWrapperAddr = _ammWrapperAddr;
    }

    function upgradeRFQ(address _rfqAddr) external onlyOperator {
        rfqAddr = _rfqAddr;
    }

    function upgradeLimitOrder(address _limitOrderAddr) external onlyOperator {
        limitOrderAddr = _limitOrderAddr;
    }

    function upgradeL2Deposit(address _l2DepositAddr) external onlyOperator {
        l2DepositAddr = _l2DepositAddr;
    }

    function toAMM(bytes calldata _payload) external payable {
        (bool callSucceed, ) = ammWrapperAddr.call{ value: msg.value }(_payload);
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

    function toPMM(bytes calldata _payload) external payable {
        (bool callSucceed, ) = pmmAddr.call{ value: msg.value }(_payload);
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

    function toRFQ(bytes calldata _payload) external payable {
        (bool callSucceed, ) = rfqAddr.call{ value: msg.value }(_payload);
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

    function toLimitOrder(bytes calldata _payload) external payable {
        (bool callSucceed, ) = limitOrderAddr.call{ value: msg.value }(_payload);
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

    function toL2Deposit(bytes calldata _payload) external payable {
        (bool callSucceed, ) = l2DepositAddr.call{ value: msg.value }(_payload);
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
