// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { Ownable } from "./Ownable.sol";
import { Asset } from "../libraries/Asset.sol";

/// @title AdminManagement Contract
/// @author imToken Labs
/// @notice This contract provides administrative functions for token management.
abstract contract AdminManagement is Ownable {
    using SafeERC20 for IERC20;

    /// @notice Sets the initial owner of the contract.
    /// @param _owner The address of the owner who can execute administrative functions.
    constructor(address _owner) Ownable(_owner) {}

    /// @notice Approves multiple tokens to multiple spenders with an unlimited allowance.
    /// @dev Only the owner can call this function.
    /// @param tokens The array of token addresses to approve.
    /// @param spenders The array of spender addresses to approve for each token.
    function approveTokens(address[] calldata tokens, address[] calldata spenders) external onlyOwner {
        for (uint256 i = 0; i < tokens.length; ++i) {
            for (uint256 j = 0; j < spenders.length; ++j) {
                IERC20(tokens[i]).forceApprove(spenders[j], type(uint256).max);
            }
        }
    }

    /// @notice Rescues multiple tokens held by this contract to the specified recipient.
    /// @dev Only the owner can call this function.
    /// @param tokens An array of token addresses to rescue.
    /// @param recipient The address to which rescued tokens will be transferred.
    function rescueTokens(address[] calldata tokens, address recipient) external onlyOwner {
        for (uint256 i = 0; i < tokens.length; ++i) {
            uint256 selfBalance = Asset.getBalance(tokens[i], address(this));
            Asset.transferTo(tokens[i], payable(recipient), selfBalance);
        }
    }
}
