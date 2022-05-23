import { TASK_COMPILE_SOLIDITY_GET_SOURCE_PATHS } from "hardhat/builtin-tasks/task-names"
import { subtask } from "hardhat/config"

import "@nomiclabs/hardhat-waffle"
import "@nomiclabs/hardhat-ethers"
import "@typechain/hardhat"
import "tsconfig-paths/register"

subtask(TASK_COMPILE_SOLIDITY_GET_SOURCE_PATHS).setAction(async (_, __, runSuper) => {
    const paths = await runSuper()

    return paths.filter((p) => !(p.endsWith(".t.sol") || p.includes("test/utils")))
})

const MAINNET_NODE_RPC_URL = process.env.MAINNET_NODE_RPC_URL || ""

module.exports = {
    networks: {
        hardhat: {
            chainId: 1,
            forking: {
                url: `${MAINNET_NODE_RPC_URL}`,
                blockNumber: 14340000,
            },
        },
    },
    solidity: {
        compilers: [
            {
                version: "0.7.6",
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 1000,
                    },
                },
            },
        ],
    },
    mocha: {
        timeout: 600000,
    },
}
