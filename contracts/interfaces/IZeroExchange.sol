pragma solidity >=0.7.0;

interface IZeroExchange {
    function executeTransaction(
        uint256 salt,
        address signerAddress,
        bytes calldata data,
        bytes calldata signature
    ) external;
}
