// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;
pragma abicoder v2;

import { Offer } from "../utils/Offer.sol";

/// @title IRFQ Interface
/// @author imToken Labs
interface IRFQv2 {
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

    struct RFQOrder {
        Offer offer;
        address payable recipient;
        uint256 feeFactor;
    }

    function fillRFQ(
        RFQOrder calldata rfqOrder,
        bytes calldata makerSignature,
        bytes calldata makerTokenPermit,
        bytes calldata takerTokenPermit,
        bytes calldata takerSignature
    ) external payable;
}
