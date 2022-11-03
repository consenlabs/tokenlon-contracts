// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
import "contracts/test/veLON/Setup.t.sol";

contract TestVeReward is TestVeLON {
    using BalanceSnapshot for BalanceSnapshot.Snapshot;

    function testEpoch() public {
        // uint256 tokenId = _stakeAndValidate(user, DEFAULT_STAKE_AMOUNT, DEFAULT_LOCK_TIME);
        // init
        (uint256 startTime, uint256 endTime, uint256 totalReward) = veRwd.getEpochInfo(0);
        assertEq(startTime, 0);
        assertEq(endTime, 0);
        assertEq(totalReward, 0);

        // add first epoch
        veRwd.addRewardForNextWeek(DEFAULT_REWARD_AMOUNT);
        (startTime, endTime, totalReward) = veRwd.getEpochInfo(0);
        assertEq(startTime, block.timestamp / 1 weeks * 1 weeks + 1 weeks);
        assertEq(endTime, startTime + 1 weeks);
        assertEq(totalReward, DEFAULT_REWARD_AMOUNT);

        // warp to the start time of first epoch
        vm.warp(startTime);
        uint256 epochId = veRwd.getCurrentEpochId();
        assertEq(epochId, 0);

        // add second and third epoch
        veRwd.addRewardForNextWeeksBatch(2 * DEFAULT_REWARD_AMOUNT, 2);
        (uint256 startTime1, uint256 endTime1, uint256 totalReward1) = veRwd.getEpochInfo(1);
        assertEq(startTime1, startTime + 1 weeks);
        assertEq(endTime1, startTime1 + 1 weeks);
        assertEq(totalReward1, DEFAULT_REWARD_AMOUNT);
        (uint256 startTime2, uint256 endTime2, uint256 totalReward2) = veRwd.getEpochInfo(2);
        assertEq(startTime2, startTime1 + 1 weeks);
        assertEq(endTime2, startTime2 + 1 weeks);
        assertEq(totalReward2, DEFAULT_REWARD_AMOUNT);

        assertEq(veRwd.getEpochIdByTime(startTime), 0);
        assertEq(veRwd.getEpochIdByTime(startTime + 3 days), 0);
        assertEq(veRwd.getEpochIdByTime(startTime1), 1);
        assertEq(veRwd.getEpochIdByTime(startTime1 + 3 days), 1);
        assertEq(veRwd.getEpochIdByTime(startTime2), 2);
        assertEq(veRwd.getEpochIdByTime(startTime2 + 3 days), 2);

        // vm.roll(block.number + 1);
        // vm.warp(block.timestamp + 2 weeks);
        // (uint256 reward, bool finished) = veRwd.getPendingRewardSingle(tokenId, 0);
        // assertEq(finished, true);
        // assertEq(reward, DEFAULT_REWARD_AMOUNT);
    }
}
