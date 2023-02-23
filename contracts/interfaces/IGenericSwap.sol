// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IStrategy } from "./IStrategy.sol";

interface IGenericSwap {
    error InvalidMsgValue();
    error InsufficientOutput();

    event Swap(address indexed maker, address indexed inputToken, address indexed outputToken, uint256 inputAmount, uint256 outputAmount);

    struct GenericSwapData {
        address inputToken;
        address outputToken;
        uint256 inputAmount;
        uint256 minOutputAmount;
        address payable receiver;
        uint256 deadline;
        bytes inputData;
        bytes strategyData;
    }

    function executeSwap(IStrategy strategy, GenericSwapData calldata swapData) external payable returns (uint256 returnAmount);

    function executeSwap(
        IStrategy strategy,
        GenericSwapData calldata swapData,
        address taker,
        uint256 salt,
        bytes calldata takerSig
    ) external payable returns (uint256 returnAmount);
}
