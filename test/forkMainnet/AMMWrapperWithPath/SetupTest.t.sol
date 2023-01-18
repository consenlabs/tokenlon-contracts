// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import "test/forkMainnet/AMMWrapperWithPath/Setup.t.sol";

contract TestAMMWrapperWithPathSetup is TestAMMWrapperWithPath {
    function testTokensAllowanceAmountWhenSetup() public {
        for (uint256 i = 0; i < tokens.length; i++) {
            assertEq(tokens[i].allowance(user, address(allowanceTarget)), type(uint256).max);
        }
    }

    function testAMMWrapperWithPathSetup() public {
        // Check fork mainnet addresses are not zero addresses
        assertTrue(uint160(UNISWAP_V2_ADDRESS) != 0);
        assertTrue(uint160(UNISWAP_V3_ADDRESS) != 0);
        assertTrue(uint160(UNISWAP_V3_QUOTER_ADDRESS) != 0);
        assertTrue(uint160(SUSHISWAP_ADDRESS) != 0);
        assertTrue(uint160(BALANCER_V2_ADDRESS) != 0);
        assertTrue(uint160(CURVE_USDT_POOL_ADDRESS) != 0);
        assertTrue(uint160(CURVE_TRICRYPTO2_POOL_ADDRESS) != 0);
        assertTrue(uint160(WETH_ADDRESS) != 0);
        assertTrue(uint160(DAI_ADDRESS) != 0);
        assertTrue(uint160(USDT_ADDRESS) != 0);
        assertTrue(uint160(USDC_ADDRESS) != 0);
        assertTrue(uint160(WBTC_ADDRESS) != 0);

        assertEq(ammWrapperWithPath.owner(), owner);
        assertEq(uint256(ammWrapperWithPath.defaultFeeFactor()), uint256(DEFAULT_FEE_FACTOR));
        assertEq(ammWrapperWithPath.userProxy(), address(userProxy));
        assertEq(address(ammWrapperWithPath.spender()), address(spender));
        assertEq(ammWrapperWithPath.feeCollector(), feeCollector);
        assertEq(userProxy.ammWrapperAddr(), address(ammWrapperWithPath));
        assertEq(permanentStorage.ammWrapperAddr(), address(ammWrapperWithPath));
        assertTrue(spender.isAuthorized(address(ammWrapperWithPath)));
        assertTrue(permanentStorage.isRelayerValid(relayer));
    }
}
