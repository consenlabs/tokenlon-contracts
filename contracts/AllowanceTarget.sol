// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Pausable } from "@openzeppelin/contracts/security/Pausable.sol";

import { Ownable } from "./abstracts/Ownable.sol";
import { IAllowanceTarget } from "./interfaces/IAllowanceTarget.sol";

contract AllowanceTarget is IAllowanceTarget, Pausable, Ownable {
    using SafeERC20 for IERC20;

    mapping(address => bool) public authorized;

    constructor(address _owner, address[] memory trustedCaller) Ownable(_owner) {
        uint256 callerCount = trustedCaller.length;
        for (uint256 i = 0; i < callerCount; ++i) {
            authorized[trustedCaller[i]] = true;
        }
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /// @inheritdoc IAllowanceTarget
    function spendFromUserTo(
        address from,
        address token,
        address to,
        uint256 amount
    ) external override whenNotPaused {
        require(authorized[msg.sender], "AllowanceTarget: not authorized");
        IERC20(token).safeTransferFrom(from, to, amount);
    }
}
