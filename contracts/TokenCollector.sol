// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import { IERC20Permit } from "@openzeppelin/contracts/drafts/IERC20Permit.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import { ITokenCollector } from "contracts/interfaces/ITokenCollector.sol";
import { IUniswapPermit2 } from "contracts/interfaces/IUniswapPermit2.sol";

contract TokenCollector is ITokenCollector {
    using SafeERC20 for IERC20;

    address public immutable owner;
    address public immutable uniswapPermit2;

    constructor(address _uniswapPermit2) {
        owner = msg.sender;
        uniswapPermit2 = _uniswapPermit2;
    }

    function collect(
        address token,
        address from,
        address to,
        uint256 amount,
        bytes memory data
    ) external override {
        require(msg.sender == owner, "TokenCollector: not owner");

        (Source src, bytes memory srcData) = abi.decode(data, (Source, bytes));
        if (src == Source.Token) {
            return collectFromToken(token, from, to, amount, srcData);
        }
        if (src == Source.UniswapPermit2) {
            return collectFromUniswapPermit2(token, from, to, amount, srcData);
        }
        revert("TokenCollector: unknown token source");
    }

    function collectFromToken(
        address token,
        address from,
        address to,
        uint256 amount,
        bytes memory data
    ) private {
        if (data.length > 0) {
            (bool success, ) = token.call(abi.encodePacked(IERC20Permit.permit.selector, data));
            require(success, "TokenCollector: token permit failed");
        }
        IERC20(token).safeTransferFrom(from, to, amount);
    }

    function collectFromUniswapPermit2(
        address token,
        address from,
        address to,
        uint256 amount,
        bytes memory data
    ) private {
        require(amount < uint256(type(uint160).max), "TokenCollector: permit2 amount too large");
        if (data.length > 0) {
            (bool success, ) = uniswapPermit2.call(abi.encodePacked(IUniswapPermit2.permit.selector, data));
            require(success, "TokenCollector: permit2 permit failed");
        }
        IUniswapPermit2(uniswapPermit2).transferFrom(from, to, uint160(amount), token);
    }
}
