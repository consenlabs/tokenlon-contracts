import { expect } from "chai"
import { ethers } from "hardhat"
import { Snapshot } from "~/test/utils/network"
import { useProviderIfNotExisting } from "../provider"
import { Native } from "./Native"

describe("Native", () => {
    describe("Inherent Behaviors", () => {
        class CustomNative extends Native {
            public otherExtendedMethod() {
                // ...
            }
        }
        const TKNMeta = {
            address: "0xnative",
            decimals: 9,
        }
        const TKN = Native.createFactory(TKNMeta, CustomNative)

        describe("Meta", () => {
            it("should be an instance of Native", () => {
                const t = TKN(0)

                expect(t).to.be.instanceOf(TKN)
                expect(t).to.be.instanceOf(CustomNative)
                expect(t).to.be.instanceOf(Native)
            })

            it("should set meta for factory", () => {
                const { address, decimals } = TKNMeta

                expect(TKN.address).to.equal(address)
                expect(TKN.decimals).to.equal(decimals)
            })

            it("should set meta for instance", () => {
                const { address, decimals } = TKNMeta

                const t = TKN(0)

                expect(t.address).to.equal(address)
                expect(t.decimals).to.equal(decimals)
            })
        })
    })

    describe("Blockchain Interaction", () => {
        const ETH = Native.createFactory({
            decimals: 18,
        })
        const user = new ethers.Wallet(
            "0x0000000000000000000000000000000000000000000000000000000000000123",
            ethers.provider,
        )
        let snapshot: Snapshot

        before(async () => {
            useProviderIfNotExisting(ethers.provider)
            snapshot = await Snapshot.take()
        })

        beforeEach(async () => {
            await snapshot.reset()
        })

        describe("transfer", () => {
            it("should transfer from connected owner to recipient", async () => {
                const [vault] = await ethers.getSigners()

                await ETH(100).from(vault).transferTo(user)

                const balance = await ETH.balanceOf(user)
                expect(balance).to.equal(ETH(100))
            })
        })
    })
})
