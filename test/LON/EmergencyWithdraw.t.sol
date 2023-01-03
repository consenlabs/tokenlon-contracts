// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "test/LON/Setup.t.sol";
import "test/mocks/MockERC20.sol";

contract TestLONEmergencyWithdraw is TestLON {
    using BalanceSnapshot for BalanceSnapshot.Snapshot;

    function testEmergencyWithdraw() public {
        uint256 withdrawAmount = 1e18;

        MockERC20 dai = new MockERC20("DAI", "DAI", uint8(18));
        dai.mint(address(lon), withdrawAmount);
        BalanceSnapshot.Snapshot memory lonDai = BalanceSnapshot.take(address(lon), address(dai));
        BalanceSnapshot.Snapshot memory emergencyRecipientDai = BalanceSnapshot.take(emergencyRecipient, address(dai));
        vm.prank(user);
        lon.emergencyWithdraw(dai);
        lonDai.assertChange(-int256(withdrawAmount));
        emergencyRecipientDai.assertChange(int256(withdrawAmount));
    }
}
