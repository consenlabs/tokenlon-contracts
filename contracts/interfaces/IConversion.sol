// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;

interface IConversion {
    function enableConversion(address _dstToken) external;

    function disableConversion() external;

    function convert(bytes calldata _encodeData) external returns (uint256);
}
