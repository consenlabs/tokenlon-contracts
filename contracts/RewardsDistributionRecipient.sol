// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

abstract contract RewardsDistributionRecipient {
    address public rewardsDistribution;

    function notifyRewardAmount(uint256 reward) external virtual;

    modifier onlyRewardsDistribution() {
        require(msg.sender == rewardsDistribution, "not rewards distribution");
        _;
    }
}
