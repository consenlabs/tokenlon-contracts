// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { StdStorage, stdStorage } from "forge-std/StdStorage.sol";
import { Test } from "forge-std/Test.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract BalanceUtil is Test {
    using stdStorage for StdStorage;
    using SafeERC20 for IERC20;

    function externalDeal(
        address tokenAddr,
        address userAddr,
        uint256 amountInWei,
        bool updateTotalSupply
    ) public {
        deal(tokenAddr, userAddr, amountInWei, updateTotalSupply);
    }

    function setTokenBalanceAndApprove(
        address user,
        address spender,
        IERC20[] memory tokens,
        uint256 amount
    ) internal {
        for (uint256 i = 0; i < tokens.length; i++) {
            setERC20Balance(address(tokens[i]), user, amount);
            approveERC20(address(tokens[i]), user, spender);
        }
    }

    function setERC20Balance(
        address token,
        address user,
        uint256 amount
    ) internal {
        uint256 decimals = uint256(ERC20(token).decimals());
        uint256 amountInWei = amount * (10**decimals);
        // First try to update `totalSupply` together, but this would fail with WETH because WETH does not store `totalSupply` in storage
        try this.externalDeal(token, user, amountInWei, true) {} catch {
            // If it fails, try again without update `totalSupply`
            deal(token, user, amountInWei, false);
        }
    }

    function approveERC20(
        address token,
        address user,
        address spender
    ) internal {
        vm.startPrank(user);
        IERC20(token).safeApprove(spender, type(uint256).max);
        vm.stopPrank();
    }
}
