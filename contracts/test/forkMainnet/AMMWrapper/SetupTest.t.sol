// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "contracts-test/forkMainnet/AMMWrapper/Setup.t.sol";

contract TestAMMWrapperSetup is TestAMMWrapper {
    function testTokensTotalSupplyWhenSetup() public {
        for (uint256 i = 0; i < tokens.length; i++) {
            assertGt(tokens[i].totalSupply(), uint256(0));
        }
    }

    function testTokensAllowanceAmountWhenSetup() public {
        for (uint256 i = 0; i < tokens.length; i++) {
            assertEq(tokens[i].allowance(user, address(allowanceTarget)), type(uint256).max);
        }
    }

    function testAMMWrapperSetup() public {
        assertEq(ammWrapper.operator(), address(this));
        assertEq(ammWrapper.subsidyFactor(), SUBSIDY_FACTOR);
        assertEq(ammWrapper.userProxy(), address(userProxy));
        assertEq(address(ammWrapper.spender()), address(spender));
        assertEq(userProxy.ammWrapperAddr(), address(ammWrapper));
        assertEq(permanentStorage.ammWrapperAddr(), address(ammWrapper));
        assertTrue(spender.isAuthorized(address(ammWrapper)));
        assertTrue(permanentStorage.isRelayerValid(relayer));
    }
}
