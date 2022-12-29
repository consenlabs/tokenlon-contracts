// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import "test/LONStaking/Setup.t.sol";

contract TestLONStakingRageExit is TestLONStaking {
    using SafeMath for uint256;
    using BalanceSnapshot for BalanceSnapshot.Snapshot;

    function testCannotExitBeforeUnstake() public {
        vm.expectRevert("not yet unstake");
        vm.prank(user);
        lonStaking.rageExit();
    }

    function testRageExitWithoutPenalty() public {
        _stake(user, DEFAULT_STAKE_AMOUNT);
        vm.prank(user);
        lonStaking.unstake();

        // rageExit after cooldown ends
        vm.warp(block.timestamp + COOLDOWN_SECONDS + 1);

        _rageExitAndValidate(user);
    }

    function testRageExitWithPenalty() public {
        _stake(user, DEFAULT_STAKE_AMOUNT);
        vm.prank(user);
        lonStaking.unstake();

        // rageExit before cooldown ends
        vm.warp(block.timestamp + 2 days);

        _rageExitAndValidate(user);
    }

    function testRageExitWithBuybackPlusPenalty() public {
        _stake(user, DEFAULT_STAKE_AMOUNT);
        _simulateBuyback(100 * 1e18);

        vm.prank(user);
        lonStaking.unstake();

        // rageExit before cooldown ends
        vm.warp(block.timestamp + COOLDOWN_SECONDS / 5);

        _rageExitAndValidate(user);
    }

    function testPreviewRageExitWithoutPenalty() public {
        _stake(user, 100);
        vm.prank(user);
        lonStaking.unstake();

        // rageExit after cooldown ends
        vm.warp(block.timestamp + COOLDOWN_SECONDS + 1);

        (uint256 expectedLONAmount, uint256 penaltyAmount) = lonStaking.previewRageExit(user);

        assertEq(penaltyAmount, 0);
        assertEq(expectedLONAmount, 100);
    }

    function testPreviewRageExitWithPenalty() public {
        _stake(user, 100);
        vm.prank(user);
        lonStaking.unstake();

        // rageExit after cooldown ends
        vm.warp(block.timestamp + 2 days);

        (uint256 expectedLONAmount, uint256 penaltyAmount) = lonStaking.previewRageExit(user);

        // floor(100 * ((7 - 2 + 1) / 7) * (500 / 10000))
        // ((7 - 2 + 1) / 7): remaining days to cool down end
        // (500 / 10000): BPS_RAGE_EXIT_PENALTY / BPS_MAX
        assertEq(penaltyAmount, 4);
        // 100 - 4
        assertEq(expectedLONAmount, 96);
    }

    /*********************************
     *         Fuzz Testing          *
     *********************************/

    function testFuzz_RageExitWithPenalty(uint256 stakeAmount) public {
        stakeAmount = bound(stakeAmount, MIN_STAKE_AMOUNT, lon.cap().sub(lon.totalSupply()));

        lon.mint(user, stakeAmount);
        _stake(user, stakeAmount);
        vm.prank(user);
        lonStaking.unstake();

        vm.warp(block.timestamp + 2 days);

        _rageExitAndValidate(user);
    }

    function testFuzz_RageExitOneByOnePlusPenaltyWithMultipleStake(uint256[16] memory stakeAmounts) public {
        uint256 totalLONAmount = lon.totalSupply();
        (stakeAmounts, totalLONAmount) = _boundStakeAmounts({ stakeAmounts: stakeAmounts, minStakeAmount: MIN_STAKE_AMOUNT, totalLONAmount: totalLONAmount });

        for (uint256 i = 0; i < stakeAmounts.length; i++) {
            address staker = address(uint256(fuzzingUserStartAddress) + i);
            uint256 stakeAmount = stakeAmounts[i];
            lon.mint(staker, stakeAmount);
            _stake(staker, stakeAmount);
            vm.prank(staker);
            lonStaking.unstake();

            vm.warp(block.timestamp + 2 days);

            _rageExitAndValidate(staker);
        }
    }

    function testFuzz_RageExitOneTimePlusPenaltyWithMultipleStake(uint256[16] memory stakeAmounts) public {
        uint256 totalLONAmount = lon.totalSupply();
        (stakeAmounts, totalLONAmount) = _boundStakeAmounts({ stakeAmounts: stakeAmounts, minStakeAmount: MIN_STAKE_AMOUNT, totalLONAmount: totalLONAmount });

        // All stake and unstake
        for (uint256 i = 0; i < stakeAmounts.length; i++) {
            address staker = address(uint256(fuzzingUserStartAddress) + i);
            uint256 stakeAmount = stakeAmounts[i];
            lon.mint(staker, stakeAmount);
            _stake(staker, stakeAmount);
            vm.prank(staker);
            lonStaking.unstake();
        }
        vm.warp(block.timestamp + 2 days);
        // All redeem
        for (uint256 i = 0; i < stakeAmounts.length; i++) {
            address staker = address(uint256(fuzzingUserStartAddress) + i);
            _rageExitAndValidate(staker);
        }
    }

    function testFuzz_RageExitOneByOneWithBuybackPlusPenaltyWithMultipleStake(uint256[16] memory stakeAmounts, uint256[16] memory buybackAmounts) public {
        // Make initial big enough deposit so LON amount will not increase dramatically relative to xLON amount due to buyback
        // and hence result in later staker getting zero shares
        lon.mint(makeAddr("initial_depositor"), 10_000_000e18);
        _stake(makeAddr("initial_depositor"), 10_000_000e18); // stake 10m LON

        uint256 totalLONAmount = lon.totalSupply();
        (stakeAmounts, buybackAmounts, totalLONAmount) = _boundStakeAndBuybackAmounts({
            stakeAmounts: stakeAmounts,
            buybackAmounts: buybackAmounts,
            minStakeAmount: MIN_STAKE_AMOUNT,
            totalLONAmount: totalLONAmount
        });

        for (uint256 i = 0; i < stakeAmounts.length; i++) {
            address staker = address(uint256(fuzzingUserStartAddress) + i);
            uint256 stakeAmount = stakeAmounts[i];
            lon.mint(staker, stakeAmount);
            _stake(staker, stakeAmount);
            _simulateBuyback(buybackAmounts[i]);
            // Skip if stake did not get any share due to too small stakeAmount and rounding error
            if (lonStaking.balanceOf(staker) == 0) continue;

            vm.prank(staker);
            lonStaking.unstake();

            vm.warp(block.timestamp + 2 days);

            _rageExitAndValidate(staker);
        }
    }

    function testFuzz_RageExitOneTimeWithBuybackPlusPenaltyWithMultipleStake(uint256[16] memory stakeAmounts, uint256 buybackAmount) public {
        uint256 totalLONAmount = lon.totalSupply();
        for (uint256 i = 0; i < stakeAmounts.length; i++) {
            uint256 numStakeAmountLeft = stakeAmounts.length - i;
            uint256 numBuybackAmountLeft = 1;
            // If stake amount is set to `lon.cap().sub(totalLONAmount)`, rest of the stake amount and buyback amount will all be zero and become invalid.
            // So an additional `numStakeAmountLeft * MIN_STAKE_AMOUNT + numBuybackAmountLeft * MIN_BUYBACK_AMOUNT` is subtracted from the max value of the current stake amount
            stakeAmounts[i] = bound(
                stakeAmounts[i],
                MIN_STAKE_AMOUNT,
                lon.cap().sub(totalLONAmount).sub(numStakeAmountLeft * MIN_STAKE_AMOUNT + numBuybackAmountLeft * MIN_BUYBACK_AMOUNT)
            );
            totalLONAmount = totalLONAmount.add(stakeAmounts[i]);
        }
        buybackAmount = bound(buybackAmount, MIN_BUYBACK_AMOUNT, lon.cap().sub(totalLONAmount));

        // All stake and unstake
        for (uint256 i = 0; i < stakeAmounts.length; i++) {
            address staker = address(uint256(fuzzingUserStartAddress) + i);
            uint256 stakeAmount = stakeAmounts[i];
            lon.mint(staker, stakeAmount);
            _stake(staker, stakeAmount);
            vm.prank(staker);
            lonStaking.unstake();
        }
        vm.warp(block.timestamp + 2 days);
        _simulateBuyback(buybackAmount);
        // All redeem
        for (uint256 i = 0; i < stakeAmounts.length; i++) {
            address staker = address(uint256(fuzzingUserStartAddress) + i);
            _rageExitAndValidate(staker);
        }
    }

    /*********************************
     *          Test Helpers         *
     *********************************/

    function _rageExitAndValidate(address staker) internal {
        uint256 lonStakingXLONBefore = lonStaking.totalSupply();
        BalanceSnapshot.Snapshot memory lonStakingLON = BalanceSnapshot.take(address(lonStaking), address(lon));
        BalanceSnapshot.Snapshot memory stakerXLON = BalanceSnapshot.take(staker, address(lonStaking));
        BalanceSnapshot.Snapshot memory stakerLON = BalanceSnapshot.take(staker, address(lon));

        uint256 shareAmount = lonStaking.balanceOf(staker);
        (uint256 expectedLONAmount, ) = lonStaking.previewRageExit(staker);
        vm.prank(staker);
        lonStaking.rageExit();

        uint256 lonStakingXLONAfter = lonStaking.totalSupply();
        assertEq(lonStakingXLONAfter, lonStakingXLONBefore - shareAmount);
        lonStakingLON.assertChange(-int256(expectedLONAmount));
        stakerXLON.assertChange(-int256(shareAmount));
        stakerLON.assertChange(int256(expectedLONAmount));
    }
}
