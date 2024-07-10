// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { GenericSwapData } from "../libraries/GenericSwapData.sol";

/// @title IGenericSwap Interface
/// @author imToken Labs
/// @notice Interface for a generic swap contract.
/// @dev This interface defines functions and events related to executing swaps and handling swap errors.
interface IGenericSwap {
    /// @notice Error to be thrown when a swap is already filled.
    /// @dev This error is used when attempting to fill a swap that has already been completed.
    error AlreadyFilled();

    /// @notice Error to be thrown when the msg.value is invalid.
    /// @dev This error is used to ensure that the correct msg.value is sent with the transaction.
    error InvalidMsgValue();

    /// @notice Error to be thrown when the output amount is insufficient.
    /// @dev This error is used when the output amount received from the swap is insufficient.
    error InsufficientOutput();

    /// @notice Error to be thrown when a signature is invalid.
    /// @dev This error is used to ensure that the provided signature is valid.
    error InvalidSignature();

    /// @notice Error to be thrown when an order has expired.
    /// @dev This error is used to ensure that the swap order has not expired.
    error ExpiredOrder();

    /// @notice Error to be thrown when an address is zero.
    /// @dev This error is used to ensure that a valid address is provided.
    error ZeroAddress();

    /// @notice Event emitted when a swap is executed.
    /// @dev This event is emitted when a swap is successfully executed.
    /// @param swapHash The hash of the swap data.
    /// @param maker The address of the maker initiating the swap.
    /// @param taker The address of the taker executing the swap.
    /// @param recipient The address receiving the output tokens.
    /// @param inputToken The address of the input token.
    /// @param inputAmount The amount of input tokens.
    /// @param outputToken The address of the output token.
    /// @param outputAmount The amount of output tokens received.
    /// @param salt The salt value used in the swap.
    event Swap(
        bytes32 indexed swapHash,
        address indexed maker,
        address indexed taker,
        address recipient,
        address inputToken,
        uint256 inputAmount,
        address outputToken,
        uint256 outputAmount,
        uint256 salt
    );

    /// @notice Executes a swap using provided swap data and taker token permit.
    /// @dev Executes a swap based on the provided swap data and taker token permit.
    /// @param swapData The swap data containing details of the swap.
    /// @param takerTokenPermit The permit for spending taker's tokens.
    /// @return returnAmount The amount of tokens returned from the swap.
    function executeSwap(GenericSwapData calldata swapData, bytes calldata takerTokenPermit) external payable returns (uint256 returnAmount);

    /// @notice Executes a swap using provided swap data, taker token permit, taker address, and signature.
    /// @dev Executes a swap with additional parameters including taker address and signature.
    /// @param swapData The swap data containing details of the swap.
    /// @param takerTokenPermit The permit for spending taker's tokens.
    /// @param taker The address of the taker initiating the swap.
    /// @param takerSig The signature of the taker authorizing the swap.
    /// @return returnAmount The amount of tokens returned from the swap.
    function executeSwapWithSig(
        GenericSwapData calldata swapData,
        bytes calldata takerTokenPermit,
        address taker,
        bytes calldata takerSig
    ) external payable returns (uint256 returnAmount);
}
