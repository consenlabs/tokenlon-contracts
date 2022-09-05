// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "contracts-test/forkMainnet/AMMWrapper/Setup.t.sol";

contract TestAMMWrapperSetFeeCollector is TestAMMWrapper {
    function testCannotSetFeeCollectorByNotOwner() public {
        vm.prank(user);
        vm.expectRevert("not owner");
        ammWrapper.setFeeCollector(user);
    }

    function testSetFeeCollector() public {
        vm.expectEmit(true, true, true, true);
        emit SetFeeCollector(user);

        ammWrapper.setFeeCollector(user);
        assertEq(ammWrapper.feeCollector(), user);
    }
}
