import { ethers } from "hardhat"

export const getChainId = async () => {
    return parseInt(await ethers.provider.send("net_version", []))
}
