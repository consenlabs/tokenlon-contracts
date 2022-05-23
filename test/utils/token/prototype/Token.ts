import { BigNumber, BigNumberish, Signer, ethers } from "ethers"

export type TokenOwner = Signer

export type TokenConfig = {
    owner?: TokenOwner
    ignoreDecimals?: boolean
}

export class Token extends BigNumber {
    public static decimals = 18

    // eslint-disable-next-line
    public owner?: TokenOwner

    // @ts-ignore
    public constructor(value: BigNumberish, config: TokenConfig = {}) {
        const self = Object.create(new.target.prototype) as unknown as Token

        const bn = ethers.utils.parseUnits(
            value.toString(),
            config.ignoreDecimals ? 0 : self.decimals,
        )
        Object.assign(self, bn)

        if (config.owner) {
            self.owner = config.owner
        }

        return self
    }

    /* public */

    public get meta() {
        return this.constructor as any
    }

    public get decimals() {
        return this.meta.decimals
    }

    /* big number */

    public add(value: BigNumberish): this {
        return this.wrap(super.add(value))
    }

    public sub(value: BigNumberish): this {
        return this.wrap(super.sub(value))
    }

    public mul(value: BigNumberish): this {
        return this.wrap(super.mul(value))
    }

    public div(value: BigNumberish): this {
        return this.wrap(super.div(value))
    }

    public abs(): this {
        return this.wrap(super.abs())
    }

    /* util */

    public connect(owner: TokenOwner) {
        return this.wrap(this, { owner })
    }

    public from(owner: TokenOwner) {
        return this.connect(owner)
    }

    public mustGetOwner(): TokenOwner {
        if (!this.owner) {
            throw new Error("No owner found for token")
        }
        return this.owner
    }

    /* protected */

    protected wrap(value: BigNumberish, config: TokenConfig = {}): this {
        return Reflect.construct(this.constructor, [
            value,
            Object.assign(
                {
                    owner: this.owner,
                    ignoreDecimals: true,
                },
                config,
            ),
        ])
    }
}

export interface TokenFactory<T> {
    (value: BigNumberish, config?: TokenConfig): T
}

export function createTokenFactory<T, S>(
    TokenCls: new (...args: any[]) => T,
    TokenStatic?: S,
): TokenFactory<T> & S {
    const Token = function (this: any, ...args: any[]) {
        return Reflect.construct(TokenCls, args, Token)
    }
    Reflect.setPrototypeOf(Token.prototype, TokenCls.prototype)
    Reflect.setPrototypeOf(Token, TokenCls)

    if (TokenStatic) {
        // setup static props
        Object.assign(Token, TokenStatic)
    }

    return Token as TokenFactory<T> & S
}
