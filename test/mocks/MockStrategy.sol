// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IStrategy } from "contracts/interfaces/IStrategy.sol";
import { Asset } from "contracts/libraries/Asset.sol";

contract MockStrategy is IStrategy {
    using Asset for address;

    uint256 public outputAmount;
    address payable public recipient;

    function setOutputAmountAndRecipient(uint256 amount, address payable rec) external {
        outputAmount = amount;
        recipient = rec;
    }

    function executeStrategy(address, address outputToken, uint256, bytes calldata) external payable override {
        outputToken.transferTo(recipient, outputAmount);
    }
}
