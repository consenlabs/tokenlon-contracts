import { expect } from "chai"
import { ethers } from "hardhat"
import { Signer } from "ethers"
import { deploy } from "~/test/utils/deployment"
import { Snapshot } from "~/test/utils/network"
import { useProviderIfNotExisting } from "../provider"
import { ERC20, ERC20Factory } from "./ERC20"

describe("ERC20", () => {
    describe("Inherent Behaviors", () => {
        class CustomToken extends ERC20 {
            public otherExtendedMethod() {
                // ...
            }
        }
        const TKNMeta = {
            abi: [
                {
                    name: "action",
                    type: "function",
                },
            ],
            address: "0xtkn",
            decimals: 9,
        }
        const TKN = ERC20.createFactory(TKNMeta, CustomToken)

        describe("Meta", () => {
            it("should be an instance of ERC20", () => {
                const t = TKN(0)

                expect(t).to.be.instanceOf(TKN)
                expect(t).to.be.instanceOf(CustomToken)
                expect(t).to.be.instanceOf(ERC20)
            })

            it("should set meta for factory", () => {
                const { abi, address, decimals } = TKNMeta

                expect(TKN.abi).to.equal(abi)
                expect(TKN.address).to.equal(address)
                expect(TKN.decimals).to.equal(decimals)
            })

            it("should set meta for instance", () => {
                const { abi, address, decimals } = TKNMeta

                const t = TKN(0)

                expect(t.abi).to.equal(abi)
                expect(t.address).to.equal(address)
                expect(t.decimals).to.equal(decimals)
            })
        })
    })

    describe("Contract Interaction", () => {
        let user: Signer
        let deployer: Signer

        let TKN: ERC20Factory<ERC20>

        let snapshot: Snapshot

        before(async () => {
            ;[user, deployer] = (await ethers.getSigners()).slice(-2)

            useProviderIfNotExisting(ethers.provider)

            // deploy test token
            const { address } = await deploy("ERC20", {
                args: ["Token", "TKN"],
                signer: deployer,
            })
            // setup test token
            TKN = ERC20.createFactory({
                address,
                decimals: 18,
            })

            snapshot = await Snapshot.take()
        })

        beforeEach(async () => {
            await snapshot.reset()
        })

        describe("allowance", () => {
            it("should approve allowance for spender", async () => {
                const [spender] = await ethers.getSigners()

                await TKN(100).approveFrom(user, spender)

                const allowance = await TKN.allowanceOf(user, spender)
                expect(allowance).to.equal(TKN(100))
            })

            it("should approve allowance from owner", async () => {
                const [spender] = await ethers.getSigners()

                await TKN(100).from(user).approve(spender)

                const allowance = await TKN.allowanceOf(user, spender)
                expect(allowance).to.equal(TKN(100))
            })

            it("should approve max allowance for spender", async () => {
                const [spender] = await ethers.getSigners()

                await TKN.approveMax(user, spender)

                const allowance = await TKN.allowanceOf(user, spender)
                expect(allowance).to.equal(ethers.constants.MaxUint256)
            })
        })

        describe("balance", () => {
            it("should set balance for target", async () => {
                await TKN(100).setBalanceFor(user)

                const balance = await TKN.balanceOf(user)
                expect(balance).to.equal(TKN(100))
            })

            it("should set balance for connected owner", async () => {
                await TKN(100).connect(user).setBalance()

                const balance = await TKN.balanceOf(user)
                expect(balance).to.equal(TKN(100))
            })
        })

        describe("transfer", () => {
            it("should transfer from connected owner to recipient", async () => {
                const [recipient] = await ethers.getSigners()

                await TKN(500).setBalanceFor(user)
                await TKN(100).from(user).transferTo(recipient)

                const balanceUser = await TKN.balanceOf(user)
                expect(balanceUser).to.equal(TKN(400))

                const balanceRecipient = await TKN.balanceOf(recipient)
                expect(balanceRecipient).to.equal(TKN(100))
            })

            it("should transfer by spender from owner to recipient", async () => {
                const [spender, recipient] = await ethers.getSigners()

                await TKN(500).setBalanceFor(user)
                await TKN(300).from(user).approve(spender)

                await TKN(100).from(spender).transferFrom(user, recipient)

                const balanceUser = await TKN.balanceOf(user)
                expect(balanceUser).to.equal(TKN(400))

                const balanceRecipient = await TKN.balanceOf(recipient)
                expect(balanceRecipient).to.equal(TKN(100))

                const allowanceSpender = await TKN.allowanceOf(user, spender)
                expect(allowanceSpender).to.equal(TKN(200))
            })
        })
    })
})
