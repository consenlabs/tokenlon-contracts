// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { ILimitOrderSwap } from "contracts/interfaces/ILimitOrderSwap.sol";
import { Ownable } from "contracts/abstracts/Ownable.sol";
import { LimitOrderSwapTest } from "test/forkMainnet/LimitOrderSwap/Setup.t.sol";

contract ManagementTest is LimitOrderSwapTest {
    function testCannotSetFeeCollectorByNotOwner() public {
        address newFeeCollector = makeAddr("newFeeCollector");
        vm.prank(newFeeCollector);
        vm.expectRevert(Ownable.NotOwner.selector);
        limitOrderSwap.setFeeCollector(payable(newFeeCollector));
    }

    function testCannotSetFeeCollectorToZero() public {
        vm.prank(limitOrderOwner, limitOrderOwner);
        vm.expectRevert(ILimitOrderSwap.ZeroAddress.selector);
        limitOrderSwap.setFeeCollector(payable(address(0)));
    }

    function testSetFeeCollector() public {
        address newFeeCollector = makeAddr("newFeeCollector");
        vm.prank(limitOrderOwner, limitOrderOwner);
        limitOrderSwap.setFeeCollector(payable(newFeeCollector));
        emit SetFeeCollector(newFeeCollector);
        assertEq(limitOrderSwap.feeCollector(), newFeeCollector);
    }
}
