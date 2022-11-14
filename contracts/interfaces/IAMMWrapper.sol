// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;

import "./IStrategyBase.sol";

/// @title IAMMWrapper Interface
/// @author imToken Labs
interface IAMMWrapper is IStrategyBase {
    /// @notice Emitted after swap with AMM
    /// @param source The tag of the contract where the order is filled
    /// @param transactionHash The hash of the transaction structure
    /// @param userAddr The address of taker
    /// @param relayed The hash of the order structure
    /// @param takerAssetAddr The taker assest used to swap
    /// @param takerAssetAmount The swap amount of taker asset
    /// @param makerAddr The address of maker
    /// @param makerAssetAddr The maker assest used to swap
    /// @param makerAssetAmount The swap amount of maker asset
    /// @param receiverAddr The address of who receives the maker asset
    /// @param settleAmount The actual amount of the maker asset recevied by receiver (settleAmount = makerAssetAmount - fee)
    /// @param feeFactor The factor used to calculate fee (fee = makerAssetAmount * feeFactor / BPS_MAX[=10000]))
    event Swapped(
        string source,
        bytes32 indexed transactionHash,
        address indexed userAddr,
        bool relayed,
        address takerAssetAddr,
        uint256 takerAssetAmount,
        address makerAddr,
        address makerAssetAddr,
        uint256 makerAssetAmount,
        address receiverAddr,
        uint256 settleAmount,
        uint16 feeFactor
    );

    // Group the local variables together to prevent stack too deep error
    struct TxMetaData {
        string source;
        bytes32 transactionHash;
        uint256 settleAmount;
        uint256 receivedAmount;
        uint16 feeFactor;
        bool relayed;
    }

    /// @notice Trade with AMM
    /// @param _makerAddress The AMM maker address
    /// @param _fromAssetAddress The input assest of the trade
    /// @param _toAssetAddress The output assest of the trade
    /// @param _takerAssetAmount The input amount of the trade
    /// @param _makerAssetAmount The output amount of the trade
    /// @param _feeFactor The factor used to calculate fee, only listed relayer can set it effectively
    /// @param _spender The address of the user
    /// @param _receiver The address of who receives the output asset
    /// @param _nonce A random number to prevent replay attack
    /// @param _deadline The time when this trade become expired
    /// @param _sig The signature of the trade from user
    /// @return The actual settled amount of the trade
    function trade(
        address _makerAddress,
        address _fromAssetAddress,
        address _toAssetAddress,
        uint256 _takerAssetAmount,
        uint256 _makerAssetAmount,
        uint256 _feeFactor,
        address _spender,
        address payable _receiver,
        uint256 _nonce,
        uint256 _deadline,
        bytes memory _sig
    ) external payable returns (uint256);
}
