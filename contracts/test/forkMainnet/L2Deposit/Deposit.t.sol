// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.7.6;
pragma abicoder v2;

import "contracts/interfaces/IL2Deposit.sol";
import "contracts-test/forkMainnet/L2Deposit/Setup.t.sol";
import "contracts-test/utils/BalanceSnapshot.sol";

contract TestL2DepositTopUp is TestL2Deposit {
    using BalanceSnapshot for BalanceSnapshot.Snapshot;

    uint256 arbMaxSubmissionCost = 1e18;
    uint256 arbMaxGas = 1e6;
    uint256 arbGasPriceBid = 1e6;

    function testCannotDepositIfExpired() public {
        // overwrite expiry
        DEFAULT_DEPOSIT.expiry = block.timestamp;
        // sig is not relevent in this case
        bytes memory sig = bytes("");
        bytes memory payload = abi.encodeWithSelector(L2Deposit.deposit.selector, IL2Deposit.DepositParams(DEFAULT_DEPOSIT, sig));

        vm.expectRevert("L2Deposit: Deposit is expired");
        userProxy.toL2Deposit(payload);
    }

    function testCannotDepositWithInvalidSig() public {
        // compose payload with signature from bob
        bytes memory sig = _signDeposit(bobPrivateKey, DEFAULT_DEPOSIT);
        bytes memory payload = abi.encodeWithSelector(L2Deposit.deposit.selector, IL2Deposit.DepositParams(DEFAULT_DEPOSIT, sig));

        vm.expectRevert("L2Deposit: Invalid deposit signature");
        userProxy.toL2Deposit(payload);
    }

    function testArbitrumDeposit() public {
        BalanceSnapshot.Snapshot memory userL1TokenBal = BalanceSnapshot.take(user, DEFAULT_DEPOSIT.l1TokenAddr);

        // overwrite deposit data with encoded arbitrum specific params
        DEFAULT_DEPOSIT.data = abi.encode(arbMaxSubmissionCost, arbMaxGas, arbGasPriceBid);

        // compose payload with signature
        bytes memory sig = _signDeposit(userPrivateKey, DEFAULT_DEPOSIT);
        bytes memory payload = abi.encodeWithSelector(L2Deposit.deposit.selector, IL2Deposit.DepositParams(DEFAULT_DEPOSIT, sig));
        uint256 callValue = arbMaxSubmissionCost + (arbMaxGas * arbGasPriceBid);

        // Response from bridge is unknown
        vm.expectEmit(true, true, true, false);
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
        userProxy.toL2Deposit{ value: callValue }(payload);

        userL1TokenBal.assertChange(-int256(DEFAULT_DEPOSIT.amount));
    }

    function testCannotReplayDeposit() public {
        // overwrite deposit data with encoded arbitrum specific params
        DEFAULT_DEPOSIT.data = abi.encode(arbMaxSubmissionCost, arbMaxGas, arbGasPriceBid);

        // compose payload with signature
        bytes memory sig = _signDeposit(userPrivateKey, DEFAULT_DEPOSIT);
        bytes memory payload = abi.encodeWithSelector(L2Deposit.deposit.selector, IL2Deposit.DepositParams(DEFAULT_DEPOSIT, sig));
        uint256 callValue = arbMaxSubmissionCost + (arbMaxGas * arbGasPriceBid);

        userProxy.toL2Deposit{ value: callValue }(payload);

        // should revert if payload relayed
        vm.expectRevert("PermanentStorage: L2 deposit seen before");
        userProxy.toL2Deposit{ value: callValue }(payload);
    }

    function testCannotDepositInvalidArbitrumToken() public {
        // overwrite l2TokenAddr with USDC address
        DEFAULT_DEPOSIT.l2TokenAddr = USDC_ADDRESS;

        // overwrite deposit data with encoded arbitrum specific params
        DEFAULT_DEPOSIT.data = abi.encode(arbMaxSubmissionCost, arbMaxGas, arbGasPriceBid);

        // compose payload with signature
        bytes memory sig = _signDeposit(userPrivateKey, DEFAULT_DEPOSIT);
        bytes memory payload = abi.encodeWithSelector(L2Deposit.deposit.selector, IL2Deposit.DepositParams(DEFAULT_DEPOSIT, sig));
        uint256 callValue = arbMaxSubmissionCost + (arbMaxGas * arbGasPriceBid);

        vm.expectRevert("L2Deposit: Incorrect L2 token address");
        userProxy.toL2Deposit{ value: callValue }(payload);
    }

    function testCannotDepositInvalidArbitrumETHAmount() public {
        // overwrite deposit data with encoded arbitrum specific params
        DEFAULT_DEPOSIT.data = abi.encode(arbMaxSubmissionCost, arbMaxGas, arbGasPriceBid);

        // compose payload with signature
        bytes memory sig = _signDeposit(userPrivateKey, DEFAULT_DEPOSIT);
        bytes memory payload = abi.encodeWithSelector(L2Deposit.deposit.selector, IL2Deposit.DepositParams(DEFAULT_DEPOSIT, sig));

        // conpose inbox revert data with defined error
        uint256 l2Callvalue = 0; // l2 call value 0 by default
        uint256 l1Cost = arbMaxSubmissionCost + l2Callvalue + (arbMaxGas * arbGasPriceBid);
        // Sig : error InsufficientValue(uint256 expected, uint256 actual)
        bytes memory revertData = abi.encodeWithSelector(0x7040b58c, l1Cost, 1);
        vm.expectRevert(revertData);
        userProxy.toL2Deposit{ value: 1 }(payload);
    }
}
