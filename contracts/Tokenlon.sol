// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "./upgrade_proxy/TransparentUpgradeableProxy.sol";

contract Tokenlon is TransparentUpgradeableProxy {
    constructor(address _logic, address _admin, bytes memory _data) public payable TransparentUpgradeableProxy(_logic, _admin, _data) {}
}