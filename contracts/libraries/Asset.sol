// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { Constant } from "./Constant.sol";

library Asset {
    using SafeERC20 for IERC20;

    error InsufficientBalance();

    function isETH(address addr) internal pure returns (bool) {
        return (addr == Constant.ETH_ADDRESS || addr == Constant.ZERO_ADDRESS);
    }

    function getBalance(address asset, address owner) internal view returns (uint256) {
        if (isETH(asset)) {
            return owner.balance;
        } else {
            return IERC20(asset).balanceOf(owner);
        }
    }

    function transferTo(
        address asset,
        address payable to,
        uint256 amount
    ) internal {
        if (to == address(this) || amount == 0) {
            return;
        }
        if (isETH(asset)) {
            // @dev forward all available gas and may cause reentrancy
            if (address(this).balance < amount) revert InsufficientBalance();
            (bool success, bytes memory result) = to.call{ value: amount }("");
            if (!success) {
                assembly {
                    revert(add(result, 32), mload(result))
                }
            }
        } else {
            IERC20(asset).safeTransfer(to, amount);
        }
    }
}
