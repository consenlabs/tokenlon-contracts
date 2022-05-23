pragma solidity 0.7.6;

import { PermanentStorage } from "contracts/PermanentStorage.sol";
import "./Addresses.sol";

contract RegisterCurveIndexes {
    address[] COMPOUND_POOL_UNDERLYING_COINS = [Addresses.DAI_ADDRESS, Addresses.USDC_ADDRESS];
    address[] COMPOUND_POOL_COINS = [Addresses.cDAI_ADDRESS, Addresses.cUSDC_ADDRESS];
    bool constant COMPOUND_POOL_SUPPORT_GET_DX = true;

    address[] USDT_POOL_UNDERLYING_COINS = [Addresses.DAI_ADDRESS, Addresses.USDC_ADDRESS, Addresses.USDT_ADDRESS];
    address[] USDT_POOL_COINS = [Addresses.cDAI_ADDRESS, Addresses.cUSDC_ADDRESS, Addresses.USDT_ADDRESS];
    bool constant USDT_POOL_SUPPORT_GET_DX = true;

    address[] Y_POOL_UNDERLYING_COINS = [Addresses.DAI_ADDRESS, Addresses.USDC_ADDRESS, Addresses.USDT_ADDRESS, Addresses.TUSD_ADDRESS];
    address[] Y_POOL_COINS = [Addresses.yDAI_ADDRESS, Addresses.yUSDC_ADDRESS, Addresses.yUSDT_ADDRESS, Addresses.yTUSD_ADDRESS];
    bool constant Y_POOL_SUPPORT_GET_DX = true;

    address[] C3_POOL_COINS = [Addresses.DAI_ADDRESS, Addresses.USDC_ADDRESS, Addresses.USDT_ADDRESS];
    bool constant C3_POOL_SUPPORT_GET_DX = false;

    address[] TRICRYPTO2POOL_COINS = [Addresses.USDT_ADDRESS, Addresses.WBTC_ADDRESS, Addresses.WETH_ADDRESS];
    bool constant TRICRYPTO2POOL_SUPPORT_GET_DX = false;

    function _registerCurveIndexes(PermanentStorage pm) internal {
        // register Compound pool
        pm.setCurvePoolInfo(Addresses.CURVE_COMPOUND_POOL_ADDRESS, COMPOUND_POOL_UNDERLYING_COINS, COMPOUND_POOL_COINS, COMPOUND_POOL_SUPPORT_GET_DX);

        // register USDT pool
        pm.setCurvePoolInfo(Addresses.CURVE_USDT_POOL_ADDRESS, USDT_POOL_UNDERLYING_COINS, USDT_POOL_COINS, USDT_POOL_SUPPORT_GET_DX);

        // register Y pool
        pm.setCurvePoolInfo(Addresses.CURVE_Y_POOL_ADDRESS, Y_POOL_UNDERLYING_COINS, Y_POOL_COINS, Y_POOL_SUPPORT_GET_DX);

        // register 3 pool
        pm.setCurvePoolInfo(Addresses.CURVE_3_POOL_ADDRESS, new address[](0), C3_POOL_COINS, C3_POOL_SUPPORT_GET_DX);

        // register tricrypto2 pool
        pm.setCurvePoolInfo(Addresses.CURVE_TRICRYPTO2_POOL_ADDRESS, new address[](0), TRICRYPTO2POOL_COINS, TRICRYPTO2POOL_SUPPORT_GET_DX);
    }
}
