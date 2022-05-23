import * as addr from "~/test/utils/address"
import { ERC20, Native } from "./prototype"

/* BTC */

export const HBTC = ERC20.createFactory({
    address: addr.HBTC_ADDR,
})

export const renBTC = ERC20.createFactory({
    address: addr.REN_BTC_ADDR,
    decimals: 8,
})

export const sBTC = ERC20.createFactory({
    address: addr.SBTC_ADDR,
})

export const WBTC = ERC20.createFactory({
    address: addr.WBTC_ADDR,
    decimals: 8,
})

/* DAI */

export const DAI = ERC20.createFactory({
    address: addr.DAI_ADDR,
})

export const cDAI = ERC20.createFactory({
    address: addr.CDAI_ADDR,
    decimals: 8,
})

/* ETH */

export const ETH = Native.createFactory({
    address: "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE",
})

export const sETH = ERC20.createFactory({
    address: addr.SETH_ADDR,
})

export const WETH = ERC20.createFactory({
    address: addr.WETH_ADDR,
})

/* OMG */

export const OMG = ERC20.createFactory({
    address: addr.OMG_ADDR,
})

/* LON */

export const LON = ERC20.createFactory({
    address: addr.LON_ADDR,
})

/* SKL */

export const SKL = ERC20.createFactory({
    address: addr.SKL_ADDR,
})

/* STA - with deflation */

export const STA = ERC20.createFactory({
    address: addr.STA_ADDR,
})

/* SUSHI */

export const SUSHI = ERC20.createFactory({
    address: addr.SUSHI_ADDR,
})

/* UNI */

export const UNI = ERC20.createFactory({
    address: addr.UNI_ADDR,
})

/* USD */

export const TUSD = ERC20.createFactory({
    address: addr.TUSD_ADDR,
})

export const sUSD = ERC20.createFactory({
    address: addr.SUSD_ADDR,
})

/* USDC */

export const USDC = ERC20.createFactory({
    address: addr.USDC_ADDR,
    decimals: 6,
})

export const cUSDC = ERC20.createFactory({
    address: addr.CUSDC_ADDR,
    decimals: 8,
})

/* USDT */

export const USDT = ERC20.createFactory({
    address: addr.USDT_ADDR,
    decimals: 6,
})

/* ZRX */

export const ZRX = ERC20.createFactory({
    address: addr.ZRX_ADDR,
})

/* stAAVE */

export const stAAVE = ERC20.createFactory({
    address: addr.STAAVE_ADDR,
})

/* Pool */

export const busdPoolyDAI = ERC20.createFactory({
    address: addr.CURVE_WRAPPED.BUSD_POOL_DAI_ADDR,
})

export const busdPoolyBUSD = ERC20.createFactory({
    address: addr.CURVE_WRAPPED.BUSD_POOL_BUSD_ADDR,
})

export const yPoolyDAI = ERC20.createFactory({
    address: addr.CURVE_WRAPPED.Y_POOL_DAI_ADDR,
})
