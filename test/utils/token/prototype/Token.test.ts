import { expect } from "chai"
import { ethers } from "hardhat"
import { BigNumber } from "ethers"
import { Token, createTokenFactory } from "./Token"

describe("Token", () => {
    class CustomToken extends Token {
        public static decimals = 10
    }
    const TKN = createTokenFactory(CustomToken)

    describe("BigNumber", () => {
        it("should be instance of BigNumber", () => {
            expect(TKN(0)).to.be.instanceOf(BigNumber)
        })

        it("should translate decimals", () => {
            expect(TKN(100)).to.equal(
                BigNumber.from(ethers.utils.parseUnits("100", CustomToken.decimals)),
            )
            expect(TKN(0.00123)).to.equal(
                BigNumber.from(ethers.utils.parseUnits("0.00123", CustomToken.decimals)),
            )
            expect(TKN(123.00456)).to.equal(
                BigNumber.from(ethers.utils.parseUnits("123.00456", CustomToken.decimals)),
            )
        })

        it("should support arithmetic", () => {
            const t = TKN(100)

            const add = t.add(TKN(10))
            expect(add).to.be.instanceOf(TKN)
            expect(add).to.equal(TKN(110))

            const sub = t.sub(TKN(10))
            expect(sub).to.be.instanceOf(TKN)
            expect(sub).to.equal(TKN(90))

            const mul = t.mul(10)
            expect(mul).to.be.instanceOf(TKN)
            expect(mul).to.equal(TKN(1000))

            const div = t.div(10)
            expect(div).to.be.instanceOf(TKN)
            expect(div).to.equal(TKN(10))

            const abs = t.mul(-1).abs()
            expect(abs).to.be.instanceOf(TKN)
            expect(abs).to.equal(TKN(100))
        })
    })

    describe("Meta", () => {
        it("should be an instance of Token", () => {
            const t = TKN(0)

            expect(t).to.be.instanceOf(TKN)
            expect(t).to.be.instanceOf(CustomToken)
            expect(t).to.be.instanceOf(Token)
        })

        it("should connect owner to token", async () => {
            const [user] = await ethers.getSigners()

            const t = TKN(100)

            const tConnectedToUser = t.connect(user)
            expect(tConnectedToUser.owner).to.equal(user)

            // alias to connect
            const tFromUser = t.from(user)
            expect(tFromUser.owner).to.equal(user)

            expect(t.owner).to.be.undefined
        })

        it("should throw error from mustGetOwner when no owner set", () => {
            const action = () => {
                TKN(0).mustGetOwner()
            }
            expect(action).to.throw()
        })
    })
})
