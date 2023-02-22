// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/draft-IERC20Permit.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

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
            (bool success, bytes memory result) = token.call(abi.encodePacked(IERC20Permit.permit.selector, data));
            if (!success) {
                assembly {
                    result := add(result, 0x04)
                }
                revert(abi.decode(result, (string)));
            }
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
            (address owner, IUniswapPermit2.PermitSingle memory permit, bytes memory permitSig) = abi.decode(
                data,
                (address, IUniswapPermit2.PermitSingle, bytes)
            );
            IUniswapPermit2(uniswapPermit2).permit(owner, permit, permitSig);
        }
        IUniswapPermit2(uniswapPermit2).transferFrom(from, to, uint160(amount), token);
    }
}
