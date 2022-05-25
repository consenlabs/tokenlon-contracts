pragma solidity ^0.6.0;

interface ISetAllowance {
    function setAllowance(address[] memory tokenList, address spender) external;

    function closeAllowance(address[] memory tokenList, address spender) external;
}
