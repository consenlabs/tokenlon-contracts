import { TransactionResponse } from "@ethersproject/abstract-provider"
import { BigNumberish } from "ethers"
import { Addressable, getAddress } from "../address"
import { getProvider } from "../provider"
import { Token, TokenConfig, createTokenFactory } from "./Token"

export interface NativeConstructor<T extends Native = Native> {
    new (value: BigNumberish): T
}

export interface NativeFactory<T extends Native = Native> extends NativeMetaGetter {
    (value: BigNumberish, config?: TokenConfig): T
    balanceOf(target: Addressable): Promise<T>
}

export interface NativeMetaGetter {
    address: string
    decimals: number
}

export type NativeFactoryMeta = {
    address?: string
    decimals?: number
}

export class Native extends Token {
    public static address = "0x"
    public static decimals = 18

    public static createFactory<T extends Native = Native>(
        NativeMeta: NativeFactoryMeta,
        NativeCls: NativeConstructor<T> = Native as any,
    ): NativeFactory<T> {
        return createTokenFactory(NativeCls, {
            ...(NativeMeta as NativeMetaGetter),
            ...NativeFactoryUtils,
        })
    }

    public get address(): string {
        return this.meta.address
    }

    public async transferTo(recipient: Addressable): Promise<TransactionResponse> {
        const owner = this.mustGetOwner()
        return owner.sendTransaction({
            to: await getAddress(recipient),
            value: this,
        })
    }
}

export const NativeFactoryUtils = {
    async balanceOf<T extends Native>(this: NativeFactory<T>, target: Addressable): Promise<T> {
        const balance = await getProvider().getBalance(await getAddress(target))
        return this(balance, { ignoreDecimals: true })
    },
}
