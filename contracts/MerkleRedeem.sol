// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "./interfaces/IEmergency.sol";
import "./Ownable.sol";
import "./utils/MerkleProof.sol";

contract MerkleRedeem is Ownable, ReentrancyGuard, IEmergency {
    using SafeMath for uint256;

    struct Claim {
        uint256 period;
        uint256 balance;
        bytes32[] proof;
    }

    IERC20 public rewardsToken;
    address public emergencyRecipient;

    // Recorded periods
    mapping(uint256 => bytes32) public periodMerkleRoots;
    mapping(uint256 => mapping(address => bool)) public claimed;

    /*==== PUBLIC FUNCTIONS =====*/
    constructor(
        address _owner,
        IERC20 _rewardsToken,
        address _emergencyRecipient
    ) Ownable(_owner) {
        emergencyRecipient = _emergencyRecipient;
        rewardsToken = _rewardsToken;
    }

    function claimPeriod(
        address recipient,
        uint256 period,
        uint256 balance,
        bytes32[] memory proof
    ) external nonReentrant {
        require(!claimed[period][recipient]);
        require(verifyClaim(recipient, period, balance, proof), "incorrect merkle proof");

        claimed[period][recipient] = true;
        _disburse(recipient, balance);
    }

    function verifyClaim(
        address recipient,
        uint256 period,
        uint256 balance,
        bytes32[] memory proof
    ) public view returns (bool) {
        bytes32 leaf = keccak256(abi.encodePacked(recipient, balance));
        return MerkleProof.verify(proof, periodMerkleRoots[period], leaf);
    }

    function claimPeriods(address recipient, Claim[] memory claims) external nonReentrant {
        uint256 totalBalance = 0;
        Claim memory claim;

        for (uint256 i = 0; i < claims.length; i++) {
            claim = claims[i];

            require(!claimed[claim.period][recipient]);
            require(verifyClaim(recipient, claim.period, claim.balance, claim.proof), "incorrect merkle proof");

            totalBalance = totalBalance.add(claim.balance);
            claimed[claim.period][recipient] = true;
        }

        _disburse(recipient, totalBalance);
    }

    function claimStatus(
        address recipient,
        uint256 begin,
        uint256 end
    ) external view returns (bool[] memory) {
        uint256 size = 1 + end - begin;
        bool[] memory arr = new bool[](size);
        for (uint256 i = 0; i < size; i++) {
            arr[i] = claimed[begin + i][recipient];
        }
        return arr;
    }

    function merkleRoots(uint256 begin, uint256 end) external view returns (bytes32[] memory) {
        uint256 size = 1 + end - begin;
        bytes32[] memory arr = new bytes32[](size);
        for (uint256 i = 0; i < size; i++) {
            arr[i] = periodMerkleRoots[begin + i];
        }
        return arr;
    }

    function emergencyWithdraw(IERC20 token) external override {
        require(token != rewardsToken, "forbidden token");

        token.transfer(emergencyRecipient, token.balanceOf(address(this)));
    }

    function seedAllocations(
        uint256 period,
        bytes32 merkleRoot,
        uint256 totalAllocation
    ) external onlyOwner {
        require(periodMerkleRoots[period] == bytes32(0), "already seed");

        periodMerkleRoots[period] = merkleRoot;
        require(rewardsToken.transferFrom(msg.sender, address(this), totalAllocation), "transfer failed");
    }

    function _disburse(address recipient, uint256 balance) private {
        if (balance > 0) {
            rewardsToken.transfer(recipient, balance);
            emit Claimed(recipient, balance);
        }
    }

    /*==== EVENTS ====*/
    event Claimed(address indexed recipient, uint256 balance);
}
