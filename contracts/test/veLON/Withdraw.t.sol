// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
import "contracts/test/veLON/Setup.t.sol";

contract TestVeLONWithfraw is TestVeLON {
    using SafeMath for uint256;
    using BalanceSnapshot for BalanceSnapshot.Snapshot;

    function testWithdraw() public {
        uint256 tokenId = _stakeAndValidate(user, DEFAULT_STAKE_AMOUNT, 1 weeks);

        stakerLon = BalanceSnapshot.take(user, address(lon));
        lockedLon = BalanceSnapshot.take(address(veLon), address(lon));

        // pretend 1 week has passed and the lock expired
        vm.prank(user);
        vm.warp(block.timestamp + 1 weeks);
        veLon.withdraw(tokenId);
        stakerLon.assertChange(int256(DEFAULT_STAKE_AMOUNT));
        lockedLon.assertChange(int256(-(DEFAULT_STAKE_AMOUNT)));

        // check whether token has burned after withdraw
        vm.expectRevert("ERC721: owner query for nonexistent token");
        veLon.ownerOf(tokenId);
    }

    function testWithdrawEarly() public {
        uint256 tokenId = _stakeAndValidate(user, DEFAULT_STAKE_AMOUNT, 2 weeks);

        stakerLon = BalanceSnapshot.take(user, address(lon));
        lockedLon = BalanceSnapshot.take(address(veLon), address(lon));

        // pretend 1 week has passed and the lock not expired
        vm.warp(block.timestamp + 1 weeks);
        vm.prank(user);
        veLon.withdrawEarly(tokenId);
        uint256 balanceChange = DEFAULT_STAKE_AMOUNT.mul(earlyWithdrawPenaltyRate).div(PENALTY_RATE_PRECISION);
        stakerLon.assertChange(int256(DEFAULT_STAKE_AMOUNT.sub(balanceChange)));

        // check whether token has burned after withdraw
        vm.expectRevert("ERC721: owner query for nonexistent token");
        veLon.ownerOf(tokenId);
    }

    function testWithdrawByOther() public {
        uint256 tokenId = _stakeAndValidate(user, DEFAULT_STAKE_AMOUNT, 2 weeks);
        vm.prank(user);
        veLon.approve(address(other), tokenId);
        vm.prank(other);
        vm.warp(block.timestamp + 2 weeks);
        veLon.withdraw(tokenId);
    }
}
