// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";

import { Ownable } from "./abstracts/Ownable.sol";
import { IAllowanceTarget } from "./interfaces/IAllowanceTarget.sol";

/// @title AllowanceTarget Contract
/// @author imToken Labs
/// @notice This contract manages allowances and authorizes spenders to transfer tokens on behalf of users.
contract AllowanceTarget is IAllowanceTarget, Pausable, Ownable {
    using SafeERC20 for IERC20;

    /// @notice Mapping of authorized addresses permitted to call spendFromUserTo.
    mapping(address trustedCaller => bool isAuthorized) public authorized;

    /// @notice Constructor to initialize the contract with the owner and trusted callers.
    /// @param _owner The address of the contract owner.
    /// @param trustedCaller An array of addresses that are initially authorized to call spendFromUserTo.
    constructor(address _owner, address[] memory trustedCaller) Ownable(_owner) {
        uint256 callerCount = trustedCaller.length;
        for (uint256 i = 0; i < callerCount; ++i) {
            authorized[trustedCaller[i]] = true;
        }
    }

    /// @notice Pauses the contract, preventing the execution of spendFromUserTo.
    /// @dev Only the owner can call this function.
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpauses the contract, allowing the execution of spendFromUserTo.
    /// @dev Only the owner can call this function.
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @inheritdoc IAllowanceTarget
    function spendFromUserTo(address from, address token, address to, uint256 amount) external whenNotPaused {
        if (!authorized[msg.sender]) revert NotAuthorized();
        IERC20(token).safeTransferFrom(from, to, amount);
    }
}
