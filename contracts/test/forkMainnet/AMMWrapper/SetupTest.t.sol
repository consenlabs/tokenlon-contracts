// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "contracts-test/forkMainnet/AMMWrapper/Setup.t.sol";

contract TestAMMWrapperSetup is TestAMMWrapper {
    function testTokensAllowanceAmountWhenSetup() public {
        for (uint256 i = 0; i < tokens.length; i++) {
            assertEq(tokens[i].allowance(user, address(allowanceTarget)), type(uint256).max);
        }
    }

    function testAMMWrapperSetup() public {
        assertEq(ammWrapper.operator(), address(this));
        assertEq(uint256(ammWrapper.defaultFeeFactor()), uint256(DEFAULT_FEE_FACTOR));
        assertEq(ammWrapper.userProxy(), address(userProxy));
        assertEq(address(ammWrapper.spender()), address(spender));
        assertEq(ammWrapper.feeCollector(), feeCollector);
        assertEq(userProxy.ammWrapperAddr(), address(ammWrapper));
        assertEq(permanentStorage.ammWrapperAddr(), address(ammWrapper));
        assertTrue(spender.isAuthorized(address(ammWrapper)));
        assertTrue(permanentStorage.isRelayerValid(relayer));
    }
}
