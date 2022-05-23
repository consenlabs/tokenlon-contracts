import { BigNumberish, CallOverrides, Contract, ContractTransaction, ethers } from "ethers"
import { setERC20Balance, setStorageAt, toBytes32 } from "~/test/utils/network"
import abi from "../abi"
import { Addressable, getAddress } from "../address"
import { getProvider } from "../provider"
import { Token, TokenConfig, TokenOwner, createTokenFactory } from "./Token"

export interface ERC20Constructor<T extends ERC20 = ERC20> {
    new (value: BigNumberish): T
}

export interface ERC20Factory<T extends ERC20 = ERC20> extends ERC20MetaGetter {
    (value: BigNumberish, config?: TokenConfig): T
    allowanceOf(owner: Addressable, spender: Addressable, overrides?: CallOverrides): Promise<T>
    approveMax(
        owner: TokenOwner,
        spender: Addressable,
        overrides?: CallOverrides,
    ): Promise<ContractTransaction>
    balanceOf(target: Addressable, overrides?: CallOverrides): Promise<T>
}

export interface ERC20MetaGetter {
    abi: object[]
    address: string
    decimals: number
    contract: Contract
}

export type ERC20FactoryMeta = {
    // TODO: custom provider for token
    abi?: object[]
    address: string
    decimals?: number
}

export class ERC20 extends Token {
    public static abi: object[] = abi.ERC20
    public static address = "0x"
    public static decimals = 18

    public static get contract(): Contract {
        return new Contract(this.address, this.abi, getProvider())
    }

    public static createFactory<T extends ERC20 = ERC20>(
        ERC20Meta: ERC20FactoryMeta,
        ERC20Cls: ERC20Constructor<T> = ERC20 as any,
    ): ERC20Factory<T> {
        return createTokenFactory(ERC20Cls, {
            ...(ERC20Meta as ERC20MetaGetter),
            ...ERC20FactoryUtils,
        })
    }

    /* meta */

    public get abi(): object[] {
        return this.meta.abi
    }

    public get address(): string {
        return this.meta.address
    }

    public get decimals(): number {
        return this.meta.decimals
    }

    public get contract(): Contract {
        return new Contract(this.address, this.abi, getProvider())
    }

    /* contract */

    public async approve(target: Addressable): Promise<ContractTransaction> {
        return this.contract.connect(this.mustGetOwner()).approve(await getAddress(target), this)
    }

    public async approveFrom(owner: TokenOwner, target: Addressable): Promise<ContractTransaction> {
        return this.contract.connect(owner).approve(await getAddress(target), this)
    }

    public async setBalance() {
        await this.setBalanceFor(this.mustGetOwner())
    }

    public async setBalanceFor(target: Addressable) {
        try {
            await setERC20Balance(this.address, await getAddress(target), this)
        } catch (e: any) {
            if (e.message.includes("registered")) {
                await setStorageAt(
                    this.address,
                    ethers.utils.solidityKeccak256(
                        ["uint256", "uint256"],
                        [await getAddress(target), 0], // key, slot
                    ),
                    toBytes32(this).toString(),
                )
                return
            }
            throw e
        }
    }

    public async transferFrom(
        owner: Addressable,
        recipient: Addressable,
    ): Promise<ContractTransaction> {
        return this.contract
            .connect(this.mustGetOwner())
            .transferFrom(await getAddress(owner), await getAddress(recipient), this)
    }

    public async transferTo(recipient: Addressable): Promise<ContractTransaction> {
        return this.contract
            .connect(this.mustGetOwner())
            .transfer(await getAddress(recipient), this)
    }
}

export const ERC20FactoryUtils = {
    async allowanceOf<T extends ERC20>(
        this: ERC20Factory<T>,
        owner: Addressable,
        spender: Addressable,
        overrides: CallOverrides = {},
    ) {
        const allowance = await this.contract.allowance(
            await getAddress(owner),
            await getAddress(spender),
            overrides,
        )
        return this(allowance, { ignoreDecimals: true })
    },

    async approveMax<T extends ERC20>(
        this: ERC20Factory<T>,
        owner: TokenOwner,
        spender: Addressable,
    ) {
        return this.contract
            .connect(owner)
            .approve(await getAddress(spender), ethers.constants.MaxUint256)
    },

    async balanceOf<T extends ERC20>(
        this: ERC20Factory<T>,
        target: Addressable,
        overrides: CallOverrides = {},
    ): Promise<T> {
        const balance = await this.contract.balanceOf(await getAddress(target), overrides)
        return this(balance, { ignoreDecimals: true })
    },
}
