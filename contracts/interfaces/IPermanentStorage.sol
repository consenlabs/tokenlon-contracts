pragma solidity ^0.6.0;

interface IPermanentStorage {
    function wethAddr() external view returns (address);
    function getCurvePoolInfo(address _makerAddr, address _takerAssetAddr, address _makerAssetAddr) external view returns (int128 takerAssetIndex, int128 makerAssetIndex, uint16 swapMethod, bool supportGetDx);
    function setCurvePoolInfo(address _makerAddr, address[] calldata _underlyingCoins, address[] calldata _coins, bool _supportGetDx) external;
    function isTransactionSeen(bytes32 _transactionHash) external view returns (bool);  // Kept for backward compatability. Should be removed from AMM 5.2.1 upward
    function isAMMTransactionSeen(bytes32 _transactionHash) external view returns (bool);
    function isRFQTransactionSeen(bytes32 _transactionHash) external view returns (bool);
    function isRelayerValid(address _relayer) external view returns (bool);
    function setTransactionSeen(bytes32 _transactionHash) external;  // Kept for backward compatability. Should be removed from AMM 5.2.1 upward
    function setAMMTransactionSeen(bytes32 _transactionHash) external;
    function setRFQTransactionSeen(bytes32 _transactionHash) external;
    function setRelayersValid(address[] memory _relayers, bool[] memory _isValids) external;
}