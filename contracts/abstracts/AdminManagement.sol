// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { Ownable } from "./Ownable.sol";
import { Asset } from "../libraries/Asset.sol";

/// @title AdminManagement Contract
/// @author imToken Labs
abstract contract AdminManagement is Ownable {
    using SafeERC20 for IERC20;

    constructor(address _owner) Ownable(_owner) {}

    function approveTokens(address[] calldata tokens, address[] calldata spenders) external onlyOwner {
        uint256 tokensLength = tokens.length;
        uint256 spendersLength = spenders.length;
        for (uint256 i = 0; i < tokensLength; ++i) {
            for (uint256 j = 0; j < spendersLength; ++j) {
                IERC20(tokens[i]).safeApprove(spenders[j], type(uint256).max);
            }
        }
    }

    function rescueTokens(address[] calldata tokens, address recipient) external onlyOwner {
        uint256 tokensLength = tokens.length;
        for (uint256 i = 0; i < tokensLength; ++i) {
            uint256 selfBalance = Asset.getBalance(tokens[i], address(this));
            if (selfBalance > 0) {
                Asset.transferTo(tokens[i], payable(recipient), selfBalance);
            }
        }
    }
}
