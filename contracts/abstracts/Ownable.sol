// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Ownable Contract
/// @author imToken Labs
/// @notice This contract manages ownership and allows transfer and renouncement of ownership.
/// @dev This contract uses a nomination system for ownership transfer.
abstract contract Ownable {
    address public owner;
    address public nominatedOwner;

    /// @notice Event emitted when a new owner is nominated.
    /// @param newOwner The address of the new nominated owner.
    event OwnerNominated(address indexed newOwner);

    /// @notice Event emitted when ownership is transferred.
    /// @param oldOwner The address of the previous owner.
    /// @param newOwner The address of the new owner.
    event OwnerChanged(address indexed oldOwner, address indexed newOwner);

    /// @notice Error to be thrown when the caller is not the owner.
    /// @dev This error is used to ensure that only the owner can call certain functions.
    error NotOwner();

    /// @notice Error to be thrown when the caller is not the nominated owner.
    /// @dev This error is used to ensure that only the nominated owner can accept ownership.
    error NotNominated();

    /// @notice Error to be thrown when the provided owner address is zero.
    /// @dev This error is used to ensure a valid address is provided for the owner.
    error ZeroOwner();

    /// @notice Error to be thrown when there is already a nominated owner.
    /// @dev This error is used to prevent nominating a new owner when one is already nominated.
    error NominationExists();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    /// @notice Constructor to set the initial owner of the contract.
    /// @param _owner The address of the initial owner.
    constructor(address _owner) {
        if (_owner == address(0)) revert ZeroOwner();
        owner = _owner;
    }

    /// @notice Accept the ownership transfer.
    /// @dev Only the nominated owner can call this function to accept the ownership.
    function acceptOwnership() external {
        if (msg.sender != nominatedOwner) revert NotNominated();
        emit OwnerChanged(owner, nominatedOwner);

        owner = nominatedOwner;
        nominatedOwner = address(0);
    }

    /// @notice Renounce ownership of the contract.
    /// @dev Only the current owner can call this function to renounce ownership. Once renounced, ownership cannot be recovered.
    function renounceOwnership() external onlyOwner {
        if (nominatedOwner != address(0)) revert NominationExists();
        emit OwnerChanged(owner, address(0));
        owner = address(0);
    }

    /// @notice Nominate a new owner.
    /// @dev Only the current owner can call this function to nominate a new owner.
    /// @param newOwner The address of the new owner.
    function nominateNewOwner(address newOwner) external onlyOwner {
        nominatedOwner = newOwner;
        emit OwnerNominated(newOwner);
    }
}
