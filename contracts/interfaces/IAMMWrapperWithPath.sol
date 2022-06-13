pragma solidity >=0.7.0;
pragma abicoder v2;

import "./IAMMWrapper.sol";
import "../utils/AMMLibEIP712.sol";

interface IAMMWrapperWithPath is IAMMWrapper {
    function trade(
        AMMLibEIP712.Order calldata _order,
        bytes calldata _sig,
        bytes calldata _makerSpecificData,
        address[] calldata _path
    ) external payable returns (uint256);

    function tradeByRelayer(
        AMMLibEIP712.Order calldata _order,
        bytes calldata _sig,
        bytes calldata _makerSpecificData,
        address[] calldata _path,
        uint16 _feeFactor
    ) external payable returns (uint256);
}
