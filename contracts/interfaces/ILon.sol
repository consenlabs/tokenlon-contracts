// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.8.0;

import "./IEmergency.sol";
import "./IEIP2612.sol";

interface ILon is IEmergency, IEIP2612 {
  function cap() external view returns(uint256);

  function mint(address to, uint256 amount) external; 

  function burn(uint256 amount) external;
}
