// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { ConOrder } from "../libraries/ConditionalOrder.sol";

interface IConditionalSwap {
    error ExpiredOrder();
    error InsufficientTimePassed();
    error InvalidSignature();
    error ZeroTokenAmount();
    error InvalidTakingAmount();
    error InvalidMakingAmount();
    error InsufficientOutput();
    error NotOrderMaker();
    error InvalidRecipient();
    error InvalidSettlementType();

    /// @notice Emitted when a conditional order is filled
    event ConditionalOrderFilled(
        bytes32 indexed orderHash,
        address indexed taker,
        address indexed maker,
        address takerToken,
        uint256 takerTokenFilledAmount,
        address makerToken,
        uint256 makerTokenSettleAmount,
        address recipient
    );

    // function
    function fillConOrder(
        ConOrder calldata order,
        bytes calldata takerSignature,
        uint256 takerTokenAmount,
        uint256 makerTokenAmount,
        bytes calldata settlementData
    ) external payable;
}
