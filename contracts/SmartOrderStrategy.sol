// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IERC20 } from "@openzeppelin/contracts@v5.0.2/token/ERC20/IERC20.sol";

import { AdminManagement } from "./abstracts/AdminManagement.sol";

import { ISmartOrderStrategy } from "./interfaces/ISmartOrderStrategy.sol";
import { IStrategy } from "./interfaces/IStrategy.sol";
import { IWETH } from "./interfaces/IWETH.sol";

import { Asset } from "./libraries/Asset.sol";

/// @title SmartOrderStrategy Contract
/// @author imToken Labs
/// @notice This contract allows users to execute complex token swap operations.
contract SmartOrderStrategy is ISmartOrderStrategy, AdminManagement {
    address public immutable weth;
    address public immutable genericSwap;

    /// @notice Receive function to receive ETH.
    receive() external payable {}

    /// @notice Constructor to initialize the contract with the owner, generic swap contract address, and WETH contract address.
    /// @param _owner The address of the contract owner.
    /// @param _genericSwap The address of the generic swap contract that interacts with this strategy.
    /// @param _weth The address of the WETH contract.
    constructor(address _owner, address _genericSwap, address _weth) AdminManagement(_owner) {
        genericSwap = _genericSwap;
        weth = _weth;
    }

    /// @dev Modifier to restrict access to the function only to the generic swap contract.
    modifier onlyGenericSwap() {
        if (msg.sender != genericSwap) revert NotFromGS();
        _;
    }

    /// @inheritdoc IStrategy
    function executeStrategy(address targetToken, bytes calldata strategyData) external payable onlyGenericSwap {
        Operation[] memory ops = abi.decode(strategyData, (Operation[]));
        if (ops.length == 0) revert EmptyOps();

        uint256 opsCount = ops.length;
        for (uint256 i; i < opsCount; ++i) {
            Operation memory op = ops[i];
            _call(op.dest, op.inputToken, op.ratioNumerator, op.ratioDenominator, op.dataOffset, op.value, op.data);
        }

        // unwrap WETH to ETH if targetToken is ETH
        if (Asset.isETH(targetToken)) {
            // the if statement is not fully covered by the tests even replacing `makerToken.isETH()` with `makerToken == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE`
            // and crafting some cases where targetToken is ETH and non-ETH
            uint256 wethBalance = IWETH(weth).balanceOf(address(this));

            if (wethBalance > 0) {
                // this if statement is not be fully covered because WETH withdraw will always succeed as wethBalance > 0
                IWETH(weth).withdraw(wethBalance);
            }
        }

        uint256 selfBalance = Asset.getBalance(targetToken, address(this));
        if (selfBalance > 1) {
            unchecked {
                --selfBalance;
            }
        }

        // transfer output tokens back to the generic swap contract
        Asset.transferTo(targetToken, payable(genericSwap), selfBalance);
    }

    /// @dev This function adjusts the input amount based on a ratio if specified, then calls the destination contract with data.
    /// @param _dest The destination address to call.
    /// @param _inputToken The address of the input token for the call.
    /// @param _ratioNumerator The numerator used for ratio calculation.
    /// @param _ratioDenominator The denominator used for ratio calculation.
    /// @param _dataOffset The offset in the data where the input amount is located.
    /// @param _value The amount of ETH to send with the call.
    /// @param _data Additional data to be passed with the call.
    function _call(
        address _dest,
        address _inputToken,
        uint256 _ratioNumerator,
        uint256 _ratioDenominator,
        uint256 _dataOffset,
        uint256 _value,
        bytes memory _data
    ) internal {
        // adjust amount if ratio != 0
        if (_ratioNumerator != 0) {
            uint256 inputTokenBalance = IERC20(_inputToken).balanceOf(address(this));

            // calculate input amount if ratio should be applied
            if (_ratioNumerator != _ratioDenominator) {
                if (_ratioDenominator == 0) revert ZeroDenominator();
                inputTokenBalance = (inputTokenBalance * _ratioNumerator) / _ratioDenominator;
            }
            assembly {
                mstore(add(_data, _dataOffset), inputTokenBalance)
            }
        }

        (bool success, bytes memory result) = _dest.call{ value: _value }(_data);
        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
    }
}
