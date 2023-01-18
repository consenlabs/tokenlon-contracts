// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.7.6;

import "test/forkMainnet/L2Deposit/Setup.t.sol";

contract TestL2DepositSetup is TestL2Deposit {
    function testSetupL2Deposit() public {
        // Check fork mainnet addresses are not zero addresses
        assertTrue(uint160(ARBITRUM_L1_GATEWAY_ROUTER_ADDR) != 0);
        assertTrue(uint160(ARBITRUM_L1_BRIDGE_ADDR) != 0);
        assertTrue(uint160(OPTIMISM_L1_STANDARD_BRIDGE_ADDR) != 0);
        assertTrue(uint160(WETH_ADDRESS) != 0);
        assertTrue(uint160(DAI_ADDRESS) != 0);
        assertTrue(uint160(USDT_ADDRESS) != 0);
        assertTrue(uint160(USDC_ADDRESS) != 0);
        assertTrue(uint160(LON_ADDRESS) != 0);

        assertEq(l2Deposit.owner(), owner);
        assertEq(l2Deposit.userProxy(), address(userProxy));
        assertEq(address(l2Deposit.spender()), address(spender));
        assertEq(address(l2Deposit.permStorage()), address(permanentStorage));
        assertEq(address(l2Deposit.arbitrumL1GatewayRouter()), address(arbitrumL1GatewayRouter));
        assertEq(address(l2Deposit.optimismL1StandardBridge()), address(optimismL1StandardBridge));
    }
}
