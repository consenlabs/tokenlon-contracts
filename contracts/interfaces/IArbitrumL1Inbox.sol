// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;

import "./IArbitrumL1Bridge.sol";

interface IArbitrumL1Inbox {
    event InboxMessageDelivered(uint256 indexed messageNum, bytes data);

    function bridge() external view returns (address);

    function createRetryableTicket(
        address destAddr,
        uint256 l2CallValue,
        uint256 maxSubmissionCost,
        address excessFeeRefundAddress,
        address callValueRefundAddress,
        uint256 maxGas,
        uint256 gasPriceBid,
        bytes calldata data
    ) external payable returns (uint256);
}
