import { expect } from "chai"
import { BigNumber } from "ethers"
import { ethers } from "hardhat"
import { Addressable, getAddress } from "../address"
import { ERC20, Native } from "../token"

/* chain */

export class Snapshot {
    static async take(): Promise<Snapshot> {
        const snapshot = await ethers.provider.send("evm_snapshot", [])
        return new Snapshot(snapshot)
    }

    private constructor(public snapshot: string) {}

    public async reset() {
        // "evm_revert" will revert state to given snapshot then delete it, as well as any snapshots taken after.
        // (e.g.: reverting to id 0x1 will delete snapshots with ids 0x1, 0x2, etc.)
        await ethers.provider.send("evm_revert", [this.snapshot])
        // so we need to retake after each revert
        this.snapshot = await ethers.provider.send("evm_snapshot", [])
    }
}

/* balance */

type Balanceable = {
    address: string
    balanceOf(address: string): Promise<BigNumber>
}

type AssetDiff = {
    asset: ERC20
    income: boolean
}

type AccountChange = {
    owner: string
    assetDiffs: AssetDiff[]
}

export class BalanceSnapshot {
    public static async take(owners: Addressable[], tokens: (ERC20 | Native | Balanceable)[]) {
        const data: {
            [ownerAddress: string]: {
                [tokenAddress: string]: BigNumber
            }
        } = {}
        for (const owner of owners) {
            const ownerAddress = await getAddress(owner)
            if (!data[ownerAddress]) {
                data[ownerAddress] = {}
            }
            for (const token of tokens) {
                const balance: ERC20 | Native = await (token.constructor as any).balanceOf(owner)
                data[ownerAddress][token.address] = balance
            }
        }
        return new BalanceSnapshot(data)
    }

    private constructor(
        public data: {
            [ownerAddress: string]: {
                [tokenAddress: string]: BigNumber
            }
        },
    ) {}

    public async assertBalanceChanges(...changes: [Addressable, (ERC20 | Native)[]][]) {
        for (const [owner, tokens] of changes) {
            const ownerAddress = await getAddress(owner)
            for (const token of tokens) {
                const balance: ERC20 | Native = await (token.constructor as any).balanceOf(owner)
                expect(balance.sub(this.data[ownerAddress][token.address])).to.equal(token)
            }
        }
    }

    public async assertAccountChanges(accountChanges: AccountChange[]) {
        for (const accountChange of accountChanges) {
            const ownerAddr = accountChange.owner
            for (const assetDiff of accountChange.assetDiffs) {
                const tokenAddr = assetDiff.asset.address
                const balanceBefore = this.data[ownerAddr][tokenAddr]
                const balanceAfter = await (
                    await ethers.getContractAt("ERC20", tokenAddr)
                ).balanceOf(ownerAddr)
                if (assetDiff.income) {
                    // Balance expected to be increased
                    expect(balanceAfter.sub(balanceBefore)).to.equal(assetDiff.asset)
                } else {
                    // Balance expected to be desreased
                    expect(balanceBefore.sub(balanceAfter)).to.equal(assetDiff.asset)
                }
            }
        }
    }
}
