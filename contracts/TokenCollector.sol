// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import { IERC20Permit } from "@openzeppelin/contracts/drafts/IERC20Permit.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import { IUniswapPermit2 } from "contracts/interfaces/IUniswapPermit2.sol";

abstract contract TokenCollector {
    using SafeERC20 for IERC20;

    enum Source {
        Token,
        UniswapPermit2
    }

    address public immutable uniswapPermit2;

    constructor(address _uniswapPermit2) {
        uniswapPermit2 = _uniswapPermit2;
    }

    function _collect(
        address token,
        address from,
        address to,
        uint256 amount,
        bytes memory data
    ) internal {
        (Source src, bytes memory srcData) = abi.decode(data, (Source, bytes));
        if (src == Source.Token) {
            return _collectFromToken(token, from, to, amount, srcData);
        }
        if (src == Source.UniswapPermit2) {
            return _collectFromUniswapPermit2(token, from, to, amount, srcData);
        }
        revert("TokenCollector: unknown token source");
    }

    function _collectFromToken(
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

    function _collectFromUniswapPermit2(
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
