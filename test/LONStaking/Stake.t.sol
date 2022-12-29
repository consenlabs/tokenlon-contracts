// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import "test/LONStaking/Setup.t.sol";

contract TestLONStakingStake is TestLONStaking {
    using SafeMath for uint256;
    using BalanceSnapshot for BalanceSnapshot.Snapshot;

    function testCannotStakeWithZeroAmount() public {
        vm.expectRevert("cannot stake 0 amount");
        lonStaking.stake(0);
    }

    function testCannotStakeWhenPaused() public {
        lonStaking.pause();
        vm.expectRevert("Pausable: paused");
        vm.prank(user);
        lonStaking.stake(DEFAULT_STAKE_AMOUNT);
    }

    function testStake() public {
        _stakeAndValidate(user, DEFAULT_STAKE_AMOUNT);
    }

    /*********************************
     *         Fuzz Testing          *
     *********************************/

    function testFuzz_Stake(uint256 stakeAmount) public {
        stakeAmount = bound(stakeAmount, MIN_STAKE_AMOUNT, lon.cap().sub(lon.totalSupply()));

        lon.mint(user, stakeAmount);
        _stakeAndValidate(user, stakeAmount);
    }

    function testFuzz_StakeMultiple(uint256[16] memory stakeAmounts) public {
        uint256 totalLONAmount = lon.totalSupply();
        (stakeAmounts, totalLONAmount) = _boundStakeAmounts({ stakeAmounts: stakeAmounts, minStakeAmount: MIN_STAKE_AMOUNT, totalLONAmount: totalLONAmount });

        for (uint256 i = 0; i < stakeAmounts.length; i++) {
            address staker = address(uint256(fuzzingUserStartAddress) + i);
            uint256 stakeAmount = stakeAmounts[i];
            lon.mint(staker, stakeAmount);
            _stakeAndValidate(staker, stakeAmount);
        }
    }

    function testFuzz_StakeMultipleWithBuybackOneByOne(uint256[16] memory stakeAmounts, uint256[16] memory buybackAmounts) public {
        // Make initial big enough deposit so LON amount will not increase dramatically relative to xLON amount due to buyback
        // and hence result in later staker getting zero shares
        lon.mint(makeAddr("initial_depositor"), 10_000_000e18);
        _stake(makeAddr("initial_depositor"), 10_000_000e18); // stake 10m LON

        uint256 totalLONAmount = lon.totalSupply();
        (stakeAmounts, buybackAmounts, totalLONAmount) = _boundStakeAndBuybackAmounts(stakeAmounts, buybackAmounts, MIN_STAKE_AMOUNT, totalLONAmount);

        for (uint256 i = 0; i < stakeAmounts.length; i++) {
            address staker = address(uint256(fuzzingUserStartAddress) + i);
            uint256 stakeAmount = stakeAmounts[i];
            lon.mint(staker, stakeAmount);
            _stakeAndValidate(staker, stakeAmount);
            _simulateBuyback(buybackAmounts[i]);
        }
    }

    function testFuzz_StakeMultipleWithBuybackOneTime(uint256[16] memory stakeAmounts, uint256 buybackAmount) public {
        // Make initial big enough deposit so LON amount will not increase dramatically relative to xLON amount due to buyback
        // and hence result in later staker getting zero shares
        lon.mint(makeAddr("initial_depositor"), 10_000_000e18);
        _stake(makeAddr("initial_depositor"), 10_000_000e18); // stake 10m LON

        uint256 totalLONAmount = lon.totalSupply();
        for (uint256 i = 0; i < stakeAmounts.length; i++) {
            uint256 numStakeAmountLeft = stakeAmounts.length - i - 1;
            uint256 numBuybackAmountLeft = 1;
            // If stake amount is set to `lon.cap().sub(totalLONAmount)`, rest of the stake amount and buyback amount will all be zero and become invalid.
            // So an additional `numStakeAmountLeft * MIN_STAKE_AMOUNT * 2 + numBuybackAmountLeft * MIN_BUYBACK_AMOUNT` is subtracted from the max value of the current stake amount
            stakeAmounts[i] = bound(
                stakeAmounts[i],
                MIN_STAKE_AMOUNT,
                lon.cap().sub(totalLONAmount).sub(numStakeAmountLeft * MIN_STAKE_AMOUNT * 2 + numBuybackAmountLeft * MIN_BUYBACK_AMOUNT)
            );
            // Divide stake amount by half for two rounds of staking
            stakeAmounts[i] = stakeAmounts[i] > 1 ? stakeAmounts[i] / 2 : 1;
            totalLONAmount = totalLONAmount.add(stakeAmounts[i].mul(2));
        }
        buybackAmount = bound(buybackAmount, MIN_BUYBACK_AMOUNT, lon.cap().sub(totalLONAmount));

        // First batch of users stake
        address firstBatchUsersAddressStart = fuzzingUserStartAddress;
        for (uint256 i = 0; i < stakeAmounts.length; i++) {
            address firstBatchUser = address(uint256(firstBatchUsersAddressStart) + i);
            uint256 stakeAmount = stakeAmounts[i];
            lon.mint(firstBatchUser, stakeAmount);
            _stakeAndValidate(firstBatchUser, stakeAmount);
        }
        _simulateBuyback(buybackAmount);
        // Second batch of users stake
        address secondBatchUsersAddressStart = address(uint256(fuzzingUserStartAddress) + stakeAmounts.length);
        for (uint256 i = 0; i < stakeAmounts.length; i++) {
            address firstBatchUser = address(uint256(firstBatchUsersAddressStart) + i);
            address secondBatchUser = address(uint256(secondBatchUsersAddressStart) + i);
            uint256 stakeAmount = stakeAmounts[i];
            lon.mint(secondBatchUser, stakeAmount);
            _stakeAndValidate(secondBatchUser, stakeAmount);
            // Check that second batch user recieve less share than first batch of user because there's a buyback happens inbetween
            assertGt(lonStaking.balanceOf(firstBatchUser), lonStaking.balanceOf(secondBatchUser));
        }
    }

    /*********************************
     *          Test Helpers         *
     *********************************/

    function _stakeAndValidate(address staker, uint256 stakeAmount) internal {
        BalanceSnapshot.Snapshot memory stakerLon = BalanceSnapshot.take(staker, address(lon));
        BalanceSnapshot.Snapshot memory lonStakingLon = BalanceSnapshot.take(address(lonStaking), address(lon));
        BalanceSnapshot.Snapshot memory stakerXLON = BalanceSnapshot.take(staker, address(lonStaking));
        uint256 expectedStakeAmount = _getExpectedXLON(stakeAmount);
        vm.startPrank(staker);
        if (lon.allowance(staker, address(lonStaking)) == 0) {
            lon.approve(address(lonStaking), type(uint256).max);
        }
        lonStaking.stake(stakeAmount);
        stakerLon.assertChange(-int256(stakeAmount));
        lonStakingLon.assertChange(int256(stakeAmount));
        stakerXLON.assertChange(int256(expectedStakeAmount));
        vm.stopPrank();
    }
}
