// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import "contracts-test/LONStaking/Setup.t.sol";

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
        vm.assume(stakeAmount > 0);
        vm.assume(stakeAmount <= lon.cap());
        vm.assume(stakeAmount.add(lon.totalSupply()) <= lon.cap());

        lon.mint(user, stakeAmount);
        _stakeAndValidate(user, stakeAmount);
    }

    function testFuzz_StakeMultiple(uint80[16] memory stakeAmounts) public {
        // LON cap lies between 2**87 and 2**88, setting upper bound of stake amount to 2**80 - 1 so stake amount will not exceed cap
        uint256 totalLONAmount = lon.totalSupply();
        for (uint256 i = 0; i < stakeAmounts.length; i++) {
            vm.assume(stakeAmounts[i] > 0);
            totalLONAmount = totalLONAmount.add(stakeAmounts[i]);
            vm.assume(totalLONAmount <= lon.cap());
        }

        for (uint256 i = 0; i < stakeAmounts.length; i++) {
            address staker = address(uint256(fuzzingUserStartAddress) + i);
            uint256 stakeAmount = stakeAmounts[i];
            lon.mint(staker, stakeAmount);
            _stakeAndValidate(staker, stakeAmount);
        }
    }

    function testFuzz_StakeMultipleWithBuybackOneByOne(uint80[16] memory stakeAmounts, uint80[16] memory buybackAmounts) public {
        // LON cap lies between 2**87 and 2**88, setting upper bound of stake amount to 2**80 - 1 so stake amount will not exceed cap
        uint256 totalLONAmount = lon.totalSupply();
        for (uint256 i = 0; i < stakeAmounts.length; i++) {
            vm.assume(stakeAmounts[i] > 0);
            totalLONAmount = totalLONAmount.add(stakeAmounts[i]);
            vm.assume(totalLONAmount <= lon.cap());
        }
        for (uint256 i = 0; i < buybackAmounts.length; i++) {
            vm.assume(buybackAmounts[i] > 0);
            totalLONAmount = totalLONAmount.add(buybackAmounts[i]);
            vm.assume(totalLONAmount <= lon.cap());
        }

        // Make initial big enough deposit so LON amount will not increase dramatically relative to xLON amount due to buyback
        // and hence result in later staker getting zero shares
        lon.mint(address(0x5566), 10_000_000e18);
        _stake(address(0x5566), 10_000_000e18); // stake 10m LON

        for (uint256 i = 0; i < stakeAmounts.length; i++) {
            address staker = address(uint256(fuzzingUserStartAddress) + i);
            uint256 stakeAmount = stakeAmounts[i];
            lon.mint(staker, stakeAmount);
            _stakeAndValidate(staker, stakeAmount);
            _simulateBuyback(buybackAmounts[i]);
        }
    }

    function testFuzz_StakeMultipleWithBuybackOneTime(uint80[16] memory stakeAmounts, uint80 buybackAmount) public {
        // LON cap lies between 2**87 and 2**88, setting upper bound of stake amount to 2**80 - 1 so stake amount will not exceed cap
        uint256 totalLONAmount = lon.totalSupply();
        for (uint256 i = 0; i < stakeAmounts.length; i++) {
            vm.assume(stakeAmounts[i] > 0);
            totalLONAmount = totalLONAmount.add(stakeAmounts[i]);
            vm.assume(totalLONAmount <= lon.cap());
        }
        vm.assume(buybackAmount > 0);
        vm.assume(totalLONAmount.add(buybackAmount) <= lon.cap());

        // Make initial big enough deposit so LON amount will not increase dramatically relative to xLON amount due to buyback
        // and hence result in later staker getting zero shares
        lon.mint(address(0x5566), 10_000_000e18);
        _stake(address(0x5566), 10_000_000e18); // stake 10m LON

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
