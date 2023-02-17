// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "./interfaces/IveLON.sol";
import "./interfaces/IveReward.sol";
import "./interfaces/IveLON.sol";
import "./utils/Ownable.sol";

contract veReward is IveReward, Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 public constant RewardMultiplier = 10000000;
    uint256 public constant BlockMultiplier = 1 ether;

    IveLON public immutable veLON;
    IERC20 public immutable rewardToken;

    EpochInfo[] public epochInfo;
    Point[] public pointHistory;
    mapping(uint256 => mapping(uint256 => uint256)) public userLastClaimTime; // tokenId -> epochId -> last claim timestamp

    constructor(
        address _owner,
        IveLON _veLON,
        IERC20 _rewardToken
    ) Ownable(_owner) {
        veLON = _veLON;
        rewardToken = _rewardToken;

        // add initial point
        _addCheckpoint();
    }

    function getEpochInfo(uint256 epochId)
        public
        view
        override
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        if (epochId >= epochInfo.length) {
            return (0, 0, 0);
        }
        EpochInfo memory epoch = epochInfo[epochId];
        uint256 totalReward = (epoch.endTime.sub(epoch.startTime)).mul(epoch.rewardPerSecond).div(RewardMultiplier);
        return (epoch.startTime, epoch.endTime, totalReward);
    }

    function getCurrentEpochId() public view override returns (uint256) {
        return getEpochIdByTime(block.timestamp);
    }

    function getEpochIdByTime(uint256 _time) public view override returns (uint256) {
        require(epochInfo[0].startTime <= _time, "no epoch started");
        if (_time > epochInfo[epochInfo.length - 1].startTime) {
            return epochInfo.length - 1;
        }
        // Binary search
        uint256 _min = 0;
        uint256 _max = epochInfo.length - 1;
        for (uint256 i = 0; i < 128; ++i) {
            // Will be always enough for 128-bit numbers
            if (_min >= _max) {
                break;
            }
            uint256 _mid = (_min + _max + 1) / 2;
            if (epochInfo[_mid].startTime <= _time) {
                _min = _mid;
            } else {
                _max = _mid - 1;
            }
        }
        return _min;
    }

    function getEpochStartBlock(uint256 epochId) public view override returns (uint256) {
        if (epochInfo[epochId].startBlock == 1) {
            return getBlockByTimeWithoutLastCheckpoint(epochInfo[epochId].startTime);
        }
        return epochInfo[epochId].startBlock;
    }

    function getEpochTotalPower(uint256 epochId) public view override returns (uint256) {
        if (epochInfo[epochId].totalPower == 1) {
            uint256 blk = getEpochStartBlock(epochId);
            if (blk > block.number) {
                return veLON.totalvBalanceAtTime(epochInfo[epochId].startTime);
            }
            return veLON.totalvBalanceAtBlk(blk);
        }
        return epochInfo[epochId].totalPower;
    }

    function getBlockByTime(uint256 _time) public view override returns (uint256) {
        // Binary search
        uint256 _min = 0;
        uint256 _max = pointHistory.length - 1;
        for (uint256 i = 0; i < 128; ++i) {
            // Will be always enough for 128-bit numbers
            if (_min >= _max) {
                break;
            }
            uint256 _mid = (_min + _max + 1) / 2;
            if (pointHistory[_mid].ts <= _time) {
                _min = _mid;
            } else {
                _max = _mid - 1;
            }
        }

        Point memory pointFrom = pointHistory[_min];
        Point memory pointTo = pointHistory[_min + 1];
        if (_time == pointFrom.ts) {
            return pointFrom.blk;
        }
        uint256 blockSlope;
        blockSlope = (BlockMultiplier.mul(pointTo.blk.sub(pointFrom.blk))).div(pointTo.ts.sub(pointFrom.ts));
        uint256 dblock = (blockSlope.mul(_time.sub(pointFrom.ts))).div(BlockMultiplier);
        return pointFrom.blk + dblock;
    }

    function getBlockByTimeWithoutLastCheckpoint(uint256 _time) public view override returns (uint256) {
        if (pointHistory[pointHistory.length - 1].ts >= _time) {
            return getBlockByTime(_time);
        }
        Point memory lastPoint = pointHistory[pointHistory.length - 1];
        if (_time == lastPoint.ts) {
            return lastPoint.blk;
        }
        uint256 blockSlope;
        blockSlope = (BlockMultiplier.mul(block.number.sub(lastPoint.blk))).div(block.timestamp.sub(lastPoint.ts));
        uint256 dblock = (blockSlope.mul(_time.sub(lastPoint.ts))).div(BlockMultiplier);
        return lastPoint.blk + dblock;
    }

    function getUserPower(uint256 tokenId, uint256 epochId) public view override returns (uint256) {
        EpochInfo memory epoch = epochInfo[epochId];
        uint256 blk = getBlockByTimeWithoutLastCheckpoint(epoch.startTime);
        if (blk < block.number) {
            return veLON.vBalanceOfAtBlk(tokenId, blk);
        }
        return veLON.vBalanceOfAtTime(tokenId, epochInfo[epochId].startTime);
    }

    function getPendingRewardSingle(uint256 tokenId, uint256 epochId) public view override returns (uint256 reward, bool finished) {
        if (epochId > getCurrentEpochId()) {
            return (0, false);
        }
        EpochInfo memory epoch = epochInfo[epochId];

        uint256 startBlock = getEpochStartBlock(epochId);

        uint256 totalPower = getEpochTotalPower(epochId);
        if (totalPower == 0) {
            return (0, true);
        }
        uint256 power = veLON.vBalanceOfAtBlk(tokenId, startBlock);

        uint256 last = userLastClaimTime[tokenId][epochId];
        last = last >= epoch.startTime ? last : epoch.startTime;
        if (last >= epoch.endTime) {
            return (0, true);
        }

        uint256 end = block.timestamp;
        finished = false;
        if (end > epoch.endTime) {
            end = epoch.endTime;
            finished = true;
        }

        reward = (epoch.rewardPerSecond.mul(end.sub(last)).mul(power)).div(totalPower.mul(RewardMultiplier));
        return (reward, finished);
    }

    function getPendingReward(
        uint256 tokenId,
        uint256 start,
        uint256 end
    ) public view override returns (IntervalReward[] memory intervalRewards) {
        uint256 current = getCurrentEpochId();
        require(start <= end);
        if (end > current) {
            end = current;
        }
        RewardInfo[] memory rewards = new RewardInfo[](end - start + 1);
        for (uint256 i = start; i <= end; i++) {
            if (block.timestamp < epochInfo[i].startTime) {
                break;
            }
            (uint256 reward_i, ) = getPendingRewardSingle(tokenId, i);
            rewards[i - start] = RewardInfo(i, reward_i);
        }

        // omit zero rewards and convert epoch list to intervals
        IntervalReward[] memory intervalRewards_0 = new IntervalReward[](rewards.length);
        uint256 intv = 0;
        uint256 intvCursor = 0;
        uint256 sum = 0;
        for (uint256 i = 0; i < rewards.length; i++) {
            if (rewards[i].reward == 0) {
                if (i != intvCursor) {
                    intervalRewards_0[intv] = IntervalReward(rewards[intvCursor].epochId, rewards[i - 1].epochId, sum);
                    intv++;
                    sum = 0;
                }
                intvCursor = i + 1;
                continue;
            }
            sum += rewards[i].reward;
        }
        if (sum > 0) {
            intervalRewards_0[intv] = IntervalReward(rewards[intvCursor].epochId, rewards[rewards.length - 1].epochId, sum);
            intervalRewards = new IntervalReward[](intv + 1);
            // Copy interval array
            for (uint256 i = 0; i < intv + 1; i++) {
                intervalRewards[i] = intervalRewards_0[i];
            }
        } else {
            intervalRewards = new IntervalReward[](intv);
            // Copy interval array
            for (uint256 i = 0; i < intv; i++) {
                intervalRewards[i] = intervalRewards_0[i];
            }
        }

        return intervalRewards;
    }

    function withdrawFee(uint256 _amount) external override onlyOwner {
        IERC20(rewardToken).safeTransfer(owner, _amount);
    }

    function updateEpochReward(uint256 _epochId, uint256 _totalReward) external override onlyOwner {
        EpochInfo memory _epoch = epochInfo[_epochId];
        require(block.timestamp < _epoch.startTime, "epoch started already");
        epochInfo[_epochId].rewardPerSecond = (_totalReward * RewardMultiplier) / (_epoch.endTime - _epoch.startTime);
    }

    function addEpoch(
        uint256 startTime,
        uint256 endTime,
        uint256 totalReward
    ) external override onlyOwner returns (uint256, uint256) {
        require(block.timestamp < endTime && startTime < endTime, "invalid epoch schedule");
        if (epochInfo.length > 0) {
            require(epochInfo[epochInfo.length - 1].endTime <= startTime, "epoch may exist already");
        }
        (uint256 epochId, uint256 accurateTotalReward) = _addEpoch(startTime, endTime, totalReward);
        uint256 lastPointTime = pointHistory[pointHistory.length - 1].ts;
        if (lastPointTime < block.timestamp) {
            _addCheckpoint();
        }
        emit AddEpoch(epochId, epochInfo[epochId]);
        return (epochId, accurateTotalReward);
    }

    function addEpochBatch(
        uint256 startTime,
        uint256 epochLength,
        uint256 epochCount,
        uint256 totalReward
    )
        external
        override
        onlyOwner
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        require(block.timestamp < startTime + epochLength);
        if (epochInfo.length > 0) {
            require(epochInfo[epochInfo.length - 1].endTime <= startTime);
        }
        uint256 _reward = totalReward / epochCount;
        uint256 _epochId;
        uint256 accurateTR;
        uint256 _start = startTime;
        uint256 _end = _start + epochLength;
        for (uint256 i = 0; i < epochCount; i++) {
            (_epochId, accurateTR) = _addEpoch(_start, _end, _reward);
            _start = _end;
            _end = _start + epochLength;
        }
        uint256 lastPointTime = pointHistory[pointHistory.length - 1].ts;
        if (lastPointTime < block.timestamp) {
            _addCheckpoint();
        }
        emit AddEpochBatch(startTime, epochLength, epochCount, _epochId + 1 - epochCount);
        return (_epochId + 1 - epochCount, _epochId, accurateTR * epochCount);
    }

    function _addEpoch(
        uint256 startTime,
        uint256 endTime,
        uint256 totalReward
    ) internal returns (uint256, uint256) {
        uint256 duration = endTime.sub(startTime);
        uint256 rewardPerSecond = (totalReward.mul(RewardMultiplier)).div(duration);
        uint256 epochId = epochInfo.length;
        epochInfo.push(EpochInfo(startTime, endTime, rewardPerSecond, 1, 1));
        uint256 accurateTotalReward = (duration.mul(rewardPerSecond)).div(RewardMultiplier);
        return (epochId, accurateTotalReward);
    }

    function _addCheckpoint() internal {
        pointHistory.push(Point(block.timestamp, block.number));
    }

    function checkpointAndCheckEpoch(uint256 epochId) external override {
        uint256 lastPointTime = pointHistory[pointHistory.length - 1].ts;
        if (lastPointTime < block.timestamp) {
            _addCheckpoint();
        }
        _checkEpoch(epochId);
    }

    function _checkEpoch(uint256 epochId) internal {
        // init epoch, fill `startBlock` and `totalPower` at this moment.
        if (epochInfo[epochId].startBlock == 1) {
            epochInfo[epochId].startBlock = getBlockByTime(epochInfo[epochId].startTime);
        }
        if (epochInfo[epochId].totalPower == 1) {
            epochInfo[epochId].totalPower = veLON.totalvBalanceAtBlk(epochInfo[epochId].startBlock);
        }
    }

    function claimRewardBatch(uint256[] calldata tokenIds, Interval[][] calldata intervals) public override returns (uint256[] memory rewards) {
        require(tokenIds.length == intervals.length, "length not equal");
        rewards = new uint256[](tokenIds.length);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            rewards[i] = claimRewardIntervals(tokenIds[i], intervals[i]);
        }
        return rewards;
    }

    function claimRewardIntervals(uint256 tokenId, Interval[] calldata intervals) public override returns (uint256 reward) {
        for (uint256 i = 0; i < intervals.length; i++) {
            reward += claimReward(tokenId, intervals[i].startEpoch, intervals[i].endEpoch);
        }
        return reward;
    }

    function claimReward(
        uint256 tokenId,
        uint256 startEpoch,
        uint256 endEpoch
    ) public override returns (uint256 totalReward) {
        require(msg.sender == veLON.ownerOf(tokenId), "only veToken owner can claim");
        require(endEpoch < epochInfo.length, "claim out of range");
        EpochInfo memory epoch;
        uint256 lastPointTime = pointHistory[pointHistory.length - 1].ts;
        for (uint256 i = startEpoch; i <= endEpoch; i++) {
            epoch = epochInfo[i];
            if (block.timestamp < epoch.startTime) {
                break;
            }
            if (lastPointTime < epoch.startTime) {
                // this branch runs 0 or 1 time
                lastPointTime = block.timestamp;
                _addCheckpoint();
            }
            _checkEpoch(i);
            (uint256 singleReward, bool finished) = _pendingRewardSingle(tokenId, userLastClaimTime[tokenId][i], epochInfo[i]);
            if (singleReward > 0) {
                totalReward = totalReward.add(singleReward);
                userLastClaimTime[tokenId][i] = block.timestamp;
            }
            if (!finished) {
                break;
            }
        }
        IERC20(rewardToken).safeTransfer(veLON.ownerOf(tokenId), totalReward);
        emit ClaimReward(tokenId, totalReward);
        return totalReward;
    }

    function _pendingRewardSingle(
        uint256 tokenId,
        uint256 lastClaimTime,
        EpochInfo memory epoch
    ) internal view returns (uint256, bool) {
        uint256 last = lastClaimTime >= epoch.startTime ? lastClaimTime : epoch.startTime;
        if (last >= epoch.endTime) {
            return (0, true);
        }
        if (epoch.totalPower == 0) {
            return (0, true);
        }

        uint256 end = block.timestamp;
        bool finished = false;
        if (end > epoch.endTime) {
            end = epoch.endTime;
            finished = true;
        }
        uint256 power = veLON.vBalanceOfAtBlk(tokenId, epoch.startBlock);

        // reward = (powerRatio * rewardRate) / RewardMultiplier
        uint256 reward = (epoch.rewardPerSecond * (end - last) * power) / (epoch.totalPower * RewardMultiplier);
        return (reward, finished);
    }
}
