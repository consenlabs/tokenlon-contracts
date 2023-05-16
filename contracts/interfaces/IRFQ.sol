// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { Offer } from "contracts/libraries/Offer.sol";
import { RFQOrder } from "contracts/libraries/RFQOrder.sol";

/// @title IRFQ Interface
/// @author imToken Labs
interface IRFQ {
    error ExpiredOffer();
    error FilledOffer();
    error ZeroAddress();
    error InvalidFeeFactor();
    error InvalidMsgValue();
    error InvalidSignature();

    event FilledRFQ(
        bytes32 indexed offerHash,
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

    function fillRFQ(
        Offer calldata offer,
        bytes calldata makerSignature,
        bytes calldata makerTokenPermit,
        bytes calldata takerTokenPermit,
        address payable recipient
    ) external payable;

    function fillRFQ(
        RFQOrder calldata rfqOrder,
        bytes calldata makerSignature,
        bytes calldata makerTokenPermit,
        bytes calldata takerTokenPermit,
        bytes calldata takerSignature
    ) external;
}
