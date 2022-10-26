// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;

/// @title IStrategyBase Interface
/// @author imToken Labs
interface IStrategyBase {
    /// @notice emitted when spender address is updated
    /// @param newSpender the address of the new spender
    event UpgradeSpender(address newSpender);

    /// @notice emitted when allowing another account to spend assets
    /// @param spender the address that is allowed to transfer tokens
    event AllowTransfer(address indexed spender, address token);

    /// @notice emitted when disallowing an account to spend assets
    /// @param spender the address that will be removed from allowing list
    event DisallowTransfer(address indexed spender, address token);

    /// @notice emitted when ETH converted to WETH
    /// @param amount the amount of coverted ETH
    event DepositETH(uint256 amount);

    /// @notice update the address of tokenlon spender
    /// @notice called by owner only
    /// @param _newSpender the address of the new spender
    function upgradeSpender(address _newSpender) external;

    /// @notice set allowance of tokens to an address
    /// @notice called by owner only
    /// @param _tokenList the list of tokens
    /// @param _spender the address that will be allowed
    function setAllowance(address[] calldata _tokenList, address _spender) external;

    /// @notice clear allowance of tokens of an address
    /// @notice called by owner only
    /// @param _tokenList the list of tokens
    /// @param _spender the address that will be cleared
    function closeAllowance(address[] calldata _tokenList, address _spender) external;

    /// @notice convert ETH in this contract to WETH
    /// @notice called by owner only
    function depositETH() external;
}
