// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import "contracts-test/veReward/Setup.t.sol";
import "contracts/interfaces/IveReward.sol";

// TODO add test for getEpochStartBlock()
// TODO add test for getEpochTotalPower()

contract TestEpoch is TestVeReward {
    event AddEpoch(uint256 epochId, IveReward.EpochInfo epochInfo);
    event AddEpochBatch(uint256 startTime, uint256 epochLength, uint256 epochCount, uint256 startEpochId);

    function testCannotAddEndedEpoch() public {
        // end time < block.timestamp
        uint256 startTS = block.timestamp - 2 weeks;
        uint256 endTS = block.timestamp - 1 weeks;
        vm.prank(veRewardOwner);
        vm.expectRevert("invalid epoch schedule");
        veRwd.addEpoch(startTS, endTS, DEFAULT_TOTAL_REWARD);
    }

    function testCannotAddEpochWithInvalidSchedule() public {
        // end time < start time
        uint256 startTS = block.timestamp + 1 weeks;
        uint256 endTS = block.timestamp - 1 weeks;
        vm.prank(veRewardOwner);
        vm.expectRevert("invalid epoch schedule");
        veRwd.addEpoch(startTS, endTS, DEFAULT_TOTAL_REWARD);
    }

    function testCannotAddEpochWithExistedSchedule() public {
        uint256 startTS = block.timestamp + 1 weeks;
        uint256 endTS = block.timestamp + 2 weeks;
        vm.prank(veRewardOwner);
        veRwd.addEpoch(startTS, endTS, DEFAULT_TOTAL_REWARD);

        // the last endTS = now + 2 weeks, so the startTS of newly added epoch should not be less than that
        startTS = block.timestamp + 5 days;
        endTS = block.timestamp + 10 days;
        vm.prank(veRewardOwner);
        vm.expectRevert("epoch may exist already");
        veRwd.addEpoch(startTS, endTS, DEFAULT_TOTAL_REWARD);
    }

    function testAddEpochAndEmitEvent() public {
        uint256 startTS = block.timestamp + 1 weeks;
        vm.prank(veRewardOwner);
        vm.expectEmit(true, true, true, true);
        emit AddEpoch(
            0,
            IveReward.EpochInfo({
                startTime: startTS,
                endTime: startTS + DEFAULT_EPOCH_DURATION,
                rewardPerSecond: DEFAULT_TOTAL_REWARD * 4,
                totalPower: 1,
                startBlock: 1
            })
        );
        (uint256 epochId, uint256 totalReward) = veRwd.addEpoch(startTS, startTS + DEFAULT_EPOCH_DURATION, DEFAULT_TOTAL_REWARD);
        assertEq(epochId, 0);
        assertEq(totalReward, DEFAULT_TOTAL_REWARD);
    }

    function testGetEpochInfo() public {
        uint256 startTS = block.timestamp + 1 weeks;
        vm.prank(veRewardOwner);
        (, uint256 actualReward) = veRwd.addEpoch(startTS, startTS + DEFAULT_EPOCH_DURATION, DEFAULT_TOTAL_REWARD);
        (uint256 startTime, uint256 endTime, uint256 epochReward) = veRwd.getEpochInfo(0);
        assertEq(startTime, startTS);
        assertEq(endTime, startTS + DEFAULT_EPOCH_DURATION);
        assertEq(epochReward, actualReward);

        (startTime, endTime, epochReward) = veRwd.getEpochInfo(1);
        assertEq(startTime, 0);
        assertEq(endTime, 0);
        assertEq(epochReward, 0);
    }

    function testGetCurrentEpochId() public {
        uint256 startTS = block.timestamp + 1 weeks;
        vm.prank(veRewardOwner);
        veRwd.addEpoch(startTS, startTS + DEFAULT_EPOCH_DURATION, DEFAULT_TOTAL_REWARD);
        vm.warp(startTS);
        uint256 currentEpochId = veRwd.getCurrentEpochId();
        assertEq(currentEpochId, 0);
    }

    function testGetEpochIdByTime() public {
        uint256 startTS = block.timestamp + 5 days;
        vm.prank(veRewardOwner);
        veRwd.addEpoch(startTS, startTS + 5 days, DEFAULT_TOTAL_REWARD);

        vm.expectRevert("no epoch started");
        veRwd.getEpochIdByTime(block.timestamp);

        // will return last epoch id if query time is greater than the latest one
        startTS = block.timestamp + 50 days;
        vm.prank(veRewardOwner);
        veRwd.addEpoch(startTS, startTS + 5 days, DEFAULT_TOTAL_REWARD);
        uint256 epochId = veRwd.getEpochIdByTime(startTS + 20 weeks);
        assertEq(epochId, 1);
    }

    function testUpdateEpochReward() public {
        uint256 startTS = block.timestamp + 1 weeks;
        vm.prank(veRewardOwner);
        veRwd.addEpoch(startTS, startTS + DEFAULT_EPOCH_DURATION, DEFAULT_TOTAL_REWARD);

        // 2x the reward
        vm.prank(veRewardOwner);
        veRwd.updateEpochReward(0, DEFAULT_TOTAL_REWARD * 2);
        (, , uint256 epochReward) = veRwd.getEpochInfo(0);
        assertEq(epochReward, DEFAULT_TOTAL_REWARD * 2);

        // cannot update started epoch
        vm.warp(startTS);
        vm.prank(veRewardOwner);
        vm.expectRevert("epoch started already");
        veRwd.updateEpochReward(0, DEFAULT_TOTAL_REWARD * 2);
    }
}
