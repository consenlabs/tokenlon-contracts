// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IUniswapPermit2 } from "../interfaces/IUniswapPermit2.sol";
import { IAllowanceTarget } from "../interfaces/IAllowanceTarget.sol";

/// @title TokenCollector Contract
/// @author imToken Labs
/// @notice This contract handles the collection of tokens using various methods.
/// @dev This contract supports multiple token collection mechanisms including allowance targets, direct transfers, and permit transfers.
abstract contract TokenCollector {
    using SafeERC20 for IERC20;

    /// @notice Error to be thrown when Permit2 data is empty.
    /// @dev This error is used to ensure Permit2 data is provided when required.
    error Permit2DataEmpty();

    /// @title Token Collection Sources
    /// @notice Enumeration of possible token collection sources.
    /// @dev Represents the various methods for collecting tokens.
    enum Source {
        TokenlonAllowanceTarget,
        Token,
        TokenPermit,
        Permit2AllowanceTransfer,
        Permit2SignatureTransfer
    }

    address public immutable permit2;
    address public immutable allowanceTarget;

    /// @notice Constructor to set the Permit2 and allowance target addresses.
    /// @param _permit2 The address of the Uniswap Permit2 contract.
    /// @param _allowanceTarget The address of the allowance target contract.
    constructor(address _permit2, address _allowanceTarget) {
        permit2 = _permit2;
        allowanceTarget = _allowanceTarget;
    }

    /// @notice Internal function to collect tokens using various methods.
    /// @dev Handles token collection based on the specified source.
    /// @param token The address of the token to be collected.
    /// @param from The address from which the tokens will be collected.
    /// @param to The address to which the tokens will be sent.
    /// @param amount The amount of tokens to be collected.
    /// @param data Additional data required for the token collection process.
    function _collect(address token, address from, address to, uint256 amount, bytes calldata data) internal {
        Source src = Source(uint8(data[0]));

        if (src == Source.TokenlonAllowanceTarget) {
            return IAllowanceTarget(allowanceTarget).spendFromUserTo(from, token, to, amount);
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
            if (permit2Data.length == 0) revert Permit2DataEmpty();
            (uint256 nonce, uint256 deadline, bytes memory permitSig) = abi.decode(permit2Data, (uint256, uint256, bytes));
            IUniswapPermit2.PermitTransferFrom memory permit = IUniswapPermit2.PermitTransferFrom({
                permitted: IUniswapPermit2.TokenPermissions({ token: token, amount: amount }),
                nonce: nonce,
                deadline: deadline
            });
            IUniswapPermit2.SignatureTransferDetails memory detail = IUniswapPermit2.SignatureTransferDetails({ to: to, requestedAmount: amount });
            return IUniswapPermit2(permit2).permitTransferFrom(permit, detail, from, permitSig);
        }
    }
}
