// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { LimitOrder } from "../libraries/LimitOrder.sol";

/// @title ICoordinatedTaker Interface
/// @author imToken Labs
/// @notice This interface defines the functions and events for a coordinated taker contract.
/// @dev The contract handles limit order fills with additional coordination parameters.
interface ICoordinatedTaker {
    /// @notice Error to be thrown when a permission is reused.
    /// @dev This error is used to prevent the reuse of permissions.
    error ReusedPermission();

    /// @notice Error to be thrown when the msg.value is invalid.
    /// @dev This error is used to ensure that the correct msg.value is sent with the transaction.
    error InvalidMsgValue();

    /// @notice Error to be thrown when a signature is invalid.
    /// @dev This error is used to ensure that the provided signature is valid.
    error InvalidSignature();

    /// @notice Error to be thrown when a permission has expired.
    /// @dev This error is used to ensure that the permission has not expired.
    error ExpiredPermission();

    /// @notice Error to be thrown when an address is zero.
    /// @dev This error is used to ensure that a valid address is provided.
    error ZeroAddress();

    /// @title Coordinator Parameters
    /// @notice Struct for coordinator parameters.
    /// @dev Contains the signature, salt, and expiry for coordinator authorization.
    struct CoordinatorParams {
        bytes sig;
        uint256 salt;
        uint256 expiry;
    }

    /// @notice Emitted when a limit order is filled by the coordinator.
    /// @dev This event is emitted when a limit order is successfully filled.
    /// @param user The address of the user.
    /// @param orderHash The hash of the order.
    /// @param allowFillHash The hash of the allowed fill.
    event CoordinatorFill(address indexed user, bytes32 indexed orderHash, bytes32 indexed allowFillHash);

    /// @notice Emitted when the coordinator address is updated.
    /// @dev This event is emitted when the coordinator address is updated.
    /// @param newCoordinator The address of the new coordinator.
    event SetCoordinator(address newCoordinator);

    /// @notice Submits a limit order fill.
    /// @dev Allows a user to submit a limit order fill with additional coordination parameters.
    /// @param order The limit order to be filled.
    /// @param makerSignature The signature of the maker.
    /// @param takerTokenAmount The amount of tokens to be taken by the taker.
    /// @param makerTokenAmount The amount of tokens to be given by the maker.
    /// @param extraAction Any extra action to be performed.
    /// @param userTokenPermit The user's token permit.
    /// @param crdParams The coordinator parameters.
    function submitLimitOrderFill(
        LimitOrder calldata order,
        bytes calldata makerSignature,
        uint256 takerTokenAmount,
        uint256 makerTokenAmount,
        bytes calldata extraAction,
        bytes calldata userTokenPermit,
        CoordinatorParams calldata crdParams
    ) external payable;
}
