// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { LimitOrder } from "../libraries/LimitOrder.sol";

/// @title ILimitOrderSwap Interface
/// @author imToken Labs
/// @notice Interface for a limit order swap contract.
/// @dev This interface defines functions and events related to executing and managing limit orders.
interface ILimitOrderSwap {
    /// @notice Struct containing parameters for the taker.
    /// @dev This struct encapsulates the parameters necessary for a taker to fill a limit order.
    struct TakerParams {
        uint256 takerTokenAmount; // Amount of tokens taken by the taker.
        uint256 makerTokenAmount; // Amount of tokens provided by the maker.
        address recipient; // Address to receive the tokens.
        bytes extraAction; // Additional action to be performed.
        bytes takerTokenPermit; // Permit for spending taker's tokens.
    }

    /// @notice Emitted when the fee collector address is updated.
    /// @param newFeeCollector The address of the new fee collector.
    event SetFeeCollector(address newFeeCollector);

    /// @notice Emitted when a limit order is successfully filled.
    /// @param orderHash The hash of the limit order.
    /// @param taker The address of the taker filling the order.
    /// @param maker The address of the maker who created the order.
    /// @param takerToken The address of the token taken by the taker.
    /// @param takerTokenFilledAmount The amount of taker tokens filled.
    /// @param makerToken The address of the token received by the maker.
    /// @param makerTokenSettleAmount The amount of maker tokens settled.
    /// @param fee The fee amount paid for the order.
    /// @param recipient The address receiving the tokens.
    event LimitOrderFilled(
        bytes32 indexed orderHash,
        address indexed taker,
        address indexed maker,
        address takerToken,
        uint256 takerTokenFilledAmount,
        address makerToken,
        uint256 makerTokenSettleAmount,
        uint256 fee,
        address recipient
    );

    /// @notice Emitted when an order is canceled.
    /// @param orderHash The hash of the canceled order.
    /// @param maker The address of the maker who canceled the order.
    event OrderCanceled(bytes32 orderHash, address maker);

    /// @notice Error to be thrown when an order has expired.
    /// @dev Thrown when attempting to fill an order that has already expired.
    error ExpiredOrder();

    /// @notice Error to be thrown when an order is canceled.
    /// @dev Thrown when attempting to fill or interact with a canceled order.
    error CanceledOrder();

    /// @notice Error to be thrown when an order is already filled.
    /// @dev Thrown when attempting to fill an order that has already been fully filled.
    error FilledOrder();

    /// @notice Error to be thrown when an address is zero.
    /// @dev Thrown when an operation requires a non-zero address.
    error ZeroAddress();

    /// @notice Error to be thrown when the taker token amount is zero.
    /// @dev Thrown when filling an order with zero taker token amount.
    error ZeroTakerTokenAmount();

    /// @notice Error to be thrown when the maker token amount is zero.
    /// @dev Thrown when filling an order with zero maker token amount.
    error ZeroMakerTokenAmount();

    /// @notice Error to be thrown when the taker spending amount is zero.
    /// @dev Thrown when an action requires a non-zero taker spending amount.
    error ZeroTakerSpendingAmount();

    /// @notice Error to be thrown when the maker spending amount is zero.
    /// @dev Thrown when an action requires a non-zero maker spending amount.
    error ZeroMakerSpendingAmount();

    /// @notice Error to be thrown when there are not enough tokens to fill the order.
    /// @dev Thrown when attempting to fill an order with insufficient tokens available.
    error NotEnoughForFill();

    /// @notice Error to be thrown when the msg.value is invalid.
    /// @dev Thrown when an operation requires a specific msg.value that is not provided.
    error InvalidMsgValue();

    /// @notice Error to be thrown when a signature is invalid.
    /// @dev Thrown when an operation requires a valid cryptographic signature that is not provided or is invalid.
    error InvalidSignature();

    /// @notice Error to be thrown when the taker address is invalid.
    /// @dev Thrown when an operation requires a valid taker address that is not provided or is invalid.
    error InvalidTaker();

    /// @notice Error to be thrown when the taking amount is invalid.
    /// @dev Thrown when an operation requires a valid taking amount that is not provided or is invalid.
    error InvalidTakingAmount();

    /// @notice Error to be thrown when the parameters provided are invalid.
    /// @dev Thrown when an operation receives invalid parameters that prevent execution.
    error InvalidParams();

    /// @notice Error to be thrown when the caller is not the maker of the order.
    /// @dev Thrown when an operation is attempted by an unauthorized caller who is not the maker of the order.
    error NotOrderMaker();

    /// @notice Fills a limit order.
    /// @param order The limit order to be filled.
    /// @param makerSignature The signature of the maker authorizing the fill.
    /// @param takerParams The parameters specifying how the order should be filled by the taker.
    function fillLimitOrder(LimitOrder calldata order, bytes calldata makerSignature, TakerParams calldata takerParams) external payable;

    /// @notice Fills a limit order fully or cancels it.
    /// @param order The limit order to be filled or canceled.
    /// @param makerSignature The signature of the maker authorizing the fill or cancel.
    /// @param takerParams The parameters specifying how the order should be filled by the taker.
    function fillLimitOrderFullOrKill(LimitOrder calldata order, bytes calldata makerSignature, TakerParams calldata takerParams) external payable;

    /// @notice Fills a group of limit orders atomically.
    /// @param orders The array of limit orders to be filled.
    /// @param makerSignatures The array of signatures of the makers authorizing the fills.
    /// @param makerTokenAmounts The array of amounts of tokens provided by the makers.
    /// @param profitTokens The array of addresses of tokens used for profit sharing.
    function fillLimitOrderGroup(
        LimitOrder[] calldata orders,
        bytes[] calldata makerSignatures,
        uint256[] calldata makerTokenAmounts,
        address[] calldata profitTokens
    ) external payable;

    /// @notice Cancels a limit order.
    /// @param order The limit order to be canceled.
    function cancelOrder(LimitOrder calldata order) external;

    /// @notice Checks if an order is canceled.
    /// @param orderHash The hash of the order to check.
    /// @return True if the order is canceled, otherwise false.
    function isOrderCanceled(bytes32 orderHash) external view returns (bool);
}
