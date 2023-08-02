// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import { IUniswapPermit2 } from "../interfaces/IUniswapPermit2.sol";
import { ISpender } from "../interfaces/ISpender.sol";
import { IERC20Permit } from "../interfaces/IERC20Permit.sol";

abstract contract TokenCollector {
    using SafeERC20 for IERC20;

    enum Source {
        TokenlonSpender,
        Token,
        TokenPermit,
        Permit2AllowanceTransfer,
        Permit2SignatureTransfer
    }

    address public immutable permit2;
    address public immutable tokenlonSpender;

    constructor(address _permit2, address _tokenlonSpender) {
        permit2 = _permit2;
        tokenlonSpender = _tokenlonSpender;
    }

    function _collect(
        address token,
        address from,
        address to,
        uint256 amount,
        bytes calldata data
    ) internal {
        Source src = Source(uint8(data[0]));

        if (src == Source.TokenlonSpender) {
            ISpender(tokenlonSpender).spendFromUser(from, token, amount);
            if (to != address(this)) {
                IERC20(token).safeTransfer(to, amount);
            }
            return;
        } else if (src == Source.Token) {
            return IERC20(token).safeTransferFrom(from, to, amount);
        } else if (src == Source.TokenPermit) {
            (bool success, bytes memory result) = token.call(abi.encodePacked(IERC20Permit.permit.selector, data[1:]));
            if (!success) {
                assembly {
                    revert(add(result, 32), returndatasize())
                }
            }
            return IERC20(token).safeTransferFrom(from, to, amount);
        } else if (src == Source.Permit2AllowanceTransfer) {
            bytes memory permit2Data = data[1:];
            if (permit2Data.length > 0) {
                (bool success, bytes memory result) = permit2.call(abi.encodePacked(IUniswapPermit2.permit.selector, permit2Data));
                if (!success) {
                    assembly {
                        revert(add(result, 32), returndatasize())
                    }
                }
            }
            return IUniswapPermit2(permit2).transferFrom(from, to, uint160(amount), token);
        } else if (src == Source.Permit2SignatureTransfer) {
            bytes memory permit2Data = data[1:];
            require(permit2Data.length != 0, "empty permit2 data");
            (uint256 nonce, uint256 deadline, bytes memory permitSig) = abi.decode(permit2Data, (uint256, uint256, bytes));
            IUniswapPermit2.PermitTransferFrom memory permit = IUniswapPermit2.PermitTransferFrom({
                permitted: IUniswapPermit2.TokenPermissions({ token: token, amount: amount }),
                nonce: nonce,
                deadline: deadline
            });
            IUniswapPermit2.SignatureTransferDetails memory detail = IUniswapPermit2.SignatureTransferDetails({ to: to, requestedAmount: amount });
            return IUniswapPermit2(permit2).permitTransferFrom(permit, detail, from, permitSig);
        }

        // won't be reached
        revert();
    }
}
