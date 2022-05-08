// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IEmergency {
    function emergencyWithdraw(IERC20 token) external;
}
