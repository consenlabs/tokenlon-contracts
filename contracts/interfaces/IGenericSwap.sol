// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { GenericSwapData } from "../libraries/GenericSwapData.sol";

interface IGenericSwap {
    error AlreadyFilled();
    error InvalidMsgValue();
    error InsufficientOutput();
    error InvalidSignature();

    event Swap(
        bytes32 indexed swapHash,
        address indexed maker,
        address indexed taker,
        address recipient,
        address inputToken,
        uint256 inputAmount,
        address outputToken,
        uint256 outputAmount
    );

    function executeSwap(GenericSwapData calldata swapData, bytes calldata takerTokenPermit) external payable returns (uint256 returnAmount);

    function executeSwap(
        GenericSwapData calldata swapData,
        bytes calldata takerTokenPermit,
        address taker,
        bytes calldata takerSig
    ) external payable returns (uint256 returnAmount);
}
