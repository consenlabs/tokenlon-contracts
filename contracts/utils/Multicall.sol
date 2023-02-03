// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import "../interfaces/IMulticall.sol";

// Modified from https://github.com/Uniswap/uniswap-v3-periphery/blob/v1.1.1/contracts/base/Multicall.sol
abstract contract Multicall is IMulticall {
    function multicall(bytes[] calldata data, bool revertOnFail) external override returns (bool[] memory successes, bytes[] memory results) {
        successes = new bool[](data.length);
        results = new bytes[](data.length);
        for (uint256 i = 0; i < data.length; ++i) {
            (bool success, bytes memory result) = address(this).delegatecall(data[i]);
            successes[i] = success;
            results[i] = result;

            if (!success) {
                // Get failed reason
                string memory revertReason;
                if (result.length < 68) {
                    revertReason = "Delegatecall failed";
                } else {
                    assembly {
                        result := add(result, 0x04)
                    }
                    revertReason = abi.decode(result, (string));
                }

                if (revertOnFail) {
                    revert(revertReason);
                }
                emit MulticallFailure(i, revertReason);
            }
        }
    }
}
