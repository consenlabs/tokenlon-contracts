// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IWETH Interface
interface IWETH {
    /// @notice Returns the balance of `account`.
    /// @param account The address for which to query the balance.
    /// @return The balance of `account`.
    function balanceOf(address account) external view returns (uint256);

    /// @notice Deposits ETH into the contract and wraps it into WETH.
    function deposit() external payable;

    /// @notice Withdraws a specified amount of WETH, unwraps it into ETH, and sends it to the caller.
    /// @param amount The amount of WETH to withdraw and unwrap.
    function withdraw(uint256 amount) external;

    /// @notice Transfers a specified amount of WETH to a destination address.
    /// @param dst The recipient address to which WETH will be transferred.
    /// @param wad The amount of WETH to transfer.
    /// @return True if the transfer is successful, false otherwise.
    function transfer(address dst, uint256 wad) external returns (bool);

    /// @notice Transfers a specified amount of WETH from a source address to a destination address.
    /// @param src The sender address from which WETH will be transferred.
    /// @param dst The recipient address to which WETH will be transferred.
    /// @param wad The amount of WETH to transfer.
    /// @return True if the transfer is successful, false otherwise.
    function transferFrom(address src, address dst, uint256 wad) external returns (bool);
}
