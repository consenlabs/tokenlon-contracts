// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts@v5.0.2/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts@v5.0.2/token/ERC20/utils/SafeERC20.sol";

import { Constant } from "./Constant.sol";

/// @title Asset Library
/// @author imToken Labs
/// @notice Library for handling asset operations, including ETH and ERC20 tokens
library Asset {
    using SafeERC20 for IERC20;

    /// @notice Error thrown when there is insufficient balance for a transfer
    error InsufficientBalance();

    /// @notice Error thrown when an ETH transfer fails
    error ETHTransferFailed();

    /// @notice Checks if an address is ETH
    /// @dev ETH is identified by comparing the address to Constant.ETH_ADDRESS or Constant.ZERO_ADDRESS
    /// @param addr The address to check
    /// @return true if the address is ETH, false otherwise
    function isETH(address addr) internal pure returns (bool) {
        return (addr == Constant.ETH_ADDRESS || addr == Constant.ZERO_ADDRESS);
    }

    /// @notice Gets the balance of an asset for a specific owner
    /// @dev If the asset is ETH, retrieves the ETH balance of the owner; otherwise, retrieves the ERC20 balance
    /// @param asset The address of the asset (ETH or ERC20 token)
    /// @param owner The address of the owner
    /// @return The balance of the asset owned by the owner
    function getBalance(address asset, address owner) internal view returns (uint256) {
        if (isETH(asset)) {
            return owner.balance;
        } else {
            return IERC20(asset).balanceOf(owner);
        }
    }

    /// @notice Transfers an amount of asset to a recipient address
    /// @dev If the asset is ETH, transfers ETH using a low-level call; otherwise, uses SafeERC20 for ERC20 transfers
    /// @param asset The address of the asset (ETH or ERC20 token)
    /// @param to The address of the recipient
    /// @param amount The amount to transfer
    function transferTo(address asset, address payable to, uint256 amount) internal {
        if (amount > 0) {
            if (to != address(this)) {
                if (isETH(asset)) {
                    // @dev Forward all available gas and may cause reentrancy
                    if (address(this).balance < amount) revert InsufficientBalance();
                    (bool success, ) = to.call{ value: amount }("");
                    if (!success) revert ETHTransferFailed();
                } else {
                    IERC20(asset).safeTransfer(to, amount);
                }
            }
        }
    }
}
