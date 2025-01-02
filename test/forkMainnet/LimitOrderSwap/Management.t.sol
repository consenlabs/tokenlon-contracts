// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { ILimitOrderSwap } from "contracts/interfaces/ILimitOrderSwap.sol";
import { Ownable } from "contracts/abstracts/Ownable.sol";
import { LimitOrderSwapTest } from "test/forkMainnet/LimitOrderSwap/Setup.t.sol";

contract ManagementTest is LimitOrderSwapTest {
    function testCannotSetFeeCollectorByNotOwner() public {
        address newFeeCollector = makeAddr("newFeeCollector");

        vm.startPrank(newFeeCollector);
        vm.expectRevert(Ownable.NotOwner.selector);
        limitOrderSwap.setFeeCollector(payable(newFeeCollector));
        vm.stopPrank();
    }

    function testCannotSetFeeCollectorToZero() public {
        vm.startPrank(limitOrderOwner);
        vm.expectRevert(ILimitOrderSwap.ZeroAddress.selector);
        limitOrderSwap.setFeeCollector(payable(address(0)));
        vm.stopPrank();
    }

    function testSetFeeCollector() public {
        address newFeeCollector = makeAddr("newFeeCollector");

        vm.expectEmit(false, false, false, true);
        emit SetFeeCollector(newFeeCollector);

        vm.startPrank(limitOrderOwner);
        limitOrderSwap.setFeeCollector(payable(newFeeCollector));
        vm.stopPrank();
    }
}
