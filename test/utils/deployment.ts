import { MockContract, deployMockContract } from "@ethereum-waffle/mock-contract"
import { Contract } from "ethers"
import { ethers } from "hardhat"
import { FactoryOptions } from "hardhat/types/runtime"

// reexport for convenience
export { MockContract }

export type DeployOptions = FactoryOptions & {
    args?: any[]
}

export async function deploy<T extends Contract>(
    contractName: string,
    options: DeployOptions = {},
): Promise<T> {
    const contractFactory = await ethers.getContractFactory(contractName, {
        signer: options.signer,
        libraries: options.libraries,
    })
    const contract = await contractFactory.deploy(...(options.args || []))
    return contract as T
}

export async function deployMock<T>(contractName: string): Promise<T & MockContract> {
    const contractFactory = await ethers.getContractFactory(contractName)
    const result = await deployMockABI(contractFactory.interface.format())
    return result as T & MockContract
}

export async function deployMockABI(abi: any): Promise<MockContract> {
    return deployMockContract(
        (await ethers.getSigners()).slice(-1)[0], // use last signer to avoid account conflicting in tests,
        abi,
    )
}
