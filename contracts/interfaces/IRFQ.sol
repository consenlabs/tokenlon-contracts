// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { Order } from "../libraries/Order.sol";

/// @title IRFQ Interface
/// @author imToken Labs
interface IRFQ {
    error ExpiredOrder();
    error FilledOrder();
    error ZeroAddress();
    error InvalidFeeFactor();
    error InvalidTaker();
    error InvalidMsgValue();
    error InvalidSignature();

    event FilledRFQ(
        bytes32 indexed rfqOrderHash,
        address indexed user,
        address indexed maker,
        address takerToken,
        uint256 takerTokenAmount,
        address makerToken,
        uint256 makerTokenAmount,
        address recipient,
        uint256 settleAmount,
        uint256 feeFactor
    );

    struct RFQOrder {
        Order order;
        uint256 feeFactor;
    }

    function fillRFQ(
        RFQOrder calldata rfqOrder,
        bytes calldata makerSignature,
        bytes calldata makerTokenPermit,
        bytes calldata takerTokenPermit
    ) external payable;

    function fillRFQ(
        RFQOrder calldata rfqOrder,
        bytes calldata makerSignature,
        bytes calldata makerTokenPermit,
        bytes calldata takerTokenPermit,
        bytes calldata takerSignature,
        address taker
    ) external;
}
