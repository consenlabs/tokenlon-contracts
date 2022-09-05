// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import { PermanentStorage } from "contracts/PermanentStorage.sol";
import "./Addresses.sol";

contract RegisterCurveIndexes {
    address[] COMPOUND_POOL_UNDERLYING_COINS = [DAI_ADDRESS, USDC_ADDRESS];
    address[] COMPOUND_POOL_COINS = [cDAI_ADDRESS, cUSDC_ADDRESS];
    bool constant COMPOUND_POOL_SUPPORT_GET_DX = true;

    address[] USDT_POOL_UNDERLYING_COINS = [DAI_ADDRESS, USDC_ADDRESS, USDT_ADDRESS];
    address[] USDT_POOL_COINS = [cDAI_ADDRESS, cUSDC_ADDRESS, USDT_ADDRESS];
    bool constant USDT_POOL_SUPPORT_GET_DX = true;

    address[] Y_POOL_UNDERLYING_COINS = [DAI_ADDRESS, USDC_ADDRESS, USDT_ADDRESS, TUSD_ADDRESS];
    address[] Y_POOL_COINS = [yDAI_ADDRESS, yUSDC_ADDRESS, yUSDT_ADDRESS, yTUSD_ADDRESS];
    bool constant Y_POOL_SUPPORT_GET_DX = true;

    address[] C3_POOL_COINS = [DAI_ADDRESS, USDC_ADDRESS, USDT_ADDRESS];
    bool constant C3_POOL_SUPPORT_GET_DX = false;

    address[] ANKRETH_POOL_COINS = [ETH_ADDRESS, ANKRETH_ADDRESS];
    bool constant ANKRETH_POOL_SUPPORT_GET_DX = false;

    function _registerCurveIndexes(PermanentStorage pm) internal {
        // register Compound pool
        pm.setCurvePoolInfo(CURVE_COMPOUND_POOL_ADDRESS, COMPOUND_POOL_UNDERLYING_COINS, COMPOUND_POOL_COINS, COMPOUND_POOL_SUPPORT_GET_DX);

        // register USDT pool
        pm.setCurvePoolInfo(CURVE_USDT_POOL_ADDRESS, USDT_POOL_UNDERLYING_COINS, USDT_POOL_COINS, USDT_POOL_SUPPORT_GET_DX);

        // register Y pool
        pm.setCurvePoolInfo(CURVE_Y_POOL_ADDRESS, Y_POOL_UNDERLYING_COINS, Y_POOL_COINS, Y_POOL_SUPPORT_GET_DX);

        // register 3 pool
        pm.setCurvePoolInfo(CURVE_3_POOL_ADDRESS, new address[](0), C3_POOL_COINS, C3_POOL_SUPPORT_GET_DX);

        // register ANKRETH pool
        pm.setCurvePoolInfo(CURVE_ANKRETH_POOL_ADDRESS, new address[](0), ANKRETH_POOL_COINS, ANKRETH_POOL_SUPPORT_GET_DX);
    }
}
