// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Ownable Contract
/// @author imToken Labs
abstract contract Ownable {
    address public owner;
    address public nominatedOwner;

    error NotOwner();
    error NotNominated();
    error ZeroOwner();
    error NominationExists();

    event OwnerNominated(address indexed newOwner);
    event OwnerChanged(address indexed oldOwner, address indexed newOwner);

    constructor(address _owner) {
        if (_owner == address(0)) revert ZeroOwner();
        owner = _owner;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    /// @notice Activate new ownership
    /// @notice Only nominated owner can call
    function acceptOwnership() external {
        if (msg.sender != nominatedOwner) revert NotNominated();
        emit OwnerChanged(owner, nominatedOwner);

        owner = nominatedOwner;
        nominatedOwner = address(0);
    }

    /// @notice Give up the ownership
    /// @notice Only owner can call
    /// @notice Ownership cannot be recovered
    function renounceOwnership() external onlyOwner {
        if (nominatedOwner != address(0)) revert NominationExists();
        emit OwnerChanged(owner, address(0));
        owner = address(0);
    }

    /// @notice Nominate new owner
    /// @notice Only owner can call
    /// @param newOwner The address of the new owner
    function nominateNewOwner(address newOwner) external onlyOwner {
        nominatedOwner = newOwner;
        emit OwnerNominated(newOwner);
    }
}
