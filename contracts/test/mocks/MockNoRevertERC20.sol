// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @dev Return false instead of reverting when transfer allownace or balance is not enough. (ZRX)
 */
contract MockNoRevertERC20 is ERC20 {
    constructor() ERC20("MockNoRevertERC20", "MNRVT") {}

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        if (balanceOf(msg.sender) < amount) {
            return false;
        }
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        if (balanceOf(msg.sender) < amount || allowance(sender, msg.sender) < amount) {
            return false;
        }
        _transfer(sender, recipient, amount);
        _approve(sender, msg.sender, allowance(sender, msg.sender) - amount);
        return true;
    }
}
