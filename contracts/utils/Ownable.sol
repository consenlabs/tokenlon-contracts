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

    /// @notice activate new ownership
    /// @notice called by nominated owner only
    function acceptOwnership() external {
        require(msg.sender == nominatedOwner, "not nominated");
        emit OwnerChanged(owner, nominatedOwner);

        owner = nominatedOwner;
        nominatedOwner = address(0);
    }

    /// @notice give up the ownership of a contract
    /// @notice called by owner only
    /// @notice ownership cannot be recovered
    function renounceOwnership() external onlyOwner {
        emit OwnerChanged(owner, address(0));
        owner = address(0);
    }

    /// @notice nominate new owner
    /// @notice called by owner only
    /// @param newOwner the address of the new owner
    function nominateNewOwner(address newOwner) external onlyOwner {
        nominatedOwner = newOwner;
        emit OwnerNominated(newOwner);
    }
}
