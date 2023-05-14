// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { Offer } from "../libraries/Offer.sol";
import { RFQOrder } from "../libraries/RFQOrder.sol";

/// @title IRFQ Interface
/// @author imToken Labs
interface IRFQ {
    error ExpiredOffer();
    error FilledOffer();
    error ZeroAddress();
    error InvalidFeeFactor();
    error InvalidMsgValue();
    error InvalidSignature();
    error ForbidContract();
    error NotOfferMaker();

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

    event CancelRFQOffer(bytes32 indexed offerHash, address indexed maker);

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

    function cancelRFQOffer(Offer calldata offer) external;
}
