// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { ConOrder } from "../libraries/ConditionalOrder.sol";

interface IConditionalSwap {
    // error
    error ExpiredOrder();
    error InsufficientTimePassed();
    error ZeroTokenAmount();
    error InvalidSignature();
    error InvalidTakingAmount();
    error InvalidMakingAmount();
    error InvalidRecipient();
    error NotOrderMaker();
    error InsufficientOutput();

    // event
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
