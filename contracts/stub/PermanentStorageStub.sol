// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;

import "../interfaces/IPermanentStorage.sol";
import "../utils/PSStorage.sol";

contract PermanentStorageStub is IPermanentStorage {
    // Supported Curve pools
    address public constant CURVE_COMPOUND_POOL = 0xA2B47E3D5c44877cca798226B7B8118F9BFb7A56;
    address public constant CURVE_USDT_POOL = 0x52EA46506B9CC5Ef470C5bf89f17Dc28bB35D85C;
    address public constant CURVE_Y_POOL = 0x45F783CCE6B7FF23B2ab2D70e416cdb7D6055f51;
    address public constant CURVE_3_POOL = 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7;
    address public constant CURVE_sUSD_POOL = 0xA5407eAE9Ba41422680e2e00537571bcC53efBfD;
    address public constant CURVE_BUSD_POOL = 0x79a8C46DeA5aDa233ABaFFD40F3A0A2B1e5A4F27;
    address public constant CURVE_renBTC_POOL = 0x93054188d876f558f4a66B2EF1d97d16eDf0895B;
    address public constant CURVE_sBTC_POOL = 0x7fC77b5c7614E1533320Ea6DDc2Eb61fa00A9714;
    address public constant CURVE_hBTC_POOL = 0x4CA9b3063Ec5866A4B82E437059D2C43d1be596F;
    address public constant CURVE_sETH_POOL = 0xc5424B857f758E906013F3555Dad202e4bdB4567;
    address public constant CURVE_tricrypto2_POOL = 0x80466c64868E1ab14a1Ddf27A676C3fcBE638Fe5;

    // Curve coins
    address private constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant cDAI = 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643;
    address private constant cUSDC = 0x39AA39c021dfbaE8faC545936693aC917d5E7563;
    address private constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address private constant TUSD = 0x0000000000085d4780B73119b644AE5ecd22b376;
    address private constant Y_POOL_yDAI = 0x16de59092dAE5CcF4A1E6439D611fd0653f0Bd01;
    address private constant Y_POOL_yUSDC = 0xd6aD7a6750A7593E092a9B218d66C0A814a3436e;
    address private constant Y_POOL_yUSDT = 0x83f798e925BcD4017Eb265844FDDAbb448f1707D;
    address private constant Y_POOL_yTUSD = 0x73a052500105205d34Daf004eAb301916DA8190f;
    address private constant sUSD = 0x57Ab1ec28D129707052df4dF418D58a2D46d5f51;
    address private constant BUSD = 0x4Fabb145d64652a948d72533023f6E7A623C7C53;
    address private constant BUSD_POOL_yDAI = 0xC2cB1040220768554cf699b0d863A3cd4324ce32;
    address private constant BUSD_POOL_yUSDC = 0x26EA744E5B887E5205727f55dFBE8685e3b21951;
    address private constant BUSD_POOL_yUSDT = 0xE6354ed5bC4b393a5Aad09f21c46E101e692d447;
    address private constant BUSD_POOL_yBUSD = 0x04bC0Ab673d88aE9dbC9DA2380cB6B79C4BCa9aE;
    address private constant renBTC = 0xEB4C2781e4ebA804CE9a9803C67d0893436bB27D;
    address private constant wBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address private constant sBTC = 0xfE18be6b3Bd88A2D2A7f928d00292E7a9963CfC6;
    address private constant hBTC = 0x0316EB71485b0Ab14103307bf65a021042c6d380;
    address private constant sETH = 0x5e74C9036fb86BD7eCdcb084a0673EFc32eA31cb;
    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    constructor() {
        // register WETH address
        PSStorage.getStorage().wethAddr = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        // register Compound pool
        // underlying_coins, exchange_underlying
        AMMWrapperStorage.getStorage().curveTokenIndexes[CURVE_COMPOUND_POOL][DAI] = 1;
        AMMWrapperStorage.getStorage().curveTokenIndexes[CURVE_COMPOUND_POOL][USDC] = 2;
        // coins, exchange
        AMMWrapperStorage.getStorage().curveWrappedTokenIndexes[CURVE_COMPOUND_POOL][cDAI] = 1;
        AMMWrapperStorage.getStorage().curveWrappedTokenIndexes[CURVE_COMPOUND_POOL][cUSDC] = 2;
        AMMWrapperStorage.getStorage().curveSupportGetDx[CURVE_COMPOUND_POOL] = true; // support get_dx or get_dx_underlying for quoting

        // register USDT pool
        // underlying_coins, exchange_underlying
        AMMWrapperStorage.getStorage().curveTokenIndexes[CURVE_USDT_POOL][DAI] = 1;
        AMMWrapperStorage.getStorage().curveTokenIndexes[CURVE_USDT_POOL][USDC] = 2;
        AMMWrapperStorage.getStorage().curveTokenIndexes[CURVE_USDT_POOL][USDT] = 3;
        // coins, exchange
        AMMWrapperStorage.getStorage().curveWrappedTokenIndexes[CURVE_USDT_POOL][cDAI] = 1;
        AMMWrapperStorage.getStorage().curveWrappedTokenIndexes[CURVE_USDT_POOL][cUSDC] = 2;
        AMMWrapperStorage.getStorage().curveWrappedTokenIndexes[CURVE_USDT_POOL][USDT] = 3;
        AMMWrapperStorage.getStorage().curveSupportGetDx[CURVE_USDT_POOL] = true;

        // register Y pool
        // underlying_coins, exchange_underlying
        AMMWrapperStorage.getStorage().curveTokenIndexes[CURVE_Y_POOL][DAI] = 1;
        AMMWrapperStorage.getStorage().curveTokenIndexes[CURVE_Y_POOL][USDC] = 2;
        AMMWrapperStorage.getStorage().curveTokenIndexes[CURVE_Y_POOL][USDT] = 3;
        AMMWrapperStorage.getStorage().curveTokenIndexes[CURVE_Y_POOL][TUSD] = 4;
        // coins, exchange
        AMMWrapperStorage.getStorage().curveWrappedTokenIndexes[CURVE_Y_POOL][Y_POOL_yDAI] = 1;
        AMMWrapperStorage.getStorage().curveWrappedTokenIndexes[CURVE_Y_POOL][Y_POOL_yUSDC] = 2;
        AMMWrapperStorage.getStorage().curveWrappedTokenIndexes[CURVE_Y_POOL][Y_POOL_yUSDT] = 3;
        AMMWrapperStorage.getStorage().curveWrappedTokenIndexes[CURVE_Y_POOL][Y_POOL_yTUSD] = 4;
        AMMWrapperStorage.getStorage().curveSupportGetDx[CURVE_Y_POOL] = true;

        // register 3 pool
        // coins, exchange
        AMMWrapperStorage.getStorage().curveWrappedTokenIndexes[CURVE_3_POOL][DAI] = 1;
        AMMWrapperStorage.getStorage().curveWrappedTokenIndexes[CURVE_3_POOL][USDC] = 2;
        AMMWrapperStorage.getStorage().curveWrappedTokenIndexes[CURVE_3_POOL][USDT] = 3;
        AMMWrapperStorage.getStorage().curveSupportGetDx[CURVE_3_POOL] = false; // only support get_dy and get_dy_underlying for exactly the same functionality

        // register sUSD pool
        // coins, exchange
        AMMWrapperStorage.getStorage().curveWrappedTokenIndexes[CURVE_sUSD_POOL][DAI] = 1;
        AMMWrapperStorage.getStorage().curveWrappedTokenIndexes[CURVE_sUSD_POOL][USDC] = 2;
        AMMWrapperStorage.getStorage().curveWrappedTokenIndexes[CURVE_sUSD_POOL][USDT] = 3;
        AMMWrapperStorage.getStorage().curveWrappedTokenIndexes[CURVE_sUSD_POOL][sUSD] = 4;
        AMMWrapperStorage.getStorage().curveSupportGetDx[CURVE_sUSD_POOL] = false;

        // register BUSD pool
        // underlying_coins, exchange_underlying
        AMMWrapperStorage.getStorage().curveTokenIndexes[CURVE_BUSD_POOL][DAI] = 1;
        AMMWrapperStorage.getStorage().curveTokenIndexes[CURVE_BUSD_POOL][USDC] = 2;
        AMMWrapperStorage.getStorage().curveTokenIndexes[CURVE_BUSD_POOL][USDT] = 3;
        AMMWrapperStorage.getStorage().curveTokenIndexes[CURVE_BUSD_POOL][BUSD] = 4;
        // coins, exchange
        AMMWrapperStorage.getStorage().curveWrappedTokenIndexes[CURVE_BUSD_POOL][BUSD_POOL_yDAI] = 1;
        AMMWrapperStorage.getStorage().curveWrappedTokenIndexes[CURVE_BUSD_POOL][BUSD_POOL_yUSDC] = 2;
        AMMWrapperStorage.getStorage().curveWrappedTokenIndexes[CURVE_BUSD_POOL][BUSD_POOL_yUSDT] = 3;
        AMMWrapperStorage.getStorage().curveWrappedTokenIndexes[CURVE_BUSD_POOL][BUSD_POOL_yBUSD] = 4;
        AMMWrapperStorage.getStorage().curveSupportGetDx[CURVE_BUSD_POOL] = true;

        // register renBTC pool
        // coins, exchange
        AMMWrapperStorage.getStorage().curveWrappedTokenIndexes[CURVE_renBTC_POOL][renBTC] = 1; // renBTC
        AMMWrapperStorage.getStorage().curveWrappedTokenIndexes[CURVE_renBTC_POOL][wBTC] = 2; // wBTC
        AMMWrapperStorage.getStorage().curveSupportGetDx[CURVE_renBTC_POOL] = false;

        // register sBTC pool
        // coins, exchange
        AMMWrapperStorage.getStorage().curveWrappedTokenIndexes[CURVE_sBTC_POOL][renBTC] = 1; // renBTC
        AMMWrapperStorage.getStorage().curveWrappedTokenIndexes[CURVE_sBTC_POOL][wBTC] = 2; // wBTC
        AMMWrapperStorage.getStorage().curveWrappedTokenIndexes[CURVE_sBTC_POOL][sBTC] = 3; // sBTC
        AMMWrapperStorage.getStorage().curveSupportGetDx[CURVE_sBTC_POOL] = false;

        // register hBTC pool
        // coins, exchange
        AMMWrapperStorage.getStorage().curveWrappedTokenIndexes[CURVE_hBTC_POOL][hBTC] = 1; // hBTC
        AMMWrapperStorage.getStorage().curveWrappedTokenIndexes[CURVE_hBTC_POOL][wBTC] = 2; // wBTC
        AMMWrapperStorage.getStorage().curveSupportGetDx[CURVE_hBTC_POOL] = false;

        // register sETH pool
        // coins, exchange
        AMMWrapperStorage.getStorage().curveWrappedTokenIndexes[CURVE_sETH_POOL][ETH] = 1; // ETH
        AMMWrapperStorage.getStorage().curveWrappedTokenIndexes[CURVE_sETH_POOL][sETH] = 2; // sETH
        AMMWrapperStorage.getStorage().curveSupportGetDx[CURVE_sETH_POOL] = false;

        AMMWrapperStorage.getStorage().curveWrappedTokenIndexes[CURVE_tricrypto2_POOL][USDT] = 1; // USDT
        AMMWrapperStorage.getStorage().curveWrappedTokenIndexes[CURVE_tricrypto2_POOL][wBTC] = 2; // wBTC
        AMMWrapperStorage.getStorage().curveWrappedTokenIndexes[CURVE_tricrypto2_POOL][WETH] = 3; // WETH
        AMMWrapperStorage.getStorage().curveSupportGetDx[CURVE_tricrypto2_POOL] = false;
    }

    /************************************************************
     *                     Getter functions                      *
     *************************************************************/
    function ammWrapperAddr() public view returns (address) {
        return PSStorage.getStorage().ammWrapperAddr;
    }

    function pmmAddr() public view returns (address) {
        return PSStorage.getStorage().pmmAddr;
    }

    function rfqAddr() public view returns (address) {
        return PSStorage.getStorage().rfqAddr;
    }

    function limitOrderAddr() public view returns (address) {
        return PSStorage.getStorage().limitOrderAddr;
    }

    function l2DepositAddr() public view returns (address) {
        return PSStorage.getStorage().l2DepositAddr;
    }

    function wethAddr() external view override returns (address) {
        return PSStorage.getStorage().wethAddr;
    }

    function getCurvePoolInfo(
        address _makerAddr,
        address _takerAssetAddr,
        address _makerAssetAddr
    )
        external
        view
        override
        returns (
            int128 takerAssetIndex,
            int128 makerAssetIndex,
            uint16 swapMethod,
            bool supportGetDx
        )
    {
        // underlying_coins
        int128 i = AMMWrapperStorage.getStorage().curveTokenIndexes[_makerAddr][_takerAssetAddr];
        int128 j = AMMWrapperStorage.getStorage().curveTokenIndexes[_makerAddr][_makerAssetAddr];
        supportGetDx = AMMWrapperStorage.getStorage().curveSupportGetDx[_makerAddr];

        swapMethod = 0;
        if (i != 0 && j != 0) {
            // in underlying_coins list
            takerAssetIndex = i;
            makerAssetIndex = j;
            // exchange_underlying
            swapMethod = 2;
        } else {
            // in coins list
            int128 iWrapped = AMMWrapperStorage.getStorage().curveWrappedTokenIndexes[_makerAddr][_takerAssetAddr];
            int128 jWrapped = AMMWrapperStorage.getStorage().curveWrappedTokenIndexes[_makerAddr][_makerAssetAddr];
            if (iWrapped != 0 && jWrapped != 0) {
                takerAssetIndex = iWrapped;
                makerAssetIndex = jWrapped;
                // exchange
                swapMethod = 1;
            } else {
                revert("PermanentStorage: invalid pair");
            }
        }
        return (takerAssetIndex, makerAssetIndex, swapMethod, supportGetDx);
    }

    function isTransactionSeen(bytes32 _transactionHash) external view override returns (bool) {
        return AMMWrapperStorage.getStorage().transactionSeen[_transactionHash];
    }

    function isAMMTransactionSeen(bytes32 _transactionHash) external view override returns (bool) {
        return AMMWrapperStorage.getStorage().transactionSeen[_transactionHash];
    }

    function isRFQTransactionSeen(bytes32 _transactionHash) external view override returns (bool) {
        return RFQStorage.getStorage().transactionSeen[_transactionHash];
    }

    function isLimitOrderTransactionSeen(bytes32 _transactionHash) external view override returns (bool) {
        return LimitOrderStorage.getStorage().transactionSeen[_transactionHash];
    }

    function isLimitOrderAllowFillSeen(bytes32 _allowFillHash) external view override returns (bool) {
        return LimitOrderStorage.getStorage().allowFillSeen[_allowFillHash];
    }

    function isRelayerValid(address _relayer) external view override returns (bool) {
        return AMMWrapperStorage.getStorage().relayerValid[_relayer];
    }

    /************************************************************
     *           Management functions for Operator               *
     *************************************************************/
    /// @dev Update AMMWrapper contract address.
    function upgradeAMMWrapper(address _newAMMWrapper) external {
        PSStorage.getStorage().ammWrapperAddr = _newAMMWrapper;
    }

    /// @dev Update PMM contract address.
    function upgradePMM(address _newPMM) external {
        PSStorage.getStorage().pmmAddr = _newPMM;
    }

    /// @dev Update RFQ contract address.
    function upgradeRFQ(address _newRFQ) external {
        PSStorage.getStorage().rfqAddr = _newRFQ;
    }

    /// @dev Update Limit Order contract address.
    function upgradeLimitOrder(address _newLimitOrder) external {
        PSStorage.getStorage().limitOrderAddr = _newLimitOrder;
    }

    /// @dev Update WETH contract address.
    function upgradeWETH(address _newWETH) external {
        PSStorage.getStorage().wethAddr = _newWETH;
    }

    /************************************************************
     *                   External functions                      *
     *************************************************************/
    function setCurvePoolInfo(
        address _makerAddr,
        address[] calldata _underlyingCoins,
        address[] calldata _coins,
        bool _supportGetDx
    ) external override {
        int128 underlyingCoinsLength = int128(_underlyingCoins.length);
        for (int128 i = 0; i < underlyingCoinsLength; i++) {
            address assetAddr = _underlyingCoins[uint256(i)];
            // underlying coins for original DAI, USDC, TUSD
            AMMWrapperStorage.getStorage().curveTokenIndexes[_makerAddr][assetAddr] = i + 1;
        }

        int128 coinsLength = int128(_coins.length);
        for (int128 i = 0; i < coinsLength; i++) {
            address assetAddr = _coins[uint256(i)];
            // wrapped coins for cDAI, cUSDC, yDAI, yUSDC, yTUSD, yBUSD
            AMMWrapperStorage.getStorage().curveWrappedTokenIndexes[_makerAddr][assetAddr] = i + 1;
        }

        AMMWrapperStorage.getStorage().curveSupportGetDx[_makerAddr] = _supportGetDx;
    }

    function setTransactionSeen(bytes32 _transactionHash) external override {
        require(!AMMWrapperStorage.getStorage().transactionSeen[_transactionHash], "PermanentStorage: transaction seen before");
        AMMWrapperStorage.getStorage().transactionSeen[_transactionHash] = true;
    }

    function setAMMTransactionSeen(bytes32 _transactionHash) external override {
        require(!AMMWrapperStorage.getStorage().transactionSeen[_transactionHash], "PermanentStorage: transaction seen before");
        AMMWrapperStorage.getStorage().transactionSeen[_transactionHash] = true;
    }

    function setRFQTransactionSeen(bytes32 _transactionHash) external override {
        require(!RFQStorage.getStorage().transactionSeen[_transactionHash], "PermanentStorage: transaction seen before");
        RFQStorage.getStorage().transactionSeen[_transactionHash] = true;
    }

    function setLimitOrderTransactionSeen(bytes32 _transactionHash) external override {
        require(!LimitOrderStorage.getStorage().transactionSeen[_transactionHash], "PermanentStorage: transaction seen before");
        LimitOrderStorage.getStorage().transactionSeen[_transactionHash] = true;
    }

    function setLimitOrderAllowFillSeen(bytes32 _allowFillHash) external override {
        require(!LimitOrderStorage.getStorage().allowFillSeen[_allowFillHash], "PermanentStorage: allow fill seen before");
        LimitOrderStorage.getStorage().allowFillSeen[_allowFillHash] = true;
    }

    function setRelayersValid(address[] calldata _relayers, bool[] calldata _isValids) external override {
        require(_relayers.length == _isValids.length, "PermanentStorage: inputs length mismatch");
        for (uint256 i = 0; i < _relayers.length; i++) {
            AMMWrapperStorage.getStorage().relayerValid[_relayers[i]] = _isValids[i];
        }
    }
}
