// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;
pragma abicoder v2;

import { RFQOrder } from "../utils/RFQOrder.sol";

/// @title IRFQv2 Interface
/// @author imToken Labs
interface IRFQv2 {
    /// @notice Emitted when an order is settled
    /// @param offerHash The hash of the offer to be filled
    /// @param user The address of the user
    /// @param maker The address of the offer maker
    /// @param takerToken The address of taker token
    /// @param takerTokenAmount The amount of taker token
    /// @param makerToken The address of maker token
    /// @param makerTokenAmount The amount of maker token
    /// @param recipient The address of recipient that will receive the maker token
    /// @param settleAmount The actual amount that recipient will receive (after fee, if any)
    /// @param feeFactor The fee factor of this settlement
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

    /// @notice Settle a RFQ order
    /// @notice Signature from maker and user should be both provided
    /// @param rfqOrder The order that is going to be filled
    /// @param makerSignature The signature of the offer
    /// @param makerTokenPermit The token permit data of the maker
    /// @param takerSignature The signature of the whole order
    /// @param takerTokenPermit The token permit data of the taker
    function fillRFQ(
        RFQOrder calldata rfqOrder,
        bytes calldata makerSignature,
        bytes calldata makerTokenPermit,
        bytes calldata takerSignature,
        bytes calldata takerTokenPermit
    ) external payable;
}
