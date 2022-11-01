// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;

/// @title IStrategyBase Interface
/// @author imToken Labs
interface IStrategyBase {
    /// @notice Emitted when Tokenlon spender address is updated
    /// @param newSpender The address of the new Tokenlon spender
    event UpgradeSpender(address newSpender);

    /// @notice Emitted when allowing another account to spend assets
    /// @param spender The address that is allowed to transfer tokens
    event AllowTransfer(address indexed spender, address token);

    /// @notice Emitted when disallowing an account to spend assets
    /// @param spender The address that is removed from allow list
    event DisallowTransfer(address indexed spender, address token);

    /// @notice Emitted when ETH converted to WETH
    /// @param amount The amount of converted ETH
    event DepositETH(uint256 amount);

    /// @notice Update the address of Tokenlon spender
    /// @notice Only owner can call
    /// @param _newSpender The address of the new spender
    function upgradeSpender(address _newSpender) external;

    /// @notice Set allowance of tokens to an address
    /// @notice Only owner can call
    /// @param _tokenList The list of tokens
    /// @param _spender The address that will be allowed
    function setAllowance(address[] calldata _tokenList, address _spender) external;

    /// @notice Clear allowance of tokens to an address
    /// @notice Only owner can call
    /// @param _tokenList The list of tokens
    /// @param _spender The address that will be cleared
    function closeAllowance(address[] calldata _tokenList, address _spender) external;

    /// @notice Convert ETH in this contract to WETH
    /// @notice Only owner can call
    function depositETH() external;
}
