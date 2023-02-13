// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IMulticall {
    event MulticallFailure(uint256 index, string reason);

    function multicall(bytes[] calldata data, bool revertOnFail) external returns (bool[] memory successes, bytes[] memory results);
}
