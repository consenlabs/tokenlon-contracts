// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;
pragma abicoder v2;

import "./IStrategyBase.sol";
import "../utils/RFQLibEIP712.sol";

/// @title IRFQ Interface
/// @author imToken Labs
interface IRFQ is IStrategyBase {
    /// @notice Emitted when order is filled
    /// @param source The tag of the contract where the order is filled
    /// @param transactionHash The hash of the transaction structure
    /// @param orderHash The hash of the order structure
    /// @param userAddr The address of taker
    /// @param takerAssetAddr The taker assest used to swap
    /// @param takerAssetAmount The swap amount of taker asset
    /// @param makerAddr The address of maker
    /// @param makerAssetAddr The maker assest used to swap
    /// @param makerAssetAmount The swap amount of maker asset
    /// @param receiverAddr The address of who receives the maker asset
    /// @param settleAmount The actual amount of the maker asset recevied by receiver (settleAmount = makerAssetAmount - fee)
    /// @param feeFactor The factor used to calculate fee (fee = makerAssetAmount * feeFactor / BPS_MAX[=10000]))
    event FillOrder(
        string source,
        bytes32 indexed transactionHash,
        bytes32 indexed orderHash,
        address indexed userAddr,
        address takerAssetAddr,
        uint256 takerAssetAmount,
        address makerAddr,
        address makerAssetAddr,
        uint256 makerAssetAmount,
        address receiverAddr,
        uint256 settleAmount,
        uint16 feeFactor
    );

    /// @notice Fill an order
    /// @notice Only order with correct signatures of taker and maker can be filled and filled only once
    /// @param _order The order that is going to be filled
    /// @param _mmSignature The signature of the order from maker
    /// @param _userSignature The signature of the order from taker
    /// @return The settled amount of the order
    function fill(
        RFQLibEIP712.Order memory _order,
        bytes memory _mmSignature,
        bytes memory _userSignature
    ) external payable returns (uint256);
}
