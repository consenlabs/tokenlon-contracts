// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.7.6;

import "contracts-test/AllowanceTarget/Setup.t.sol";
import "contracts-test/utils/BalanceSnapshot.sol";
import "contracts-test/mocks/MockERC20.sol";

contract TestAllowanceTargetExecuteCall is TestAllowanceTarget {
    // include Snapshot struct from BalanceSnapshot
    using BalanceSnapshot for BalanceSnapshot.Snapshot;

    function testCannotExecuteByNotSpender() public {
        vm.prank(bob);
        vm.expectRevert("AllowanceTarget: not the spender");

        bytes memory data;
        allowanceTarget.executeCall(payable(address(newSpender)), data);
    }

    function testExecuteCall() public {
        MockERC20 token = new MockERC20("Test", "TST", 18);
        BalanceSnapshot.Snapshot memory bobBalance = BalanceSnapshot.take(address(bob), address(token));

        // mint(address to, uint256 value)
        uint256 mintAmount = 1e18;
        allowanceTarget.executeCall(payable(address(token)), abi.encodeWithSelector(MockERC20.mint.selector, address(bob), mintAmount));
        bobBalance.assertChange(int256(mintAmount));
    }
}
