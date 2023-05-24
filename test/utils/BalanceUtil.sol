// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import { stdStorage, StdStorage } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import { Addresses } from "test/utils/Addresses.sol";

contract BalanceUtil is Addresses {
    using SafeERC20 for IERC20;
    using stdStorage for StdStorage;

    function setERC20Balance(
        address tokenAddr,
        address userAddr,
        uint256 amount
    ) internal {
        uint256 decimals = uint256(ERC20(tokenAddr).decimals());
        // Skip setting WETH's totalSupply because WETH does not store total supply in storage
        // Only update WETH's totalSupply in local env
        bool updateTotalSupply = getChainId() == 31337 && tokenAddr == address(weth);
        deal(
            tokenAddr,
            userAddr,
            amount * (10**decimals),
            updateTotalSupply // also update totalSupply
        );
    }

    function approveERC20(
        IERC20[] memory tokens,
        address userAddr,
        address target
    ) internal {
        vm.startPrank(userAddr);
        for (uint256 i = 0; i < tokens.length; i++) {
            tokens[i].safeApprove(target, type(uint256).max);
        }
        vm.stopPrank();
    }
}
