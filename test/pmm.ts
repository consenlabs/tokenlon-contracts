import * as crypto from "crypto"
import { expect } from "chai"
import { config, ethers } from "hardhat"
import { assetDataUtils, BigNumber } from "0x.js"

import {
    contractWrappers,
    getWalletFromPrv,
    signTx,
    sign712Order,
    signEoaOrder,
    signOrder,
} from "./utils/0x"
import * as addr from "~/test/utils/address"

import {
    PMM,
    AllowanceTarget,
    MarketMakerProxy,
    PermanentStorage,
    Spender,
    UserProxy,
} from "~/typechain-types"
import { Snapshot, resetHardhatFork, setStorageAt } from "./utils/network"
import { DAI, ETH, SUSHI, USDC, USDT, WETH } from "~/test/utils/token"

describe("Test PMM contract", function () {
    const DEFAULT_EXPIRY = Math.floor(Date.now() / 1000) + 86400
    const FEE_FACTOR = new BigNumber(30)

    const zxExchangeAddr = "0x080bf510FCbF18b91105470639e9561022937712"
    const zxERC20ProxyAddr = "0x95E6F48254609A6ee006F7D493c8e5fB97094ceF"

    const wallet = {
        user: new ethers.Wallet(
            "0x0000000000000000000000000000000000000000000000000000000000000001",
            ethers.provider,
        ),
        receiver: new ethers.Wallet(
            "0x0000000000000000000000000000000000000000000000000000000000000002",
            ethers.provider,
        ),
        maker: new ethers.Wallet(
            "0x0000000000000000000000000000000000000000000000000000000000000003",
            ethers.provider,
        ),
        operator: new ethers.Wallet(
            "0x0000000000000000000000000000000000000000000000000000000000000004",
            ethers.provider,
        ),
    }

    let makerProxy: MarketMakerProxy
    let permanentStorage: PermanentStorage
    let userProxy: UserProxy
    let allowanceTarget: AllowanceTarget, spender: Spender
    let pmm: PMM

    let snapshot: Snapshot

    beforeEach(async () => {
        await resetHardhatFork(config.networks.hardhat.forking?.blockNumber!)

        const [defaultAccount, upgradeAdmin] = await ethers.getSigners()
        // Add all account's ETH balance
        for (const account of Object.values(wallet)) {
            await ETH(100).from(defaultAccount).transferTo(account)
        }

        // Deploy permanent storage
        permanentStorage = (await deployPermanentStorage(
            upgradeAdmin.address,
            wallet.operator.address,
        )) as PermanentStorage

        // Deploy Tokenlon
        userProxy = (await deployTokenlon(
            upgradeAdmin.address,
            wallet.operator.address,
        )) as UserProxy

        // Deploy Spender
        spender = (await (
            await ethers.getContractFactory("Spender")
        ).deploy(wallet.operator.address, addr.CONSUME_GAS_ERC20Addrs)) as Spender

        // Deploy AllowanceTarget
        allowanceTarget = (await (
            await ethers.getContractFactory("AllowanceTarget")
        ).deploy(spender.address)) as AllowanceTarget
        // Set AllowanceTarget address on spender
        await spender.connect(wallet.operator).setAllowanceTarget(allowanceTarget.address)

        // Deploy pmm
        const pmmFactory = await ethers.getContractFactory("PMM")
        pmm = (await pmmFactory.deploy(
            wallet.operator.address,
            userProxy.address,
            spender.address,
            permanentStorage.address,
            zxExchangeAddr,
            zxERC20ProxyAddr,
        )) as PMM
        await userProxy.connect(wallet.operator).upgradePMM(pmm.address, true)

        // Add pmm to authorized list in Spender
        await spender.connect(wallet.operator).authorize([pmm.address])

        // Add pmm to permanent storage roles
        await permanentStorage.connect(wallet.operator).upgradePMM(pmm.address)

        // Deploy market maker proxy and set up
        makerProxy = (await (
            await ethers.getContractFactory("MarketMakerProxy", wallet.maker)
        ).deploy()) as MarketMakerProxy
        await makerProxy.setSigner(wallet.maker.address)
        await makerProxy.setWithdrawer(wallet.maker.address)
        await makerProxy.setConfig(addr.WETH_ADDR)
        await makerProxy.registerWithdrawWhitelist(wallet.maker.address, true)

        for (const TKN of [DAI, SUSHI, USDC, USDT, WETH]) {
            // Add user, maker and maker proxy's token balance
            await TKN(10000).setBalanceFor(wallet.user)
            await TKN(10000).setBalanceFor(wallet.maker)
            await TKN(1000).setBalanceFor(makerProxy.address)
            // User approve AllowanceTarget to transfer from their assets
            await TKN.approveMax(wallet.user, allowanceTarget)
            // EOA maker approve zx ERC20 Proxy
            await TKN.approveMax(wallet.maker, zxERC20ProxyAddr)
        }

        // Maker proxy approve zx ERC20 proxy
        await makerProxy.setAllowance(
            [DAI.address, SUSHI.address, USDC.address, USDT.address, WETH.address],
            zxERC20ProxyAddr,
        )

        snapshot = await Snapshot.take()

        await snapshot.reset()
    })

    describe("Contract setup", () => {
        it("Should have correct setup for PMM", async () => {
            expect(addressIsEqual(await pmm.operator(), wallet.operator.address)).to.be.true
            expect(addressIsEqual(await pmm.userProxy(), userProxy.address)).to.be.true
            expect(addressIsEqual(await pmm.spender(), spender.address)).to.be.true
            expect(addressIsEqual(await pmm.zeroExchange(), zxExchangeAddr)).to.be.true
            expect(addressIsEqual(await pmm.zxERC20Proxy(), zxERC20ProxyAddr)).to.be.true
            expect(addressIsEqual(await userProxy.pmmAddr(), pmm.address)).to.be.true
            expect(await spender.isAuthorized(pmm.address)).to.be.true
            expect(addressIsEqual(await permanentStorage.pmmAddr(), pmm.address)).to.be.true
        })

        it("Should have correct setup for MakerProxy", async () => {
            expect(addressIsEqual(await makerProxy.SIGNER(), wallet.maker.address)).to.be.true
            expect(addressIsEqual(await makerProxy.withdrawer(), wallet.maker.address)).to.be.true
            expect(addressIsEqual(await makerProxy.WETH_ADDR(), WETH.address)).to.be.true
            expect(await makerProxy.isWithdrawWhitelist(wallet.maker.address)).to.be.true
        })
    })

    describe("Operator functions", () => {
        it(`Should fail to set/close allowance by non-operator`, async () => {
            // Set allowance
            const spenderAddr = wallet.user.address
            await expect(
                pmm.connect(wallet.user).setAllowance([addr.DAI_ADDR], spenderAddr),
            ).to.be.revertedWith("PMM: not operator")

            // Close allowance
            await expect(
                pmm.connect(wallet.user).closeAllowance([addr.DAI_ADDR], spenderAddr),
            ).to.be.revertedWith("PMM: not operator")
        })

        it(`Should set/close allowance`, async () => {
            // Set allowance
            const spenderAddr = wallet.user.address
            await pmm.connect(wallet.operator).setAllowance([addr.DAI_ADDR], spenderAddr)
            expect(await DAI.allowanceOf(pmm.address, spenderAddr)).to.equal(
                ethers.constants.MaxUint256,
            )

            // Close allowance
            await pmm.connect(wallet.operator).closeAllowance([addr.DAI_ADDR], spenderAddr)
            expect(await DAI.allowanceOf(pmm.address, spenderAddr)).to.equal(0)
        })
    })

    describe("Market maker proxy", () => {
        it(`Should verify maker signature`, async () => {
            const orderHash = "0x" + crypto.randomBytes(32).toString("hex")
            const hashArray = ethers.utils.arrayify(orderHash)
            const sig = await wallet.maker.signMessage(hashArray)
            const splitSig = ethers.utils.splitSignature(sig)
            const reorgSig =
                (splitSig.v == 27 ? "1b" : "1c") + splitSig.r.slice(2) + splitSig.s.slice(2)
            const tokenlonV4Sig = "0x" + reorgSig
            await makerProxy.callStatic.isValidSignature(orderHash, tokenlonV4Sig)
        })

        describe("Withdrawals", () => {
            it(`Should maker withdraw 100 DAI`, async () => {
                const makerProxyDaiBalanceBefore = await DAI.balanceOf(makerProxy.address)
                const makerDaiBalanceBefore = await DAI.balanceOf(wallet.maker.address)
                await makerProxy
                    .connect(wallet.maker)
                    .withdraw(DAI.address, wallet.maker.address, ethers.utils.parseUnits("100"))
                const makerProxyDaiBalanceAfter = await DAI.balanceOf(makerProxy.address)
                const makerDaiBalanceAfter = await DAI.balanceOf(wallet.maker.address)
                expect(makerDaiBalanceAfter.sub(makerDaiBalanceBefore)).eq(
                    ethers.utils.parseUnits("100"),
                )
                expect(makerProxyDaiBalanceBefore.sub(makerProxyDaiBalanceAfter)).eq(
                    ethers.utils.parseUnits("100"),
                )
            })

            it(`Should maker withdraw 10 ETH`, async () => {
                const makerProxyWethBalanceBefore = await WETH.balanceOf(makerProxy.address)
                const makerEthBalanceBefore = await wallet.maker.getBalance()
                await makerProxy
                    .connect(wallet.maker)
                    .withdraw(WETH.address, wallet.maker.address, ethers.utils.parseUnits("10"))
                const makerProxyWethBalanceAfter = await WETH.balanceOf(makerProxy.address)
                const makerEthBalanceAfter = await wallet.maker.getBalance()
                expect(makerEthBalanceAfter.sub(makerEthBalanceBefore)).gt(
                    ethers.utils.parseUnits("9"),
                )
                expect(makerProxyWethBalanceBefore.sub(makerProxyWethBalanceAfter)).eq(
                    ethers.utils.parseUnits("10"),
                )
            })

            it(`Should fail to withdraw if a non-maker try to call withdraw/withdrawETH`, async () => {
                await expect(
                    makerProxy
                        .connect(wallet.user)
                        .withdraw(DAI.address, wallet.maker.address, ethers.utils.parseUnits("10")),
                ).to.be.revertedWith("MarketMakerProxy: only contract withdrawer")

                await expect(
                    makerProxy
                        .connect(wallet.user)
                        .withdrawETH(wallet.maker.address, ethers.utils.parseUnits("1")),
                ).to.be.revertedWith("MarketMakerProxy: only contract withdrawer")
            })
        })
    })

    describe("Fill", () => {
        it(`Should fill 1 ETH(712 sig user) <-> 100 USDT(wallet type MMP) order (user transaction) & receive fee`, async () => {
            const userUsdtBalanceBefore = await USDT.balanceOf(wallet.user.address)
            const makerProxyWethBalanceBefore = await WETH.balanceOf(makerProxy.address)
            const pmmUsdtFeeBalanceBefore = await USDT.balanceOf(pmm.address)
            const order = {
                takerAddress: pmm.address.toLowerCase(),
                takerFee: 0,
                takerAssetData: assetDataUtils.encodeERC20AssetData(addr.WETH_ADDR.toLowerCase()),
                takerAssetAmount: new BigNumber(1 * Math.pow(10, 18)),

                makerAddress: makerProxy.address.toLowerCase(),
                makerAssetData: assetDataUtils.encodeERC20AssetData(addr.USDT_ADDR.toLowerCase()),
                makerAssetAmount: new BigNumber(100 * Math.pow(10, 6)),
                makerFee: 0,

                senderAddress: pmm.address.toLowerCase(),
                feeRecipientAddress: wallet.user.address.toLowerCase(),
                expirationTimeSeconds: DEFAULT_EXPIRY,
                exchangeAddress: zxExchangeAddr.toLowerCase(),
            }

            const signedOrder = await signOrder(order, wallet.maker, FEE_FACTOR)
            const signedTx = await signTx(
                contractWrappers(
                    getWalletFromPrv(wallet.user.privateKey.slice(2)),
                    zxExchangeAddr,
                    zxERC20ProxyAddr,
                ),
                signedOrder,
                wallet.user.address,
                wallet.user,
            )

            const payload = pmm.interface.encodeFunctionData("fill", [
                ethers.utils.parseUnits(signedTx.salt.toString(), 0),
                signedTx.fillData,
                signedTx.signature,
            ])
            const tx = await userProxy
                .connect(wallet.user)
                .toPMM(payload, { value: ethers.utils.parseUnits("1") })
            const receipt = await tx.wait()
            console.log(`Gas used by PMM.fill: ${receipt.gasUsed.toString()}`)

            const userUsdtBalanceAfter = await USDT.balanceOf(wallet.user.address)
            const makerProxyWethBalanceAfter = await WETH.balanceOf(makerProxy.address)
            const pmmUsdtFeeBalanceAfter = await USDT.balanceOf(pmm.address)
            expect(userUsdtBalanceAfter.sub(userUsdtBalanceBefore)).eq(
                ethers.utils.parseUnits("99.7", "mwei"),
            )
            expect(makerProxyWethBalanceAfter.sub(makerProxyWethBalanceBefore)).eq(
                ethers.utils.parseUnits("1"),
            )
            expect(pmmUsdtFeeBalanceAfter.sub(pmmUsdtFeeBalanceBefore)).eq(
                ethers.utils.parseUnits("0.3", "mwei"),
            )
        })

        it(`Should fill 100 DAI(712 sig user) <-> 100 USDC(EOA market maker) order & receive fee`, async () => {
            const userUsdcBalanceBefore = await USDC.balanceOf(wallet.user.address)
            const makerDaiBalanceBefore = await DAI.balanceOf(wallet.maker.address)
            const pmmUsdcFeeBalanceBefore = await USDC.balanceOf(pmm.address)
            const order = {
                takerAddress: pmm.address.toLowerCase(),
                takerFee: 0,
                takerAssetData: assetDataUtils.encodeERC20AssetData(addr.DAI_ADDR.toLowerCase()),
                takerAssetAmount: new BigNumber(100 * Math.pow(10, 18)),

                makerAddress: wallet.maker.address.toLowerCase(),
                makerAssetData: assetDataUtils.encodeERC20AssetData(addr.USDC_ADDR.toLowerCase()),
                makerAssetAmount: new BigNumber(100 * Math.pow(10, 6)),
                makerFee: 0,

                senderAddress: pmm.address.toLowerCase(),
                feeRecipientAddress: wallet.user.address.toLowerCase(),
                expirationTimeSeconds: DEFAULT_EXPIRY,
                exchangeAddress: zxExchangeAddr.toLowerCase(),
            }

            const signedOrder = await signEoaOrder(order, wallet.maker, FEE_FACTOR)

            const signedTx = await signTx(
                contractWrappers(
                    getWalletFromPrv(wallet.user.privateKey.slice(2)),
                    zxExchangeAddr,
                    zxERC20ProxyAddr,
                ),
                signedOrder,
                wallet.user.address,
                wallet.user,
            )
            const payload = pmm.interface.encodeFunctionData("fill", [
                ethers.utils.parseUnits(signedTx.salt.toString(), 0),
                signedTx.fillData,
                signedTx.signature,
            ])
            const tx = await userProxy.toPMM(payload)
            const receipt = await tx.wait()
            console.log(`Gas used by PMM.fill: ${receipt.gasUsed.toString()}`)

            const userUsdcBalanceAfter = await USDC.balanceOf(wallet.user.address)
            const makerDaiBalanceAfter = await DAI.balanceOf(wallet.maker.address)

            const pmmUsdcFeeBalanceAfter = await USDC.balanceOf(pmm.address)

            expect(userUsdcBalanceAfter.sub(userUsdcBalanceBefore)).eq(
                ethers.utils.parseUnits("99.7", "mwei"),
            )
            expect(makerDaiBalanceAfter.sub(makerDaiBalanceBefore)).eq(
                ethers.utils.parseUnits("100"),
            )
            expect(pmmUsdcFeeBalanceAfter.sub(pmmUsdcFeeBalanceBefore)).eq(
                ethers.utils.parseUnits("0.3", "mwei"),
            )
        })

        it(`Should fill 100 DAI(712 sig user) <-> 100 USDC(712 market maker) order & receive fee`, async () => {
            const userUsdcBalanceBefore = await USDC.balanceOf(wallet.user.address)
            const makerDaiBalanceBefore = await DAI.balanceOf(wallet.maker.address)
            const pmmUsdcFeeBalanceBefore = await USDC.balanceOf(pmm.address)
            const order = {
                takerAddress: pmm.address.toLowerCase(),
                takerFee: 0,
                takerAssetData: assetDataUtils.encodeERC20AssetData(addr.DAI_ADDR.toLowerCase()),
                takerAssetAmount: new BigNumber(100 * Math.pow(10, 18)),

                makerAddress: wallet.maker.address.toLowerCase(),
                makerAssetData: assetDataUtils.encodeERC20AssetData(addr.USDC_ADDR.toLowerCase()),
                makerAssetAmount: new BigNumber(100 * Math.pow(10, 6)),
                makerFee: 0,

                senderAddress: pmm.address.toLowerCase(),
                feeRecipientAddress: wallet.user.address.toLowerCase(),
                expirationTimeSeconds: DEFAULT_EXPIRY,
                exchangeAddress: zxExchangeAddr.toLowerCase(),
            }

            const signedOrder = await sign712Order(order, wallet.maker, FEE_FACTOR)

            const signedTx = await signTx(
                contractWrappers(
                    getWalletFromPrv(wallet.user.privateKey.slice(2)),
                    zxExchangeAddr,
                    zxERC20ProxyAddr,
                ),
                signedOrder,
                wallet.user.address,
                wallet.user,
            )
            const payload = pmm.interface.encodeFunctionData("fill", [
                ethers.utils.parseUnits(signedTx.salt.toString(), 0),
                signedTx.fillData,
                signedTx.signature,
            ])
            const tx = await userProxy.toPMM(payload)
            const receipt = await tx.wait()
            console.log(`Gas used by PMM.fill: ${receipt.gasUsed.toString()}`)

            const userUsdcBalanceAfter = await USDC.balanceOf(wallet.user.address)
            const makerDaiBalanceAfter = await DAI.balanceOf(wallet.maker.address)

            const pmmUsdcFeeBalanceAfter = await USDC.balanceOf(pmm.address)

            expect(userUsdcBalanceAfter.sub(userUsdcBalanceBefore)).eq(
                ethers.utils.parseUnits("99.7", "mwei"),
            )
            expect(makerDaiBalanceAfter.sub(makerDaiBalanceBefore)).eq(
                ethers.utils.parseUnits("100"),
            )
            expect(pmmUsdcFeeBalanceAfter.sub(pmmUsdcFeeBalanceBefore)).eq(
                ethers.utils.parseUnits("0.3", "mwei"),
            )
        })
    })

    async function deployPermanentStorage(proxyAdmin: string, logicOperator: string) {
        const pStorageLogic = await (await ethers.getContractFactory("PermanentStorage")).deploy()

        const proxyPermanentStorage = await (
            await ethers.getContractFactory("ProxyPermanentStorage")
        ).deploy(pStorageLogic.address, proxyAdmin, "0x")

        // Set operator address
        await setStorageAt(
            proxyPermanentStorage.address,
            "0x0",
            ethers.utils.hexZeroPad(logicOperator, 32),
        )

        const wrappedContract = await ethers.getContractAt(
            "PermanentStorage",
            proxyPermanentStorage.address,
        )
        return wrappedContract
    }

    async function deployTokenlon(proxyAdmin: string, logicOperator: string) {
        const userProxyLogic = await (await ethers.getContractFactory("UserProxy")).deploy()

        const tokenlon = await (
            await ethers.getContractFactory("Tokenlon")
        ).deploy(userProxyLogic.address, proxyAdmin, "0x")

        // Set operator address
        await setStorageAt(tokenlon.address, "0x0", ethers.utils.hexZeroPad(logicOperator, 32))

        const wrappedContract = await ethers.getContractAt("UserProxy", tokenlon.address)
        return wrappedContract
    }

    function addressIsEqual(a: string, b: string) {
        return ethers.utils.getAddress(a) === ethers.utils.getAddress(b)
    }
})
