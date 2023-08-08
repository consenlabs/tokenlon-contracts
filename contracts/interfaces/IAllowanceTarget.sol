// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/// @title IAllowanceTarget Interface
/// @author imToken Labs
interface IAllowanceTarget {
    error NotAuthorized();

    /// @dev Spend tokens on user's behalf. Only an authority can call this.
    /// @param  from The user to spend token from.
    /// @param  token The address of the token.
    /// @param  to The recipient of the trasnfer.
    /// @param  amount Amount to spend.
    function spendFromUserTo(
        address from,
        address token,
        address to,
        uint256 amount
    ) external;
}
