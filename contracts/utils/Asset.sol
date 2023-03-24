// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { LibConstant } from "./LibConstant.sol";

library Asset {
    using SafeERC20 for IERC20;

    function isETH(address addr) internal pure returns (bool) {
        return (addr == LibConstant.ETH_ADDRESS || addr == LibConstant.ZERO_ADDRESS);
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
        if (isETH(asset)) {
            // FIXME replace with fixed gas to solve reentrancy issue
            Address.sendValue(to, amount);
        } else {
            IERC20(asset).safeTransfer(to, amount);
        }
    }
}
