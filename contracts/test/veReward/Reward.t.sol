// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "contracts-test/veReward/Setup.t.sol";
import "contracts-test/utils/BalanceSnapshot.sol";

contract TestReward is TestVeReward {
    using BalanceSnapshot for BalanceSnapshot.Snapshot;

    event ClaimReward(uint256 tokenId, uint256 reward);

    function testStakeAndGetReward() public {
        uint256 startTS = block.timestamp + 10 weeks;
        rewardToken.mint(address(veRwd), DEFAULT_TOTAL_REWARD);
        BalanceSnapshot.Snapshot memory veRwdReward = BalanceSnapshot.take({ owner: address(veRwd), token: address(rewardToken) });
        BalanceSnapshot.Snapshot memory userReward = BalanceSnapshot.take({ owner: user, token: address(rewardToken) });

        uint256 tokenId = _stakeVE(user, DEFAULT_STAKE_AMOUNT, DEFAULT_LOCK_TIME);

        vm.prank(veRewardOwner);
        vm.warp(block.timestamp + 2 weeks);
        vm.roll(block.number + 2000);
        (uint256 epochId, uint256 accurateTotalReward) = veRwd.addEpoch(startTS, startTS + DEFAULT_EPOCH_DURATION, DEFAULT_TOTAL_REWARD);
        vm.warp(startTS + DEFAULT_EPOCH_DURATION + 1 weeks);
        vm.roll(block.number + 2000);
        (uint256 reward, bool finished) = veRwd.getPendingRewardSingle(tokenId, epochId);
        // only 1 user stake so takes all reward
        assertEq(reward, accurateTotalReward);
        assertEq(finished, true);

        vm.prank(user);
        vm.expectEmit(true, true, true, true);
        emit ClaimReward(tokenId, accurateTotalReward);
        uint256 cliamedReward = veRwd.claimReward(tokenId, 0, 0);
        assertEq(cliamedReward, accurateTotalReward);
        veRwdReward.assertChange(-int256(DEFAULT_TOTAL_REWARD));
        userReward.assertChange(int256(DEFAULT_TOTAL_REWARD));
    }

    function testCannotClaimIfNotOwner() public {
        uint256 tokenId = _stakeVE(user, DEFAULT_STAKE_AMOUNT, DEFAULT_LOCK_TIME);
        vm.expectRevert("only veToken owner can claim");
        veRwd.claimReward(tokenId, 0, 0);
    }

    function testCannotClaimEpochOutOfRange() public {
        uint256 tokenId = _stakeVE(user, DEFAULT_STAKE_AMOUNT, DEFAULT_LOCK_TIME);
        vm.prank(veRewardOwner);
        uint256 startTS = block.timestamp + 10 weeks;
        vm.warp(block.timestamp + 2 weeks);
        vm.roll(block.number + 2000);
        veRwd.addEpoch(startTS, startTS + DEFAULT_EPOCH_DURATION, DEFAULT_TOTAL_REWARD);

        vm.prank(user);
        vm.expectRevert("claim out of range");
        veRwd.claimReward(tokenId, 0, 1);
    }
}
