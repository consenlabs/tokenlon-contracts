// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;

interface ISetAllowance {
    function setAllowance(address[] memory tokenList, address spender) external;

    function closeAllowance(address[] memory tokenList, address spender) external;
}
