// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.7.6;

import "contracts-test/AllowanceTarget/Setup.t.sol";
import "contracts-test/utils/BalanceSnapshot.sol";

contract TestAllowanceTargetTeardown is TestAllowanceTarget {
    // include Snapshot struct from BalanceSnapshot
    using BalanceSnapshot for BalanceSnapshot.Snapshot;

    function testCannotTeardownByNotSpender() public {
        vm.prank(bob);
        vm.expectRevert("AllowanceTarget: not the spender");
        allowanceTarget.teardown();
    }

    // normal case
    function testTeardown() public {
        BalanceSnapshot.Snapshot memory beneficiary = BalanceSnapshot.take(address(this), ETH_ADDRESS);
        uint256 heritage = 10 ether;
        deal(address(allowanceTarget), heritage);
        allowanceTarget.teardown();
        beneficiary.assertChange(int256(heritage));
    }
}
