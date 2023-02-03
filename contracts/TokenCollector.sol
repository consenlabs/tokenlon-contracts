// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

import { IERC20Permit } from "@openzeppelin/contracts/drafts/IERC20Permit.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import { ISpender } from "contracts/interfaces/ISpender.sol";
import { ITokenCollector } from "contracts/interfaces/ITokenCollector.sol";

contract TokenCollector is ITokenCollector {
    using SafeERC20 for IERC20;

    address public immutable spender;

    constructor(address _spender) {
        spender = _spender;
    }

    function collect(
        address token,
        address from,
        address to,
        uint256 amount,
        bytes memory data
    ) external override {
        (Source src, bytes memory data) = abi.decode(data, (Source, bytes));
        if (src == Source.Token) {
            return transferFromToken(token, from, to, amount, data);
        }
        if (src == Source.Spender) {
            return transferFromSpender(token, from, to, amount, data);
        }
    }

    function transferFromToken(
        address token,
        address from,
        address to,
        uint256 amount,
        bytes memory data
    ) private {
        if (data.length > 0) {
            token.call(abi.encodePacked(IERC20Permit.permit.selector, data));
        }
        IERC20(token).safeTransferFrom(from, to, amount);
    }

    function transferFromSpender(
        address token,
        address from,
        address to,
        uint256 amount,
        bytes memory data
    ) private {
        ISpender(spender).spendFromUserTo(from, token, to, amount);
    }
}
