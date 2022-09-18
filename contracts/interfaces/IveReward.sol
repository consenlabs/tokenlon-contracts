// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;
pragma abicoder v2;

interface IveReward {
    struct EpochInfo {
        uint256 startTime;
        uint256 endTime;
        uint256 rewardPerSecond; // totalReward * RewardMultiplier / (endBlock - startBlock)
        uint256 totalPower;
        uint256 startBlock;
    }

    struct Point {
        uint256 ts;
        uint256 blk; // block
    }

    struct Interval {
        uint256 startEpoch;
        uint256 endEpoch;
    }

    struct IntervalReward {
        uint256 startEpoch;
        uint256 endEpoch;
        uint256 reward;
    }

    struct RewardInfo {
        uint256 epochId;
        uint256 reward;
    }


    event LogClaimReward(uint256 tokenId, uint256 reward);
    event LogAddEpoch(uint256 epochId, EpochInfo epochInfo);
    event LogAddEpoch(uint256 startTime, uint256 epochLength, uint256 epochCount, uint256 startEpochId);
    event LogTransferAdmin(address pendingAdmin);
    event LogAcceptAdmin(address admin);


    function withdrawFee(uint256 amount) external;

    function transferAdmin(address _admin) external;

    function acceptAdmin() external;

    function updateEpochReward(uint256 epochId, uint256 totalReward) external;

    function addRewardForNextWeek(uint256 totalReward) external;

    function addRewardForNextWeeksBatch(uint256 totalReward, uint256 epochCount) external;
}