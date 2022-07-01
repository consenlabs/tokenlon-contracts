// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "contracts-test/LON/Setup.t.sol";
import "contracts-test/mocks/MockERC20.sol";

contract TestLONEmergencyWithdraw is TestLON {
    using BalanceSnapshot for BalanceSnapshot.Snapshot;

    function testEmergencyWithdraw() public {
        MockERC20 dai = new MockERC20("DAI", "DAI", 18);
        dai.mint(address(lon), 1e18);
        BalanceSnapshot.Snapshot memory lonDai = BalanceSnapshot.take(address(lon), address(dai));
        BalanceSnapshot.Snapshot memory emergencyRecipientDai = BalanceSnapshot.take(emergencyRecipient, address(dai));
        vm.prank(user);
        lon.emergencyWithdraw(dai);
        lonDai.assertChange(-int256(1e18));
        emergencyRecipientDai.assertChange(int256(1e18));
    }
}
