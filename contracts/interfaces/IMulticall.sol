pragma solidity >=0.7.0;
pragma abicoder v2;

interface IMulticall {
    event MulticallFailure(uint256 index, string reason);

    function multicall(bytes[] calldata data, bool revertOnFail) external returns (bool[] memory successes, bytes[] memory results);
}
