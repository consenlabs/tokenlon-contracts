// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "./interfaces/IveLON.sol";

contract veReward {
    using SafeERC20 for IERC20;

    struct EpochInfo {
        uint256 startTime;
        uint256 endTime;
        uint256 rewardPerSecond; // totalReward * RewardMultiplier / (endBlock - startBlock)
        uint256 totalPower;
        uint256 startBlock;
    }

    /// @dev RewardMultiplier
    uint256 public constant RewardMultiplier = 10000000;
    /// @dev BlockMultiplier
    uint256 public constant BlockMultiplier = 1000000000000000000;

    /// @dev veLON
    IveLON public immutable veLON;
    /// @dev reward token
    IERC20 public immutable rewardToken;

    /// @dev reward epochs.
    EpochInfo[] public epochInfo;

    /// @dev user's last claim time.
    mapping(uint256 => mapping(uint256 => uint256)) public userLastClaimTime; // tokenId -> epoch id -> last claim timestamp

    struct Point {
        uint256 ts;
        uint256 blk; // block
    }

    /// @dev list of checkpoints, used in getBlockByTime
    Point[] public point_history;

    address public admin;
    address public pendingAdmin;

    modifier onlyAdmin() {
        require(msg.sender == admin);
        _;
    }

    event LogClaimReward(uint256 tokenId, uint256 reward);
    event LogAddEpoch(uint256 epochId, EpochInfo epochInfo);
    event LogAddEpoch(uint256 startTime, uint256 epochLength, uint256 epochCount, uint256 startEpochId);
    event LogTransferAdmin(address pendingAdmin);
    event LogAcceptAdmin(address admin);

    constructor(
        address _admin,
        IveLON _veLON,
        IERC20 _rewardToken
    ) {
        admin = _admin;
        veLON = _veLON;
        rewardToken = _rewardToken;

        // add init point
        addCheckpoint();
    }

    function withdrawFee(uint256 amount) external onlyAdmin {
        IERC20(rewardToken).safeTransfer(admin, amount);
    }

    function transferAdmin(address _admin) external onlyAdmin {
        pendingAdmin = _admin;
        emit LogTransferAdmin(pendingAdmin);
    }

    function acceptAdmin() external {
        require(msg.sender == pendingAdmin);
        admin = pendingAdmin;
        pendingAdmin = address(0);
        emit LogAcceptAdmin(admin);
    }

    /// @notice add checkpoint to point_history
    /// called in constructor, addEpoch, addEpochBatch and claimReward
    /// point_history increments without repetition, length always >= 1
    function addCheckpoint() internal {
        point_history.push(Point(block.timestamp, block.number));
    }

    /// @notice estimate last block number before given time
    /// @return blockNumber
    function getBlockByTime(uint256 _time) public view returns (uint256) {
        // Binary search
        uint256 _min = 0;
        uint256 _max = point_history.length - 1; // asserting length >= 2
        for (uint256 i = 0; i < 128; ++i) {
            // Will be always enough for 128-bit numbers
            if (_min >= _max) {
                break;
            }
            uint256 _mid = (_min + _max + 1) / 2;
            if (point_history[_mid].ts <= _time) {
                _min = _mid;
            } else {
                _max = _mid - 1;
            }
        }

        Point memory point0 = point_history[_min];
        Point memory point1 = point_history[_min + 1];
        if (_time == point0.ts) {
            return point0.blk;
        }
        // asserting point0.blk < point1.blk, point0.ts < point1.ts
        uint256 block_slope; // dblock/dt
        block_slope = (BlockMultiplier * (point1.blk - point0.blk)) / (point1.ts - point0.ts);
        uint256 dblock = (block_slope * (_time - point0.ts)) / BlockMultiplier;
        return point0.blk + dblock;
    }

    /// @notice add a batch of continuous epochs
    /// @return firstEpochId
    /// @return lastEpochId
    /// @return accurateTotalReward
    function _addEpochBatch(
        uint256 startTime,
        uint256 epochLength,
        uint256 epochCount,
        uint256 totalReward
    )
        internal
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
        uint256 lastPointTime = point_history[point_history.length - 1].ts;
        if (lastPointTime < block.timestamp) {
            addCheckpoint();
        }
        emit LogAddEpoch(startTime, epochLength, epochCount, _epochId + 1 - epochCount);
        return (_epochId + 1 - epochCount, _epochId, accurateTR * epochCount);
    }

    /// @notice add one epoch
    /// @return epochId
    /// @return accurateTotalReward
    function _addEpoch(
        uint256 startTime,
        uint256 endTime,
        uint256 totalReward
    ) internal returns (uint256, uint256) {
        uint256 rewardPerSecond = (totalReward * RewardMultiplier) / (endTime - startTime);
        uint256 epochId = epochInfo.length;
        epochInfo.push(EpochInfo(startTime, endTime, rewardPerSecond, 1, 1));
        uint256 accurateTotalReward = ((endTime - startTime) * rewardPerSecond) / RewardMultiplier;
        return (epochId, accurateTotalReward);
    }

    /// @notice set epoch reward
    function updateEpochReward(uint256 epochId, uint256 totalReward) external onlyAdmin {
        _updateEpochReward(epochId, totalReward);
    }

    function _updateEpochReward(uint256 epochId, uint256 totalReward) internal {
        require(block.timestamp < epochInfo[epochId].startTime);
        epochInfo[epochId].rewardPerSecond = (totalReward * RewardMultiplier) / (epochInfo[epochId].endTime - epochInfo[epochId].startTime);
    }

    function addRewardForNextWeek(uint256 totalReward) external onlyWhitelist {
        uint256 startTime = block.timestamp / 1 weeks * 1 weeks + 1 weeks;
        uint256 endTime = startTime + 1 weeks;
        uint256 epochId = getEpochIdByTime(startTime);
        if (epochInfo[epochId].startTime == startTime) {
            _updateEpochReward(epochId, totalReward);
        } else if (epochInfo[epochId].endTime <= startTime) {
            _addEpoch(startTime, endTime, totalReward);
        }
    }

    function addRewardForNextWeeksBatch(uint256 totalReward, uint256 epochCount) external onlyWhitelist {
        uint256 startTime = block.timestamp / 1 weeks * 1 weeks + 1 weeks;
        _addEpochBatch(startTime, 1 weeks, epochCount, totalReward);
    }

    /// @notice query pending reward by epoch
    /// @return pendingReward
    /// @return finished
    /// panic when block.timestamp < epoch.startTime
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

        uint256 reward = (epoch.rewardPerSecond * (end - last) * power) / (epoch.totalPower * RewardMultiplier);
        return (reward, finished);
    }

    function checkpointAndCheckEpoch(uint256 epochId) public {
        uint256 lastPointTime = point_history[point_history.length - 1].ts;
        if (lastPointTime < block.timestamp) {
            addCheckpoint();
        }
        checkEpoch(epochId);
    }

    function checkEpoch(uint256 epochId) internal {
        if (epochInfo[epochId].startBlock == 1) {
            epochInfo[epochId].startBlock = getBlockByTime(epochInfo[epochId].startTime);
        }
        if (epochInfo[epochId].totalPower == 1) {
            epochInfo[epochId].totalPower = veLON.totalvBalanceAtBlk(epochInfo[epochId].startBlock);
        }
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

    function claimRewardMany(uint256[] calldata tokenIds, Interval[][] calldata intervals) public returns (uint256[] memory rewards) {
        require(tokenIds.length == intervals.length, "length not equal");
        rewards = new uint256[](tokenIds.length);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            rewards[i] = claimReward(tokenIds[i], intervals[i]);
        }
        return rewards;
    }

    function claimReward(uint256 tokenId, Interval[] calldata intervals) public returns (uint256 reward) {
        for (uint256 i = 0; i < intervals.length; i++) {
            reward += claimReward(tokenId, intervals[i].startEpoch, intervals[i].endEpoch);
        }
        return reward;
    }

    /// @notice claim reward in range
    function claimReward(
        uint256 tokenId,
        uint256 startEpoch,
        uint256 endEpoch
    ) public returns (uint256 reward) {
        require(msg.sender == veLON.ownerOf(tokenId));
        require(endEpoch < epochInfo.length, "claim out of range");
        EpochInfo memory epoch;
        uint256 lastPointTime = point_history[point_history.length - 1].ts;
        for (uint256 i = startEpoch; i <= endEpoch; i++) {
            epoch = epochInfo[i];
            if (block.timestamp < epoch.startTime) {
                break;
            }
            if (lastPointTime < epoch.startTime) {
                // this branch runs 0 or 1 time
                lastPointTime = block.timestamp;
                addCheckpoint();
            }
            checkEpoch(i);
            (uint256 reward_i, bool finished) = _pendingRewardSingle(tokenId, userLastClaimTime[tokenId][i], epochInfo[i]);
            if (reward_i > 0) {
                reward += reward_i;
                userLastClaimTime[tokenId][i] = block.timestamp;
            }
            if (!finished) {
                break;
            }
        }
        IERC20(rewardToken).safeTransfer(veLON.ownerOf(tokenId), reward);
        emit LogClaimReward(tokenId, reward);
        return reward;
    }

    /// @notice get epoch by time
    function getEpochIdByTime(uint256 _time) public view returns (uint256) {
        assert(epochInfo[0].startTime <= _time);
        if (_time > epochInfo[epochInfo.length - 1].startTime) {
            return epochInfo.length - 1;
        }
        // Binary search
        uint256 _min = 0;
        uint256 _max = epochInfo.length - 1; // asserting length >= 2
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

    /**
    External read functions
     */
    struct RewardInfo {
        uint256 epochId;
        uint256 reward;
    }

    /// @notice get epoch info
    /// @return startTime
    /// @return endTime
    /// @return totalReward
    function getEpochInfo(uint256 epochId)
        public
        view
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
        uint256 totalReward = ((epoch.endTime - epoch.startTime) * epoch.rewardPerSecond) / RewardMultiplier;
        return (epoch.startTime, epoch.endTime, totalReward);
    }

    function getCurrentEpochId() public view returns (uint256) {
        uint256 currentEpochId = getEpochIdByTime(block.timestamp);
        return currentEpochId;
    }

    /// @notice only for external view functions
    /// Time beyond last checkpoint resulting in inconsistent estimated block number.
    function getBlockByTimeWithoutLastCheckpoint(uint256 _time) public view returns (uint256) {
        if (point_history[point_history.length - 1].ts >= _time) {
            return getBlockByTime(_time);
        }
        Point memory point0 = point_history[point_history.length - 1];
        if (_time == point0.ts) {
            return point0.blk;
        }
        uint256 block_slope;
        block_slope = (BlockMultiplier * (block.number - point0.blk)) / (block.timestamp - point0.ts);
        uint256 dblock = (block_slope * (_time - point0.ts)) / BlockMultiplier;
        return point0.blk + dblock;
    }

    function getEpochStartBlock(uint256 epochId) public view returns (uint256) {
        if (epochInfo[epochId].startBlock == 1) {
            return getBlockByTimeWithoutLastCheckpoint(epochInfo[epochId].startTime);
        }
        return epochInfo[epochId].startBlock;
    }

    function getEpochTotalPower(uint256 epochId) public view returns (uint256) {
        if (epochInfo[epochId].totalPower == 1) {
            uint256 blk = getEpochStartBlock(epochId);
            if (blk > block.number) {
                return veLON.totalvBalanceAtTime(epochInfo[epochId].startTime);
            }
            return veLON.totalvBalanceAtBlk(blk);
        }
        return epochInfo[epochId].totalPower;
    }

    /// @notice get user's power at epochId
    function getUserPower(uint256 tokenId, uint256 epochId) public view returns (uint256) {
        EpochInfo memory epoch = epochInfo[epochId];
        uint256 blk = getBlockByTimeWithoutLastCheckpoint(epoch.startTime);
        if (blk < block.number) {
            return veLON.vBalanceOfAtBlk(tokenId, blk);
        }
        return veLON.vBalanceOfAtTime(tokenId, epochInfo[epochId].startTime);
    }

    /// @notice
    /// Current epoch reward is inaccurate
    /// because the checkpoint may not have been added.
    function getPendingRewardSingle(uint256 tokenId, uint256 epochId) public view returns (uint256 reward, bool finished) {
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

        reward = (epoch.rewardPerSecond * (end - last) * power) / (totalPower * RewardMultiplier);
        return (reward, finished);
    }

    /// @notice get claimable reward
    function pendingReward(
        uint256 tokenId,
        uint256 start,
        uint256 end
    ) public view returns (IntervalReward[] memory intervalRewards) {
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
}
