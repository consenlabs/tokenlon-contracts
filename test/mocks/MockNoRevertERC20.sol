// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { MockERC20 } from "test/mocks/MockERC20.sol";

/**
 * @dev Return false instead of reverting when transfer allownace or balance is not enough. (ZRX)
 */
contract MockNoRevertERC20 is MockERC20 {
    constructor() MockERC20("MockNoRevertERC20", "MNRVT", 18) {}

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        if (balanceOf(msg.sender) < amount) {
            return false;
        }
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        if (balanceOf(msg.sender) < amount || allowance(sender, msg.sender) < amount) {
            return false;
        }
        _transfer(sender, recipient, amount);
        _approve(sender, msg.sender, allowance(sender, msg.sender) - amount);
        return true;
    }
}
