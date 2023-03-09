// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

struct GeneralOrder {
    address payable maker;
    address taker;
    address inputToken;
    bytes inputTokenPermit;
    address outputToken;
    bytes ourputTokenPermit;
    uint256 inputAmount;
    uint256 outputAmount;
    uint256 minOutputAmount;
    address payable recipient;
    uint256 expiry;
    uint256 salt;
}
