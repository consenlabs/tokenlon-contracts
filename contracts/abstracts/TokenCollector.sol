// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/draft-IERC20Permit.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IUniswapPermit2 } from "../interfaces/IUniswapPermit2.sol";
import { IAllowanceTarget } from "../interfaces/IAllowanceTarget.sol";

abstract contract TokenCollector {
    using SafeERC20 for IERC20;

    error UnknownTokenSource();

    enum Source {
        TokenlonAllowanceTarget,
        Token,
        TokenPermit,
        Permit2AllowanceTransfer,
        Permit2SignatureTransfer
    }

    address public immutable permit2;
    address public immutable allowanceTarget;

    constructor(address _permit2, address _allowanceTarget) {
        permit2 = _permit2;
        allowanceTarget = _allowanceTarget;
    }

    function _collect(
        address token,
        address from,
        address to,
        uint256 amount,
        bytes memory data
    ) internal {
        if (data.length == 1) {
            if (uint8(data[0]) == uint8(Source.TokenlonAllowanceTarget)) {
                return IAllowanceTarget(allowanceTarget).spendFromUserTo(from, token, to, amount);
            } else if (uint8(data[0]) == uint8(Source.Token)) {
                return IERC20(token).safeTransferFrom(from, to, amount);
            }
            revert UnknownTokenSource();
        } else {
            (Source src, bytes memory srcData) = abi.decode(data, (Source, bytes));
            if (src == Source.TokenPermit) {
                (bool success, bytes memory result) = token.call(abi.encodePacked(IERC20Permit.permit.selector, srcData));
                if (!success) {
                    assembly {
                        result := add(result, 0x04)
                    }
                    revert(abi.decode(result, (string)));
                }
                return IERC20(token).safeTransferFrom(from, to, amount);
            } else if (src == Source.Permit2AllowanceTransfer) {
                require(amount < uint256(type(uint160).max), "TokenCollector: permit2 amount too large");
                if (srcData.length > 0) {
                    (uint48 nonce, uint48 deadline, bytes memory permitSig) = abi.decode(srcData, (uint48, uint48, bytes));
                    IUniswapPermit2.PermitSingle memory permit = IUniswapPermit2.PermitSingle({
                        details: IUniswapPermit2.PermitDetails({ token: token, amount: uint160(amount), expiration: deadline, nonce: nonce }),
                        spender: address(this),
                        sigDeadline: uint256(deadline)
                    });
                    IUniswapPermit2(permit2).permit(from, permit, permitSig);
                }
                return IUniswapPermit2(permit2).transferFrom(from, to, uint160(amount), token);
            } else if (src == Source.Permit2SignatureTransfer) {
                require(srcData.length > 0, "TokenCollector: permit2 data cannot be empty");
                (uint256 nonce, uint256 deadline, bytes memory permitSig) = abi.decode(srcData, (uint256, uint256, bytes));
                IUniswapPermit2.PermitTransferFrom memory permit = IUniswapPermit2.PermitTransferFrom({
                    permitted: IUniswapPermit2.TokenPermissions({ token: token, amount: amount }),
                    nonce: nonce,
                    deadline: deadline
                });
                IUniswapPermit2.SignatureTransferDetails memory detail = IUniswapPermit2.SignatureTransferDetails({ to: to, requestedAmount: amount });
                return IUniswapPermit2(permit2).permitTransferFrom(permit, detail, from, permitSig);
            }
            revert UnknownTokenSource();
        }
    }
}
