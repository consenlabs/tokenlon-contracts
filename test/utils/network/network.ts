import { BigNumber } from "ethers"
import { config, ethers, network } from "hardhat"
import * as addr from "~/test/utils/address"

const normalStorageSlot = 0
const proxyStorageSlot = 1
const storageSlotMap = {
    [addr.WETH_ADDR]: [normalStorageSlot, 3],
    [addr.DAI_ADDR]: [normalStorageSlot, 2],
    [addr.USDC_ADDR]: [normalStorageSlot, 9],
    [addr.USDT_ADDR]: [normalStorageSlot, 2],
    [addr.TUSD_ADDR]: [normalStorageSlot, 14],
    [addr.BUSD_ADDR]: [normalStorageSlot, 1],
    [addr.SUSHI_ADDR]: [normalStorageSlot, 0],
    "0x0000000000095413afC295d19EDeb1Ad7B71c952": [normalStorageSlot, 0], // LON
    [addr.UNI_ADDR]: [normalStorageSlot, 4],
    [addr.OMG_ADDR]: [normalStorageSlot, 1],
    [addr.SKL_ADDR]: [normalStorageSlot, 0],
    [addr.CRV_ADDR]: [normalStorageSlot, 3],
    [addr.STAAVE_ADDR]: [normalStorageSlot, 0],
    [addr.ZRX_ADDR]: [normalStorageSlot, 0],
    [addr.CDAI_ADDR]: [normalStorageSlot, 14],
    [addr.CUSDC_ADDR]: [normalStorageSlot, 15],
    [addr.WBTC_ADDR]: [normalStorageSlot, 0],
    [addr.CURVE_WRAPPED.BUSD_POOL_DAI_ADDR]: [normalStorageSlot, 0],
    [addr.CURVE_WRAPPED.Y_POOL_DAI_ADDR]: [normalStorageSlot, 0],
    [addr.REN_BTC_ADDR]: [normalStorageSlot, 102],
    [addr.STA_ADDR]: [normalStorageSlot, 3],
    "0x57Ab1ec28D129707052df4dF418D58a2D46d5f51": [
        proxyStorageSlot,
        "0x05a9CBe762B36632b3594DA4F082340E0e5343e8",
        3,
    ], // sUSD proxy to another token state contract
    "0x5e74C9036fb86BD7eCdcb084a0673EFc32eA31cb": [
        proxyStorageSlot,
        "0x34A5ef81d18F3a305aE9C2d7DF42beef4c79031c",
        3,
    ], // sETH proxy to another token state contract
    "0x0316EB71485b0Ab14103307bf65a021042c6d380": [
        proxyStorageSlot,
        "0xC728693dCf6B257BF88577D6c92E52028426eefd",
        4,
    ], // hBTC proxy to another token state contract
}

export async function mineBlock(timestamp: number) {
    await ethers.provider.send("evm_mine", [timestamp])
}

export async function fastforward(duration: number) {
    await ethers.provider.send("evm_increaseTime", [duration])
    await ethers.provider.send("evm_mine", [])
}

// advanceNextBlockTimestamp is mainly used before mutation function
export async function advanceNextBlockTimestamp(seconds: number) {
    await ethers.provider.send("evm_increaseTime", [seconds])
}

export async function getCurrentBlockTimestamp(): Promise<number> {
    const provider = ethers.provider
    const blockNumber = await provider.getBlockNumber()
    const block = await provider.getBlock(blockNumber)
    return block.timestamp
}

// setNextBlockTimestamp is mainly used before mutation function
export async function setNextBlockTimestamp(timestamp: number) {
    await ethers.provider.send("evm_setNextBlockTimestamp", [timestamp])
}

// reset hardhat mainnet fork
export async function resetHardhatFork(blockNumber: number) {
    await network.provider.request({
        method: "hardhat_reset",
        params: [
            {
                forking: {
                    jsonRpcUrl: config.networks.hardhat.forking?.url,
                    blockNumber: blockNumber,
                },
            },
        ],
    })
}

// impersonate multiple accounts
export async function impersonateAccounts(addrs: Array<string>) {
    for (const addr of addrs) {
        await network.provider.request({
            method: "hardhat_impersonateAccount",
            params: [addr],
        })
    }
}

export function toBytes32(bn: BigNumber): string {
    return ethers.utils.hexlify(ethers.utils.zeroPad(bn.toHexString(), 32))
}

export async function setStorageAt(contractAddress: string, index: string, value: string) {
    await ethers.provider.send("hardhat_setStorageAt", [contractAddress, index, value])
    await ethers.provider.send("evm_mine", []) // Just mines to the next block
}

export async function setERC20Balance(
    contractAddress: string,
    userAddress: string,
    balance: BigNumber,
) {
    let storageSlotInfo = storageSlotMap[contractAddress]
    if (storageSlotInfo === undefined) {
        throw Error(`Storage slot of balanceOf not registered for contract: ${contractAddress}`)
    }
    let actualContractAddress = contractAddress
    let index: string
    if (storageSlotInfo[0] == normalStorageSlot) {
        const storageSlot = storageSlotInfo[1]
        index = ethers.utils.solidityKeccak256(
            ["uint256", "uint256"],
            [userAddress, storageSlot], // key, slot
        )
    } else {
        actualContractAddress = storageSlotInfo[1] as string
        const storageSlot = storageSlotInfo[2]
        index = ethers.utils.solidityKeccak256(
            ["uint256", "uint256"],
            [userAddress, storageSlot], // key, slot
        )
    }
    // remove padding for JSON RPC
    while (index.startsWith("0x0")) {
        index = "0x" + index.slice(3)
    }
    await setStorageAt(actualContractAddress, index, toBytes32(balance))
}
