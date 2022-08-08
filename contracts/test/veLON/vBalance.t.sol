// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "contracts/test/veLON/Setup.t.sol";

contract TestVeLONDeposit is TestVeLON {
    using SafeMath for uint256;
    using BalanceSnapshot for BalanceSnapshot.Snapshot;

    function testCreateLockTwoUsesSameBlock() public {
        uint256 total = 0;

        uint256 bobStakeAmount = 15 * 365 days;
        uint256 bobTokenId = _stakeAndValidate(bob, bobStakeAmount, 1 weeks);
        uint256 expectedBobInitvBal = 15 * 7 days;
        assertEq(veLon.vBalanceOf(bobTokenId), expectedBobInitvBal);
        total = total.add(expectedBobInitvBal);
        assertEq(veLon.totalvBalance(), total);

        uint256 aliceStakeAmount = 31 * 365 days;
        uint256 aliceTokenId = _stakeAndValidate(alice, aliceStakeAmount, 3 weeks);
        uint256 expectedAliceInitvBal = 31 * 3 weeks;
        assertEq(veLon.vBalanceOf(aliceTokenId), expectedAliceInitvBal);
        total = total.add(expectedAliceInitvBal);
        assertEq(veLon.totalvBalance(), total);
    }

    function testCreateLockTwoUsersDifferentBlock() public {
        uint256 total = 0;

        uint256 bobStakeAmount = 15 * 365 days;
        uint256 bobTokenId = _stakeAndValidate(bob, bobStakeAmount, 1 weeks);
        uint256 expectedBobInitvBal = 15 * 7 days;
        assertEq(veLon.vBalanceOf(bobTokenId), expectedBobInitvBal);
        total = total.add(expectedBobInitvBal);
        assertEq(veLon.totalvBalance(), total);

        // fastforward 1 day
        uint256 dt = 1 days;
        vm.warp(block.timestamp + dt);
        vm.roll(block.number + 1);

        // calculate bob's current vBalance
        uint256 bobBalance = expectedBobInitvBal.sub(dt * 15);
        total = total.sub(dt * 15);

        uint256 aliceStakeAmount = 31 * 365 days;
        uint256 aliceTokenId = _stakeAndValidate(alice, aliceStakeAmount, 1 weeks);
        // after rounding, end - start = 6 days
        uint256 expectedAliceInitvBal = 31 * 6 days;
        assertEq(veLon.vBalanceOf(aliceTokenId), expectedAliceInitvBal);
        total = total.add(expectedAliceInitvBal);
        assertEq(veLon.totalvBalance(), total);
    }

    /*****************************************
     *   Uint Test for balance of single Ve  *
     *****************************************/
    function testVbalanceOf() public {
        uint256 tokenId = _stakeAndValidate(user, DEFAULT_STAKE_AMOUNT, 2 weeks);
        uint256 vBalance = veLon.vBalanceOf(tokenId);
        uint256 expectBalance = 10 * 2 weeks;
        assertEq(vBalance, expectBalance, "Balance is not equal");
    }

    function testVBalanceOfAtTime() public {
        uint256 aliceStakeAmount = 10 * 365 days;
        uint256 aliceTokenId = _stakeAndValidate(alice, aliceStakeAmount, 2 weeks);

        // fast forward 1 week
        vm.warp(block.timestamp + 1 weeks);
        vm.roll(block.number + 1);

        // calculate Alice's balance
        // declineRate  = locking_amount / MAX_lock_duration = (10 * 365 days)/ 365days = 10
        // exptectedBalance = initial balance - decline balance = 10 * 2 weeks - 10 * 1 weeks = 10 * 1 week
        uint256 expectAliceBalance = 10 * 7 days;
        assertEq(veLon.vBalanceOfAtTime(aliceTokenId, block.timestamp), expectAliceBalance);
    }

    function testCannotGetVBalabnceInFuture() public {
        uint256 tokenId = _stakeAndValidate(user, DEFAULT_STAKE_AMOUNT, DEFAULT_LOCK_TIME);
        vm.expectRevert("Invalid timestamp");
        veLon.vBalanceOfAtTime(tokenId, block.timestamp + 1 weeks);
    }

    function testVBalanceOfAtBlk() public {
        uint256 tokenId = _stakeAndValidate(user, DEFAULT_STAKE_AMOUNT, DEFAULT_LOCK_TIME);

        // next block and 1 week later
        uint256 expectBalance = 10 * 1 weeks;
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1 weeks);
        assertEq(veLon.vBalanceOfAtBlk(tokenId, block.number), expectBalance);
    }

    function testCannotGetVBalabnceAtFutureBlk() public {
        uint256 tokenId = _stakeAndValidate(user, DEFAULT_STAKE_AMOUNT, 2 weeks);
        vm.expectRevert("Invalid block number");
        // get balance in future block
        veLon.vBalanceOfAtBlk(tokenId, block.number + 1);
    }

    /***********************************
     *   Uint Test for Total Balance *
     ***********************************/
    function testTotalvBalance() public {
        _stakeAndValidate(alice, DEFAULT_STAKE_AMOUNT, 2 weeks);
        _stakeAndValidate(bob, DEFAULT_STAKE_AMOUNT, 2 weeks);
        uint256 totalvBalance = veLon.totalvBalance();
        uint256 expectvBalance = _initialvBalance(2 * DEFAULT_STAKE_AMOUNT, 2 weeks);
        assertEq(totalvBalance, expectvBalance);
    }

    function testTotalvBalanceAtTime() public {
        _stakeAndValidate(user, DEFAULT_STAKE_AMOUNT, 2 weeks);
        uint256 totalvBalance = veLon.totalvBalanceAtTime(block.timestamp);
        uint256 expectvBalance = 10 * 2 weeks;
        assertEq(totalvBalance, expectvBalance);

        // test 1 week has passed
        vm.warp(block.timestamp + 1 weeks);
        vm.roll(block.number + 1);
        totalvBalance = veLon.totalvBalanceAtTime(block.timestamp);
        expectvBalance = 10 * 1 weeks;
        assertEq(totalvBalance, expectvBalance);
    }

    function testCannotGetTotalvBalanceInFuture() public {
        vm.expectRevert("Invalid timestamp");
        veLon.totalvBalanceAtTime(block.timestamp + 1 weeks);
    }

    function testTotalvBalanceAtBlk() public {
        _stakeAndValidate(user, DEFAULT_STAKE_AMOUNT, 2 weeks);
        uint256 totalvBalance = veLon.totalvBalanceAtBlk(block.number);
        uint256 expectvBalance = 10 * 2 weeks;
        assertEq(totalvBalance, expectvBalance);

        // 10 blocks and 1 week has passed
        expectvBalance = 10 * 1 weeks;
        vm.roll(block.number + 10);
        vm.warp(block.timestamp + 1 weeks);
        assertEq(veLon.totalvBalanceAtBlk(block.number), expectvBalance);
    }

    function testCannotGetTotalvBalanceAtFutureBlk() public {
        vm.expectRevert("Invalid block number");
        veLon.totalvBalanceAtBlk(block.number + 1);
    }
}
