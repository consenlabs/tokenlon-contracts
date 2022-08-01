// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
import "contracts/test/veLON/Setup.t.sol";

contract TestVeLONDeposit is TestVeLON {
    using BalanceSnapshot for BalanceSnapshot.Snapshot;

    function testCreateLock() public {
        _stakeAndValidate(user, DEFAULT_STAKE_AMOUNT, MAX_LOCK_TIME);
    }

    function testFuzzCreateLock(uint256 _amount) public {
        vm.prank(user);
        vm.assume(_amount <= 100 * 1e18);
        vm.assume(_amount > 0);
        veLon.createLock(_amount, MAX_LOCK_TIME);
    }

    function testCannotCreateLockWithZero() public {
        vm.prank(user);
        vm.expectRevert("Zero lock amount");
        veLon.createLock(0, MAX_LOCK_TIME);
    }

    function testDepositFor() public {
        uint256 tokenId = _stakeAndValidate(user, DEFAULT_STAKE_AMOUNT, MAX_LOCK_TIME);
        require(tokenId != 0, "No lock created yet");

        stakerLon = BalanceSnapshot.take(user, address(lon));
        lockedLon = BalanceSnapshot.take(address(veLon), address(lon));
        vm.prank(user);
        veLon.depositFor(tokenId, 1);

        stakerLon.assertChange(-(1));
        lockedLon.assertChange(1);

        vm.stopPrank();
    }

    function testDepositForByOther() public {
        uint256 tokenId = _stakeAndValidate(user, DEFAULT_STAKE_AMOUNT, MAX_LOCK_TIME);
        vm.prank(other);
        veLon.depositFor(tokenId, 100);
    }

    function testFuzzDepositFor(uint256 _amount) public {
        uint256 tokenId = _stakeAndValidate(user, DEFAULT_STAKE_AMOUNT, MAX_LOCK_TIME);
        vm.prank(user);
        vm.assume(_amount <= 50 * 1e18);
        vm.assume(_amount > 0);
        veLon.depositFor(tokenId, _amount);
    }

    function testExtendLock() public {
        uint256 tokenId = _stakeAndValidate(user, DEFAULT_STAKE_AMOUNT, 1 weeks);
        uint256 lockEndBefore = veLon.unlockTime(tokenId);

        vm.prank(user);
        veLon.extendLock(tokenId, 2 weeks);
        uint256 lockEndAfter = veLon.unlockTime(tokenId);

        require((lockEndAfter - lockEndBefore) == 1 weeks, "wrong time extended");
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
        uint256 _fromTokenId = _stakeAndValidate(user, DEFAULT_STAKE_AMOUNT, MAX_LOCK_TIME);

        uint256 _toTokenId = _stakeAndValidate(other, DEFAULT_STAKE_AMOUNT, MAX_LOCK_TIME);
        vm.prank(other);
        veLon.approve(address(user), _toTokenId);

        vm.prank(user);
        veLon.merge(_fromTokenId, _toTokenId);

        // check whether fromToken has burned
        vm.expectRevert("ERC721: owner query for nonexistent token");
        veLon.ownerOf(_fromTokenId);
    }
}
