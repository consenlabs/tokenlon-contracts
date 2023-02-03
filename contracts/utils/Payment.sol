// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

import { IERC20Permit } from "@openzeppelin/contracts/drafts/IERC20Permit.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import { ISpender } from "contracts/interfaces/ISpender.sol";

library Payment {
    using SafeERC20 for IERC20;

    enum Type {
        Token,
        Spender
    }

    function fulfill(
        address spender,
        address payer,
        address token,
        uint256 amount,
        bytes memory data
    ) internal {
        (Type t, bytes memory data) = abi.decode(data, (Type, bytes));
        if (t == Type.Token) {
            return transferFromToken(payer, token, amount, data);
        }
        if (t == Type.Spender) {
            return transferFromSpender(spender, payer, token, amount, data);
        }
    }

    function transferFromToken(
        address payer,
        address token,
        uint256 amount,
        bytes memory data
    ) private {
        if (data.length > 0) {
            token.call(abi.encodePacked(IERC20Permit.permit.selector, data));
        }
        IERC20(token).safeTransferFrom(payer, address(this), amount);
    }

    function transferFromSpender(
        address spender,
        address payer,
        address token,
        uint256 amount,
        bytes memory data
    ) private {
        ISpender(spender).spendFromUserTo(payer, token, address(this), amount);
    }
}
