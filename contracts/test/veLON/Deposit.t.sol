// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
import "contracts-test/veLON/Setup.t.sol";

contract TestVeLONDeposit is TestVeLON {
    using BalanceSnapshot for BalanceSnapshot.Snapshot;

    enum DepositType {
        CREATE_LOCK_TYPE,
        INCREASE_LOCK_AMOUNT,
        INCREASE_UNLOCK_TIME,
        MERGE_TYPE
    }
    event Deposit(address indexed provider, uint256 tokenId, uint256 value, uint256 indexed locktime, DepositType depositType, uint256 ts);
    event Supply(uint256 prevSupply, uint256 supply);

    function testFuzzCreateLock(uint256 _amount) public {
        vm.prank(user);
        vm.assume(_amount <= 100 * 1e18);
        vm.assume(_amount > 0);
        veLon.createLock(_amount, DEFAULT_LOCK_TIME);
    }

    function testCannotCreateLockWithZero() public {
        vm.prank(user);
        vm.expectRevert("Zero lock amount");
        veLon.createLock(0, DEFAULT_LOCK_TIME);
    }

    function testCreateLock() public {
        uint256 prevSupply = 0;
        stakerLon = BalanceSnapshot.take(user, address(lon));
        lockedLon = BalanceSnapshot.take(address(veLon), address(lon));
        uint256 nftSupplyBefore = veLon.totalSupply();
        uint256 expectedUnlockTime = block.timestamp + DEFAULT_LOCK_TIME;

        uint256 supply = DEFAULT_STAKE_AMOUNT;
        vm.expectEmit(true, true, true, true);
        emit Supply(prevSupply, supply);
        vm.expectEmit(true, true, true, true);
        emit Deposit(user, nftSupplyBefore + 1, DEFAULT_STAKE_AMOUNT, expectedUnlockTime, DepositType.CREATE_LOCK_TYPE, block.timestamp);

        uint256 tokenId = _stakeAndValidate(user, DEFAULT_STAKE_AMOUNT, DEFAULT_LOCK_TIME);

        stakerLon.assertChange(-int256(DEFAULT_STAKE_AMOUNT));
        lockedLon.assertChange(int256(DEFAULT_STAKE_AMOUNT));

        // check whether ERC721 token has minted
        uint256 nftSupplyAfter = veLon.totalSupply();
        assertEq((nftSupplyBefore + 1), nftSupplyAfter);

        // check epoch index
        assertEq(veLon.epoch(), 1);
        assertEq(veLon.userPointEpoch(tokenId), 1);

        uint256 vBalance = veLon.vBalanceOf(tokenId);
        // decliningRate = 10, lock duration = 2 weeks (exactly)
        assertEq(vBalance, 10 * 2 weeks);
        // only one user deposit in pool so represent the whole pool
        assertEq(vBalance, veLon.totalvBalance());
        // validate unlcok time
        assertEq(veLon.unlockTime(tokenId), expectedUnlockTime);
    }

    function testDepositFor() public {
        uint256 prevSupply = DEFAULT_STAKE_AMOUNT;
        uint256 tokenId = _stakeAndValidate(user, DEFAULT_STAKE_AMOUNT, DEFAULT_LOCK_TIME);
        require(tokenId != 0, "No lock created yet");
        uint256 lockEnd = veLon.unlockTime(tokenId);

        // check epoch index
        assertEq(veLon.epoch(), 1);
        assertEq(veLon.userPointEpoch(tokenId), 1);

        stakerLon = BalanceSnapshot.take(user, address(lon));
        lockedLon = BalanceSnapshot.take(address(veLon), address(lon));

        // deposit more on exsisting lock
        uint256 deposit2nd = 5 * 365 days;
        uint256 supply = prevSupply + deposit2nd;
        vm.prank(user);
        vm.expectEmit(true, true, true, true);
        emit Supply(prevSupply, supply);
        vm.expectEmit(true, true, true, true);
        emit Deposit(user, tokenId, deposit2nd, lockEnd, DepositType.INCREASE_LOCK_AMOUNT, block.timestamp);
        veLon.depositFor(tokenId, deposit2nd);

        stakerLon.assertChange(-(int256(deposit2nd)));
        lockedLon.assertChange(int256(deposit2nd));
        assertEq(veLon.vBalanceOf(tokenId), (10 + 5) * 2 weeks);
        assertEq(veLon.unlockTime(tokenId), lockEnd);

        // check epoch index
        assertEq(veLon.epoch(), 2);
        assertEq(veLon.userPointEpoch(tokenId), 2);
    }

    function testDepositForByOther() public {
        uint256 tokenId = _stakeAndValidate(user, DEFAULT_STAKE_AMOUNT, DEFAULT_LOCK_TIME);
        vm.prank(other);
        veLon.depositFor(tokenId, 100);
    }

    function testFuzzDepositFor(uint256 _amount) public {
        uint256 tokenId = _stakeAndValidate(user, DEFAULT_STAKE_AMOUNT, DEFAULT_LOCK_TIME);
        vm.prank(user);
        vm.assume(_amount <= 50 * 1e18);
        vm.assume(_amount > 0);
        veLon.depositFor(tokenId, _amount);
    }

    function testExtendLock() public {
        uint256 lockDuration = 2 weeks;
        uint256 tokenId = _stakeAndValidate(user, DEFAULT_STAKE_AMOUNT, lockDuration);
        uint256 lockEndBefore = veLon.unlockTime(tokenId);

        uint256 newLockDuration = lockDuration + 8 days;
        uint256 expectedNewEnd = lockEndBefore + 1 weeks; // round to weeks

        vm.prank(user);
        vm.expectEmit(true, true, true, true);
        emit Deposit(user, tokenId, 0, expectedNewEnd, DepositType.INCREASE_UNLOCK_TIME, block.timestamp);
        veLon.extendLock(tokenId, newLockDuration);

        assertEq(veLon.vBalanceOf(tokenId), 10 * (2 weeks + 1 weeks));
        assertEq(veLon.unlockTime(tokenId), expectedNewEnd);
        assertEq(veLon.epoch(), 2);
        assertEq(veLon.userPointEpoch(tokenId), 2);
    }

    function testCannotExtendLockNotAllowance() public {
        uint256 tokenId = _stakeAndValidate(user, DEFAULT_STAKE_AMOUNT, 1 weeks);

        vm.prank(other);
        vm.expectRevert("Not approved or owner");
        veLon.extendLock(tokenId, 1 weeks);
    }

    function testCannoExtendLockExpired() public {
        uint256 lockTime = 1 weeks;
        uint256 tokenId = _stakeAndValidate(user, DEFAULT_STAKE_AMOUNT, lockTime);

        // pretend 1 week has passed and the lock expired
        vm.warp(block.timestamp + 1 weeks);
        vm.prank(user);
        vm.expectRevert("Lock expired");
        veLon.extendLock(tokenId, lockTime);
    }

    function testMerge() public {
        uint256 _stakeAmountFrom = 2 * 356 days;
        uint256 _stakeDurationFrom = 15 weeks;
        uint256 _fromTokenId = _stakeAndValidate(user, _stakeAmountFrom, 15 weeks);
        uint256 _fromUnlockTime = veLon.unlockTime(_fromTokenId);

        uint256 _toTokenId = _stakeAndValidate(other, DEFAULT_STAKE_AMOUNT, DEFAULT_LOCK_TIME);
        vm.prank(other);
        veLon.approve(address(user), _toTokenId);

        vm.prank(user);
        vm.expectEmit(true, true, true, true);
        emit Deposit(user, _toTokenId, _stakeAmountFrom, _fromUnlockTime, DepositType.MERGE_TYPE, block.timestamp);
        veLon.merge(_fromTokenId, _toTokenId);

        // check wether the _toToken balance was increased as expected
        // _fromToken lock is longer(15 weeks) then _toToken(2 weeks), so the merged token's lock end would be 15 weeks
        uint256 expectedToBalance = _initialvBalance(_stakeAmountFrom + DEFAULT_STAKE_AMOUNT, _stakeDurationFrom);
        assertEq(expectedToBalance, veLon.vBalanceOf(_toTokenId));
        assertEq(expectedToBalance, veLon.totalvBalance());

        // check whether fromToken has burned
        vm.expectRevert("ERC721: owner query for nonexistent token");
        veLon.ownerOf(_fromTokenId);

        // create 2 locks and merge will generate 2 points
        assertEq(veLon.epoch(), 4);
    }
}
