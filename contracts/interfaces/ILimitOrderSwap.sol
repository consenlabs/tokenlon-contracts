// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { LimitOrder } from "../libraries/LimitOrder.sol";

/// @title ILimitOrderSwap Interface
/// @author imToken Labs
interface ILimitOrderSwap {
    error ExpiredOrder();
    error CanceledOrder();
    error FilledOrder();
    error ZeroAddress();
    error ZeroTokenAmount();
    error NotEnoughForFill();
    error InvalidMsgValue();
    error InvalidSignature();
    error InvalidTaker();
    error InvalidTakingAmount();
    error InvalidParams();
    error NotOrderMaker();

    /// @notice Emitted when fee collector address is updated
    /// @param newFeeCollector The address of the new fee collector
    event SetFeeCollector(address newFeeCollector);

    /// @notice Emitted when an order is filled
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

    /// @notice Emitted when order is canceled
    event OrderCanceled(bytes32 orderHash, address maker);

    struct TakerParams {
        uint256 takerTokenAmount;
        uint256 makerTokenAmount;
        address recipient;
        bytes extraAction;
        bytes takerTokenPermit;
    }

    /// @notice Fill an order
    function fillLimitOrder(LimitOrder calldata order, bytes calldata makerSignature, TakerParams calldata takerParams) external payable;

    /// @notice Fill an order
    function fillLimitOrderFullOrKill(LimitOrder calldata order, bytes calldata makerSignature, TakerParams calldata takerParams) external payable;

    function fillLimitOrderGroup(
        LimitOrder[] calldata orders,
        bytes[] calldata makerSignatures,
        uint256[] calldata makerTokenAmounts,
        address[] calldata profitTokens
    ) external payable;

    /// @notice Cancel an order
    function cancelOrder(LimitOrder calldata order) external;

    function isOrderCanceled(bytes32 orderHash) external view returns (bool);
}
