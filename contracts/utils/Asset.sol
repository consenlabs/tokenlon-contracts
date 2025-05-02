// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import { LibConstant } from "./LibConstant.sol";

library Asset {
    using SafeERC20 for IERC20;

    function isETH(address addr) internal pure returns (bool) {
        return (addr == LibConstant.ETH_ADDRESS || addr == LibConstant.ZERO_ADDRESS);
    }

    function transferTo(address asset, address payable to, uint256 amount) internal {
        if (to == address(this)) {
            return;
        }
        if (isETH(asset)) {
            // @dev forward all available gas and may cause reentrancy
            require(address(this).balance >= amount, "insufficient balance");
            (bool success, ) = to.call{ value: amount }("");
            require(success, "unable to send ETH");
        } else {
            IERC20(asset).safeTransfer(to, amount);
        }
    }
}
