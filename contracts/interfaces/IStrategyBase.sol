// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;

interface IStrategyBase {
    event UpgradeSpender(address newSpender);
    event AllowTransfer(address indexed spender, address token);
    event DisallowTransfer(address indexed spender, address token);
    event DepositETH(uint256 ethBalance);

    function upgradeSpender(address _newSpender) external;

    function setAllowance(address[] calldata _tokenList, address _spender) external;

    function closeAllowance(address[] calldata _tokenList, address _spender) external;

    function depositETH() external;
}
