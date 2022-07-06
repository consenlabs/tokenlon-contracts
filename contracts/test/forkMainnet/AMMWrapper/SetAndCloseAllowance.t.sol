// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "contracts-test/forkMainnet/AMMWrapper/Setup.t.sol";

contract TestAMMWrapperSetAndCloseAllowance is TestAMMWrapper {
    function testCannotSetAndCloseAllowanceByNotOperator() public {
        address[] memory allowanceTokenList = new address[](1);
        allowanceTokenList[0] = address(usdt);

        vm.startPrank(user);
        vm.expectRevert("AMMWrapper: not the operator");
        ammWrapper.setAllowance(allowanceTokenList, address(this));
        vm.expectRevert("AMMWrapper: not the operator");
        ammWrapper.closeAllowance(allowanceTokenList, address(this));
        vm.stopPrank();
    }

    function testSetAndCloseAllowance() public {
        address[] memory allowanceTokenList = new address[](1);
        allowanceTokenList[0] = address(usdt);

        assertEq(usdt.allowance(address(ammWrapper), address(this)), uint256(0));

        ammWrapper.setAllowance(allowanceTokenList, address(this));
        assertEq(usdt.allowance(address(ammWrapper), address(this)), type(uint256).max);

        ammWrapper.closeAllowance(allowanceTokenList, address(this));
        assertEq(usdt.allowance(address(ammWrapper), address(this)), uint256(0));
    }
}
