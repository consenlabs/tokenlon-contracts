// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { StdStorage, stdStorage } from "forge-std/StdStorage.sol";
import { Test } from "forge-std/Test.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract BalanceUtil is Test {
    using stdStorage for StdStorage;

    function externalDeal(
        address tokenAddr,
        address userAddr,
        uint256 amountInWei,
        bool updateTotalSupply
    ) public {
        deal(tokenAddr, userAddr, amountInWei, updateTotalSupply);
    }

    function setERC20Balance(
        address tokenAddr,
        address userAddr,
        uint256 amount
    ) internal {
        uint256 decimals = uint256(ERC20(tokenAddr).decimals());
        uint256 amountInWei = amount * (10**decimals);
        // First try to update `totalSupply` together, but this would fail with WETH because WETH does not store `totalSupply` in storage
        try this.externalDeal(tokenAddr, userAddr, amountInWei, true) {} catch {
            // If it fails, try again without update `totalSupply`
            deal(tokenAddr, userAddr, amountInWei, false);
        }
    }
}
