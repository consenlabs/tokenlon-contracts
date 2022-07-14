// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "contracts-test/forkMainnet/AMMWrapper/Setup.t.sol";

contract TestAMMWrapperAllowance is TestAMMWrapper {
    function testCannotSetByNotOperator() public {
        address[] memory allowanceTokenList = new address[](1);
        allowanceTokenList[0] = address(usdt);

        vm.expectRevert("AMMWrapper: not the operator");
        vm.prank(user);
        ammWrapper.setAllowance(allowanceTokenList, address(this));
    }

    function testCannotCloseByNotOperator() public {
        address[] memory allowanceTokenList = new address[](1);
        allowanceTokenList[0] = address(usdt);

        vm.expectRevert("AMMWrapper: not the operator");
        vm.prank(user);
        ammWrapper.closeAllowance(allowanceTokenList, address(this));
    }

    function testAllowance() public {
        address[] memory allowanceTokenList = new address[](1);
        allowanceTokenList[0] = address(usdt);

        assertEq(usdt.allowance(address(ammWrapper), address(this)), uint256(0));

        ammWrapper.setAllowance(allowanceTokenList, address(this));
        assertEq(usdt.allowance(address(ammWrapper), address(this)), type(uint256).max);

        ammWrapper.closeAllowance(allowanceTokenList, address(this));
        assertEq(usdt.allowance(address(ammWrapper), address(this)), uint256(0));
    }
}
