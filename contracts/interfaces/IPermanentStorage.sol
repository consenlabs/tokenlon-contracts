// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;

interface IPermanentStorage {
    // Operator events
    event OperatorNominated(address indexed newOperator);
    event OperatorChanged(address indexed oldOperator, address indexed newOperator);
    event SetPermission(bytes32 storageId, address role, bool enabled);
    event UpgradeAMMWrapper(address newAMMWrapper);
    event UpgradePMM(address newPMM);
    event UpgradeRFQ(address newRFQ);
    event UpgradeRFQv2(address newRFQv2);
    event UpgradeLimitOrder(address newLimitOrder);
    event UpgradeWETH(address newWETH);
    event SetCurvePoolInfo(address makerAddr, address[] underlyingCoins, address[] coins, bool supportGetD);
    event SetRelayerValid(address relayer, bool valid);

    function hasPermission(bytes32 _storageId, address _role) external view returns (bool);

    function ammWrapperAddr() external view returns (address);

    function pmmAddr() external view returns (address);

    function rfqAddr() external view returns (address);

    function rfqv2Addr() external view returns (address);

    function limitOrderAddr() external view returns (address);

    function wethAddr() external view returns (address);

    function getCurvePoolInfo(
        address _makerAddr,
        address _takerAssetAddr,
        address _makerAssetAddr
    )
        external
        view
        returns (
            int128 takerAssetIndex,
            int128 makerAssetIndex,
            uint16 swapMethod,
            bool supportGetDx
        );

    function setCurvePoolInfo(
        address _makerAddr,
        address[] calldata _underlyingCoins,
        address[] calldata _coins,
        bool _supportGetDx
    ) external;

    function isAMMTransactionSeen(bytes32 _transactionHash) external view returns (bool);

    function isRFQTransactionSeen(bytes32 _transactionHash) external view returns (bool);

    function isRFQOfferFilled(bytes32 _offerHash) external view returns (bool);

    function isLimitOrderTransactionSeen(bytes32 _transactionHash) external view returns (bool);

    function isLimitOrderAllowFillSeen(bytes32 _allowFillHash) external view returns (bool);

    function isRelayerValid(address _relayer) external view returns (bool);

    function setAMMTransactionSeen(bytes32 _transactionHash) external;

    function setRFQTransactionSeen(bytes32 _transactionHash) external;

    function setRFQOfferFilled(bytes32 _offerHash) external;

    function setLimitOrderTransactionSeen(bytes32 _transactionHash) external;

    function setLimitOrderAllowFillSeen(bytes32 _allowFillHash) external;

    function setRelayersValid(address[] memory _relayers, bool[] memory _isValids) external;
}
