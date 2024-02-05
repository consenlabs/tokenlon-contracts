// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { ConOrder } from "../libraries/ConditionalOrder.sol";

interface IConditionalSwap {
    // error
    error ExpiredOrder();
    error FilledOrder();
    error ZeroAddress();
    error ZeroTokenAmount();
    error InvalidMsgValue();
    error InvalidSignature();
    error InvalidTaker();
    error InvalidTakingAmount();
    error InvalidRecipient();
    error NotOrderMaker();

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

    // struct

    // function
    function fillOrder(ConOrder calldata cd, bytes calldata userSig, uint256 userAmount, uint256 makerAmount, bytes calldata settlementData) external;
}
