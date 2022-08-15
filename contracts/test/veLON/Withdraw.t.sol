// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
import "contracts/test/veLON/Setup.t.sol";

contract TestVeLONWithdraw is TestVeLON {
    using SafeMath for uint256;
    using BalanceSnapshot for BalanceSnapshot.Snapshot;

    event Withdraw(address indexed provider, bool indexed lockExpired, uint256 tokenId, uint256 withdrawValue, uint256 burnValue, uint256 ts);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Supply(uint256 prevSupply, uint256 supply);

    function testWithdraw() public {
        uint256 tokenId = _stakeAndValidate(user, DEFAULT_STAKE_AMOUNT, 1 weeks);
        uint256 prevSupply = DEFAULT_STAKE_AMOUNT;

        stakerLon = BalanceSnapshot.take(user, address(lon));
        lockedLon = BalanceSnapshot.take(address(veLon), address(lon));

        // pretend 1 week has passed and the lock expired
        vm.startPrank(user);
        vm.warp(block.timestamp + 1 weeks);
        vm.expectEmit(true, true, true, true);
        emit Withdraw(user, true, tokenId, DEFAULT_STAKE_AMOUNT, 0, block.timestamp);

        // check supply event
        uint256 supply = prevSupply - DEFAULT_STAKE_AMOUNT;
        vm.expectEmit(true, true, true, true);
        emit Supply(prevSupply, supply);

        veLon.withdraw(tokenId);
        stakerLon.assertChange(int256(DEFAULT_STAKE_AMOUNT));
        lockedLon.assertChange(int256(-(DEFAULT_STAKE_AMOUNT)));
        vm.stopPrank();

        // check whether token has burned after withdraw
        vm.expectRevert("ERC721: owner query for nonexistent token");
        veLon.ownerOf(tokenId);
    }

    function testWithdrawEarly() public {
        uint256 tokenId = _stakeAndValidate(user, DEFAULT_STAKE_AMOUNT, 2 weeks);
        uint256 prevSupply = DEFAULT_STAKE_AMOUNT;

        stakerLon = BalanceSnapshot.take(user, address(lon));
        lockedLon = BalanceSnapshot.take(address(veLon), address(lon));

        // set earlyWithdrawPenaltyRate from veLon
        uint256 earlyWithdrawPenaltyRate = veLon.earlyWithdrawPenaltyRate();

        // pretend 1 week has passed and the lock not expired
        vm.warp(block.timestamp + 1 weeks);

        // calculate the panalty
        uint256 expectedPanalty = ((DEFAULT_STAKE_AMOUNT.mul(veLon.earlyWithdrawPenaltyRate())).div(veLon.PENALTY_RATE_PRECISION()));
        uint256 expectedAmount = DEFAULT_STAKE_AMOUNT.sub(expectedPanalty);
        vm.expectEmit(true, true, true, true);
        emit Withdraw(user, false, tokenId, expectedAmount, expectedPanalty, block.timestamp);

        // check supply event
        uint256 supply = prevSupply - expectedAmount - expectedPanalty;
        vm.expectEmit(true, true, true, true);
        emit Supply(prevSupply, supply);

        vm.prank(user);
        veLon.withdrawEarly(tokenId);
        uint256 balanceChange = DEFAULT_STAKE_AMOUNT.mul(earlyWithdrawPenaltyRate).div(PENALTY_RATE_PRECISION);
        stakerLon.assertChange(int256(DEFAULT_STAKE_AMOUNT.sub(balanceChange)));
        lockedLon.assertChange(-int256(expectedAmount + expectedPanalty));
        // check whether token has burned after withdraw
        vm.expectRevert("ERC721: owner query for nonexistent token");
        veLon.ownerOf(tokenId);
    }

    function testWithdrawByOther() public {
        uint256 tokenId = _stakeAndValidate(user, DEFAULT_STAKE_AMOUNT, 2 weeks);
        uint256 prevSupply = DEFAULT_STAKE_AMOUNT;

        stakerLon = BalanceSnapshot.take(user, address(lon));
        lockedLon = BalanceSnapshot.take(address(veLon), address(lon));

        vm.prank(user);
        // check Approval event
        vm.expectEmit(true, true, true, true);
        emit Approval(user, other, tokenId);
        veLon.approve(address(other), tokenId);
        vm.prank(other);

        // check Withdraw event
        vm.warp(block.timestamp + 2 weeks);
        vm.expectEmit(true, true, true, true);
        emit Withdraw(other, true, tokenId, DEFAULT_STAKE_AMOUNT, 0, block.timestamp);

        // check supply event
        uint256 supply = prevSupply - DEFAULT_STAKE_AMOUNT;
        vm.expectEmit(true, true, true, true);
        emit Supply(prevSupply, supply);

        veLon.withdraw(tokenId);

        stakerLon.assertChange(int256(DEFAULT_STAKE_AMOUNT));
        lockedLon.assertChange(-int256(DEFAULT_STAKE_AMOUNT));
    }
}
