// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.7.6;
pragma abicoder v2;

import "contracts/interfaces/IL2Deposit.sol";
import "contracts-test/forkMainnet/L2Deposit/Setup.t.sol";
import "contracts-test/utils/BalanceSnapshot.sol";

contract TestArbitrumL2Refund is TestL2Deposit {
    using BalanceSnapshot for BalanceSnapshot.Snapshot;

    uint256 arbMaxSubmissionCost = 1e18;
    uint256 arbMaxGas = 1e6;
    uint256 arbGasPriceBid = 1e6;

    event CollectArbitrumL2Refund(
        address indexed arbitrumL2RefundCollector,
        uint256 indexed seqNum,
        uint256 indexed amount,
        uint256 maxSubmissionCost,
        uint256 maxGas,
        uint256 gasPriceBid
    );

    function testCannotArbitrumL2RefundWithZeroCallValue() public {
        uint256 l2CallValue = 1234;
        uint256 l1Cost = arbMaxSubmissionCost + l2CallValue + (arbMaxGas * arbGasPriceBid);

        // conpose inbox revert data with defined error
        // Sig : error InsufficientValue(uint256 expected, uint256 actual)
        bytes memory revertData = abi.encodeWithSelector(0x7040b58c, l1Cost, 0);
        vm.expectRevert(revertData);
        l2Deposit.collectArbitrumL2Refund(l2CallValue, arbMaxSubmissionCost, arbMaxGas, arbGasPriceBid);
    }

    function testArbitrumL2Refund() public {
        uint256 l2CallValue = 1234;
        uint256 l1Cost = arbMaxSubmissionCost + l2CallValue + (arbMaxGas * arbGasPriceBid);
        // Response from bridge is unknown
        uint256 seqNum = 0;
        vm.expectEmit(true, false, true, true);
        emit CollectArbitrumL2Refund(arbitrumL2RefundCollector, seqNum, l2CallValue, arbMaxSubmissionCost, arbMaxGas, arbGasPriceBid);

        l2Deposit.collectArbitrumL2Refund{ value: l1Cost }(l2CallValue, arbMaxSubmissionCost, arbMaxGas, arbGasPriceBid);
    }
}
