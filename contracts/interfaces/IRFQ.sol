// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { RFQOffer } from "../libraries/RFQOffer.sol";
import { RFQTx } from "../libraries/RFQTx.sol";

/// @title IRFQ Interface
/// @author imToken Labs
/// @notice Interface for an RFQ (Request for Quote) contract.
/// @dev This interface defines functions and events related to handling RFQ offers and transactions.
interface IRFQ {
    /// @notice Emitted when the fee collector address is updated.
    /// @param newFeeCollector The address of the new fee collector.
    event SetFeeCollector(address newFeeCollector);

    /// @notice Emitted when an RFQ offer is successfully filled.
    /// @param rfqOfferHash The hash of the RFQ offer.
    /// @param user The address of the user filling the RFQ offer.
    /// @param maker The address of the maker who created the RFQ offer.
    /// @param takerToken The address of the token taken by the taker.
    /// @param takerTokenUserAmount The amount of taker tokens taken by the user.
    /// @param makerToken The address of the token provided by the maker.
    /// @param makerTokenUserAmount The amount of maker tokens received by the user.
    /// @param recipient The address receiving the tokens.
    /// @param fee The fee amount paid for the RFQ transaction.
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

    /// @notice Emitted when an RFQ offer is canceled.
    /// @param rfqOfferHash The hash of the canceled RFQ offer.
    /// @param maker The address of the maker who canceled the RFQ offer.
    event CancelRFQOffer(bytes32 indexed rfqOfferHash, address indexed maker);

    /// @notice Error to be thrown when an RFQ offer has expired.
    /// @dev Thrown when attempting to fill an RFQ offer that has expired.
    error ExpiredRFQOffer();

    /// @notice Error to be thrown when an RFQ offer is already filled.
    /// @dev Thrown when attempting to fill an RFQ offer that has already been filled.
    error FilledRFQOffer();

    /// @notice Error to be thrown when an address is zero.
    /// @dev Thrown when an operation requires a non-zero address.
    error ZeroAddress();

    /// @notice Error to be thrown when the fee factor is invalid.
    /// @dev Thrown when an operation requires a valid fee factor that is not provided.
    error InvalidFeeFactor();

    /// @notice Error to be thrown when the msg.value is invalid.
    /// @dev Thrown when an operation requires a specific msg.value that is not provided.
    error InvalidMsgValue();

    /// @notice Error to be thrown when a signature is invalid.
    /// @dev Thrown when an operation requires a valid cryptographic signature that is not provided or is invalid.
    error InvalidSignature();

    /// @notice Error to be thrown when the taker amount is invalid.
    /// @dev Thrown when an operation requires a valid taker amount that is not provided or is invalid.
    error InvalidTakerAmount();

    /// @notice Error to be thrown when the maker amount is invalid.
    /// @dev Thrown when an operation requires a valid maker amount that is not provided or is invalid.
    error InvalidMakerAmount();

    /// @notice Error to be thrown when interaction with contracts is forbidden.
    /// @dev Thrown when an operation is attempted with a contract address where only EOA (Externally Owned Account) is allowed.
    error ForbidContract();

    /// @notice Error to be thrown when partial fill is forbidden.
    /// @dev Thrown when attempting to partially fill an RFQ offer that does not allow partial fills.
    error ForbidPartialFill();

    /// @notice Error to be thrown when the caller is not the maker of the RFQ offer.
    /// @dev Thrown when an operation is attempted by an unauthorized caller who is not the maker of the RFQ offer.
    error NotOfferMaker();

    /// @notice Fills an RFQ offer.
    /// @param rfqTx The RFQ transaction details.
    /// @param makerSignature The signature of the maker authorizing the fill.
    /// @param makerTokenPermit The permit for spending maker's tokens.
    /// @param takerTokenPermit The permit for spending taker's tokens.
    function fillRFQ(RFQTx calldata rfqTx, bytes calldata makerSignature, bytes calldata makerTokenPermit, bytes calldata takerTokenPermit) external payable;

    /// @notice Fills an RFQ offer using a taker signature.
    /// @param rfqTx The RFQ transaction details.
    /// @param makerSignature The signature of the maker authorizing the fill.
    /// @param makerTokenPermit The permit for spending maker's tokens.
    /// @param takerTokenPermit The permit for spending taker's tokens.
    /// @param takerSignature The cryptographic signature of the taker authorizing the fill.
    function fillRFQWithSig(
        RFQTx calldata rfqTx,
        bytes calldata makerSignature,
        bytes calldata makerTokenPermit,
        bytes calldata takerTokenPermit,
        bytes calldata takerSignature
    ) external;

    /// @notice Cancels an RFQ offer.
    /// @param rfqOffer The RFQ offer to be canceled.
    function cancelRFQOffer(RFQOffer calldata rfqOffer) external;
}
