// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/drafts/ERC20Permit.sol";

import { MockERC20 } from "./MockERC20.sol";

contract MockERC20Permit is ERC20Permit, MockERC20 {
    // solhint-disable-next-line var-name-mixedcase
    bytes32 public constant _PERMIT_TYPEHASH = keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    constructor(string memory _name, string memory _symbol, uint8 _decimals) ERC20Permit(_name) MockERC20(_name, _symbol, _decimals) {}
}
