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

    struct RewardInfo {
        uint256 epochId;
        uint256 reward;
    }

    struct Point {
        uint256 ts;
        uint256 blk;
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

    event ClaimReward(uint256 tokenId, uint256 reward);
    event AddEpoch(uint256 epochId, EpochInfo epochInfo);
    event AddEpochBatch(uint256 startTime, uint256 epochLength, uint256 epochCount, uint256 startEpochId);

    function getEpochInfo(uint256 epochId)
        external
        view
        returns (
            uint256,
            uint256,
            uint256
        );

    function getCurrentEpochId() external view returns (uint256);

    function getBlockByTime(uint256 _time) external view returns (uint256);

    function getEpochIdByTime(uint256 _time) external view returns (uint256);

    function getBlockByTimeWithoutLastCheckpoint(uint256 _time) external view returns (uint256);

    function getEpochStartBlock(uint256 epochId) external view returns (uint256);

    function getEpochTotalPower(uint256 epochId) external view returns (uint256);

    function getUserPower(uint256 tokenId, uint256 epochId) external view returns (uint256);

    function getPendingRewardSingle(uint256 tokenId, uint256 epochId) external view returns (uint256 reward, bool finished);

    function getPendingReward(
        uint256 tokenId,
        uint256 start,
        uint256 end
    ) external view returns (IntervalReward[] memory intervalRewards);

    function withdrawFee(uint256 _amount) external;

    function updateEpochReward(uint256 epochId, uint256 totalReward) external;

    function addEpoch(
        uint256 startTime,
        uint256 endTime,
        uint256 totalReward
    ) external returns (uint256, uint256);

    function addEpochBatch(
        uint256 startTime,
        uint256 epochLength,
        uint256 epochCount,
        uint256 totalReward
    )
        external
        returns (
            uint256,
            uint256,
            uint256
        );

    function checkpointAndCheckEpoch(uint256 epochId) external;

    function claimRewardBatch(uint256[] calldata tokenIds, Interval[][] calldata intervals) external returns (uint256[] memory rewards);

    function claimRewardIntervals(uint256 tokenId, Interval[] calldata intervals) external returns (uint256 reward);

    function claimReward(
        uint256 tokenId,
        uint256 startEpoch,
        uint256 endEpoch
    ) external returns (uint256 reward);
}
