// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;
pragma abicoder v2;

import { RFQOrder } from "../utils/RFQOrder.sol";

/// @title IRFQv2 Interface
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

    function fillRFQ(
        RFQOrder calldata rfqOrder,
        bytes calldata makerSignature,
        bytes calldata makerTokenPermit,
        bytes calldata takerSignature,
        bytes calldata takerTokenPermit
    ) external payable;
}
