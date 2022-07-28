// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "contracts-test/forkMainnet/AMMWrapper/Setup.t.sol";

contract TestAMMWrapperSetFeeCollector is TestAMMWrapper {
    function testCannotSetFeeCollectorByNotOperator() public {
        vm.prank(user);
        vm.expectRevert("AMMWrapper: not the operator");
        ammWrapper.setFeeCollector(user);
    }

    function testSetFeeCollector() public {
        vm.expectEmit(true, true, true, true);
        emit SetFeeCollector(user);

        ammWrapper.setFeeCollector(user);
        assertEq(ammWrapper.feeCollector(), user);
    }
}
