// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "contracts-test/forkMainnet/AMMWrapper/Setup.t.sol";

contract TestAMMWrapperDepositETH is TestAMMWrapper {
    function testCannotDepositByNotOwner() public {
        vm.expectRevert("not owner");
        vm.prank(user);
        ammWrapper.depositETH();
    }

    function testDepositETH() public {
        deal(address(ammWrapper), 1 ether);
        assertEq(address(ammWrapper).balance, 1 ether);
        vm.prank(owner, owner);
        ammWrapper.depositETH();
        assertEq(address(ammWrapper).balance, uint256(0));
        assertEq(weth.balanceOf(address(ammWrapper)), 1 ether);
    }
}
