// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { RFQOffer } from "../libraries/RFQOffer.sol";
import { RFQTx } from "../libraries/RFQTx.sol";

/// @title IRFQ Interface
/// @author imToken Labs
interface IRFQ {
    error ExpiredRFQOffer();
    error FilledRFQOffer();
    error ZeroAddress();
    error InvalidFeeFactor();
    error InvalidMsgValue();
    error InvalidSignature();
    error InvalidTakerAmount();
    error InvalidMakerAmount();
    error ForbidContract();
    error ForbidPartialFill();
    error NotOfferMaker();

    event FilledRFQ(
        bytes32 indexed rfqOfferHash,
        address indexed user,
        address indexed maker,
        address takerToken,
        uint256 takerTokenUserAmount,
        address makerToken,
        uint256 makerTokenUserAmount,
        address recipient,
        uint256 fee
    );

    event CancelRFQOffer(bytes32 indexed rfqOfferHash, address indexed maker);

    function fillRFQ(RFQTx calldata rfqTx, bytes calldata makerSignature, bytes calldata makerTokenPermit, bytes calldata takerTokenPermit) external payable;

    function fillRFQ(
        RFQTx calldata rfqTx,
        bytes calldata makerSignature,
        bytes calldata makerTokenPermit,
        bytes calldata takerTokenPermit,
        bytes calldata takerSignature
    ) external;

    function cancelRFQOffer(RFQOffer calldata rfqOffer) external;
}
