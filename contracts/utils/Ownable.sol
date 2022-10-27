// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

/// @title Ownable Contract
/// @author imToken Labs
abstract contract Ownable {
    address public owner;
    address public nominatedOwner;

    event OwnerNominated(address indexed newOwner);
    event OwnerChanged(address indexed oldOwner, address indexed newOwner);

    constructor(address _owner) {
        require(_owner != address(0), "owner should not be 0");
        owner = _owner;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    /// @notice Activate new ownership
    /// @notice Called by nominated owner only
    function acceptOwnership() external {
        require(msg.sender == nominatedOwner, "not nominated");
        emit OwnerChanged(owner, nominatedOwner);

        owner = nominatedOwner;
        nominatedOwner = address(0);
    }

    /// @notice Give up the ownership of a contract
    /// @notice Called by owner only
    /// @notice Ownership cannot be recovered
    function renounceOwnership() external onlyOwner {
        emit OwnerChanged(owner, address(0));
        owner = address(0);
    }

    /// @notice Nominate new owner
    /// @notice Called by owner only
    /// @param newOwner The address of the new owner
    function nominateNewOwner(address newOwner) external onlyOwner {
        nominatedOwner = newOwner;
        emit OwnerNominated(newOwner);
    }
}
