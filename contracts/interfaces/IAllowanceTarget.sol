// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IAllowanceTarget Interface
/// @author imToken Labs
/// @notice This interface defines the function for spending tokens on behalf of a user.
/// @dev Only authorized addresses can call the spend function.
interface IAllowanceTarget {
    /// @notice Error to be thrown when the caller is not authorized.
    /// @dev This error is used to ensure that only authorized addresses can spend tokens on behalf of a user.
    error NotAuthorized();

    /// @notice Spend tokens on user's behalf.
    /// @dev Only an authorized address can call this function to spend tokens on behalf of a user.
    /// @param from The user to spend tokens from.
    /// @param token The address of the token.
    /// @param to The recipient of the transfer.
    /// @param amount The amount to spend.
    function spendFromUserTo(address from, address token, address to, uint256 amount) external;
}
