// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import "test/LONStaking/Setup.t.sol";
import "test/mocks/MockERC20.sol";

contract TestLONStakingRecoverERC20 is TestLONStaking {
    using BalanceSnapshot for BalanceSnapshot.Snapshot;

    function testCannotRecoverByNotOwner() public {
        uint256 recoverAmount = 1e18;

        vm.expectRevert("not owner");
        vm.prank(user);
        lonStaking.recoverERC20(address(lon), recoverAmount);
    }

    function testCannotRecoverWithLONToken() public {
        uint256 recoverAmount = 1e18;

        vm.expectRevert("cannot withdraw lon token");
        lonStaking.recoverERC20(address(lon), recoverAmount);
    }

    function testRecoverERC20() public {
        uint256 recoverAmount = 1e18;

        MockERC20 dai = new MockERC20("DAI", "DAI", 18);
        dai.mint(address(lonStaking), recoverAmount);
        BalanceSnapshot.Snapshot memory lonStakingDai = BalanceSnapshot.take(address(lonStaking), address(dai));
        BalanceSnapshot.Snapshot memory receiverDai = BalanceSnapshot.take(address(this), address(dai));
        lonStaking.recoverERC20(address(dai), recoverAmount);
        lonStakingDai.assertChange(-int256(recoverAmount));
        receiverDai.assertChange(int256(recoverAmount));
    }
}
