// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IAllowanceTarget } from "./interfaces/IAllowanceTarget.sol";
import { Constant } from "./libraries/Constant.sol";

contract AllowanceTarget is IAllowanceTarget {
    using SafeERC20 for IERC20;

    mapping(address => bool) public authorized;

    constructor(address[] memory trustedCaller) {
        for (uint256 i = 0; i < trustedCaller.length; ++i) {
            authorized[trustedCaller[i]] = true;
        }
    }

    /// @inheritdoc IAllowanceTarget
    function spendFromUserTo(
        address from,
        address token,
        address to,
        uint256 amount
    ) external override {
        require(authorized[msg.sender], "AllowanceTarget: not authorized");
        IERC20(token).safeTransferFrom(from, to, amount);
    }
}
