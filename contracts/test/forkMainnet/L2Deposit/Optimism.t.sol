// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.7.6;
pragma abicoder v2;

import "contracts/interfaces/IL2Deposit.sol";
import "contracts/utils/L2DepositLibEIP712.sol";
import "contracts-test/forkMainnet/L2Deposit/Setup.t.sol";
import "contracts-test/utils/BalanceSnapshot.sol";

contract TestL2DepositOptimism is TestL2Deposit {
    using BalanceSnapshot for BalanceSnapshot.Snapshot;

    uint32 optL2Gas = 1e6;

    function testOptimismDeposit() public {
        BalanceSnapshot.Snapshot memory userL1TokenBal = BalanceSnapshot.take(user, DEFAULT_DEPOSIT.l1TokenAddr);

        // overwrite l2Identifier
        DEFAULT_DEPOSIT.l2Identifier = L2DepositLibEIP712.L2Identifier.Optimism;

        // overwrite l2TokenAddr with LON address on L1
        DEFAULT_DEPOSIT.l2TokenAddr = LON_ADDRESS;

        // overwrite deposit data with encoded optimism specific params
        DEFAULT_DEPOSIT.data = abi.encode(optL2Gas);

        // compose payload with signature
        bytes memory sig = _signDeposit(userPrivateKey, DEFAULT_DEPOSIT);
        bytes memory payload = abi.encodeWithSelector(L2Deposit.deposit.selector, IL2Deposit.DepositParams(DEFAULT_DEPOSIT, sig));

        vm.expectEmit(true, true, true, true);
        emit Deposited(
            DEFAULT_DEPOSIT.l2Identifier,
            DEFAULT_DEPOSIT.l1TokenAddr,
            DEFAULT_DEPOSIT.l2TokenAddr,
            DEFAULT_DEPOSIT.sender,
            DEFAULT_DEPOSIT.recipient,
            DEFAULT_DEPOSIT.amount,
            DEFAULT_DEPOSIT.data,
            bytes("")
        );
        userProxy.toL2Deposit(payload);

        userL1TokenBal.assertChange(-int256(DEFAULT_DEPOSIT.amount));
    }
}
