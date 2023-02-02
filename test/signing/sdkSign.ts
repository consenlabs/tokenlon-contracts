import assert from "assert"
import fs from "fs"
import path from "path"
import { getDefaultProvider, Wallet } from "ethers"
import { SignatureType } from "@tokenlon/contracts-lib/signing"
import {
    AMMOrder,
    LimitOrder,
    LimitOrderAllowFill,
    LimitOrderFill,
    RFQFill,
    RFQOrder,
    signingHelper,
} from "@tokenlon/contracts-lib/v5"

const CHAIN_ID = 1
const AmmWrapperPath = path.join(__dirname, "./payload/ammWrapper.json")
const ammWrapperPayloadJson = JSON.parse(fs.readFileSync(AmmWrapperPath).toString())
const RFQPath = path.join(__dirname, "./payload/rfq.json")
const rfqPayloadJson = JSON.parse(fs.readFileSync(RFQPath).toString())
const LimitOrderPath = path.join(__dirname, "./payload/limitOrder.json")
const limitOrderPayloadJson = JSON.parse(fs.readFileSync(LimitOrderPath).toString())
const L2DepositPath = path.join(__dirname, "./payload/l2Deposit.json")
const l2DepositPayloadJson = JSON.parse(fs.readFileSync(L2DepositPath).toString())

async function signAMMOrder(signer: Wallet) {
    const ammOrder: AMMOrder = {
        makerAddr: ammWrapperPayloadJson.makerAddr,
        takerAssetAddr: ammWrapperPayloadJson.takerAssetAddr,
        makerAssetAddr: ammWrapperPayloadJson.makerAssetAddr,
        takerAssetAmount: ammWrapperPayloadJson.takerAssetAmount,
        makerAssetAmount: ammWrapperPayloadJson.makerAssetAmount,
        userAddr: ammWrapperPayloadJson.userAddr,
        receiverAddr: ammWrapperPayloadJson.receiverAddr,
        salt: ammWrapperPayloadJson.salt,
        deadline: ammWrapperPayloadJson.deadline,
    }
    const ammOrderSig = await signingHelper.signAMMOrder(ammOrder, {
        type: SignatureType.EIP712,
        signer: signer,
        verifyingContract: ammWrapperPayloadJson.AMMWrapper,
    })
    ammWrapperPayloadJson["expectedSig"] = ammOrderSig

    fs.writeFileSync(AmmWrapperPath, JSON.stringify(ammWrapperPayloadJson, null, 2))
}

async function signRFQOrderAndFill(signer: Wallet) {
    const rfqOrder: RFQOrder = {
        takerAddr: rfqPayloadJson.takerAddr,
        makerAddr: rfqPayloadJson.makerAddr,
        takerAssetAddr: rfqPayloadJson.takerAssetAddr,
        makerAssetAddr: rfqPayloadJson.makerAssetAddr,
        takerAssetAmount: rfqPayloadJson.takerAssetAmount,
        makerAssetAmount: rfqPayloadJson.makerAssetAmount,
        salt: rfqPayloadJson.salt,
        deadline: rfqPayloadJson.deadline,
        feeFactor: rfqPayloadJson.feeFactor,
    }
    const rfqOrderSig = await signingHelper.signRFQOrder(rfqOrder, {
        type: SignatureType.EIP712,
        signer: signer,
        verifyingContract: rfqPayloadJson.RFQ,
    })
    rfqPayloadJson["expectedOrderSig"] = rfqOrderSig

    const rfqFill: RFQFill = { ...rfqOrder, receiverAddr: rfqPayloadJson.receiverAddr }
    const rfqFillSig = await signingHelper.signRFQFillOrder(rfqFill, {
        type: SignatureType.EIP712,
        signer: signer,
        verifyingContract: rfqPayloadJson.RFQ,
    })
    rfqPayloadJson["expectedFillSig"] = rfqFillSig

    fs.writeFileSync(RFQPath, JSON.stringify(rfqPayloadJson, null, 2))
}

async function signLimitOrderOrderAndFill(signer: Wallet) {
    const limitOrder: LimitOrder = {
        makerToken: limitOrderPayloadJson.makerToken,
        takerToken: limitOrderPayloadJson.takerToken,
        makerTokenAmount: limitOrderPayloadJson.makerTokenAmount,
        takerTokenAmount: limitOrderPayloadJson.takerTokenAmount,
        maker: limitOrderPayloadJson.maker,
        taker: limitOrderPayloadJson.taker,
        salt: limitOrderPayloadJson.salt,
        expiry: limitOrderPayloadJson.expiry,
    }
    const limitOrderSig = await signingHelper.signLimitOrder(limitOrder, {
        type: SignatureType.EIP712,
        signer: signer,
        verifyingContract: limitOrderPayloadJson.LimitOrder,
    })
    limitOrderPayloadJson["expectedOrderSig"] = limitOrderSig
    const orderHash = await signingHelper.getLimitOrderEIP712Digest(limitOrder, {
        chainId: CHAIN_ID,
        verifyingContract: limitOrderPayloadJson.LimitOrder,
    })

    const limitOrderFill: LimitOrderFill = {
        orderHash: orderHash,
        taker: limitOrder.taker,
        recipient: limitOrderPayloadJson.recipient,
        takerTokenAmount: limitOrder.takerTokenAmount,
        takerSalt: limitOrder.salt,
        expiry: limitOrder.expiry,
    }
    const limitOrderFillSig = await signingHelper.signLimitOrderFill(limitOrderFill, {
        type: SignatureType.EIP712,
        signer: signer,
        verifyingContract: limitOrderPayloadJson.LimitOrder,
    })
    limitOrderPayloadJson["expectedFillSig"] = limitOrderFillSig

    const limitOrderAllowFill: LimitOrderAllowFill = {
        orderHash: orderHash,
        executor: limitOrder.taker,
        fillAmount: limitOrder.takerTokenAmount,
        salt: limitOrder.salt,
        expiry: limitOrder.expiry,
    }
    const limitOrderAllowFillSig = await signingHelper.signLimitOrderAllowFill(
        limitOrderAllowFill,
        {
            type: SignatureType.EIP712,
            signer: signer,
            verifyingContract: limitOrderPayloadJson.LimitOrder,
        },
    )
    limitOrderPayloadJson["expectedAllowFillSig"] = limitOrderAllowFillSig

    fs.writeFileSync(LimitOrderPath, JSON.stringify(limitOrderPayloadJson, null, 2))
}

async function signL2Deposit(signer: Wallet) {
    const deposit = {
        l2Identifier: l2DepositPayloadJson.l2Identifier,
        l1TokenAddr: l2DepositPayloadJson.l1TokenAddr,
        l2TokenAddr: l2DepositPayloadJson.l2TokenAddr,
        sender: l2DepositPayloadJson.sender,
        recipient: l2DepositPayloadJson.recipient,
        amount: l2DepositPayloadJson.amount,
        salt: l2DepositPayloadJson.salt,
        expiry: l2DepositPayloadJson.expiry,
        data: l2DepositPayloadJson.data,
    }
    const EIP712Types = {
        Deposit: [
            { name: "l2Identifier", type: "uint8" },
            { name: "l1TokenAddr", type: "address" },
            { name: "l2TokenAddr", type: "address" },
            { name: "sender", type: "address" },
            { name: "recipient", type: "address" },
            { name: "amount", type: "uint256" },
            { name: "salt", type: "uint256" },
            { name: "expiry", type: "uint256" },
            { name: "data", type: "bytes" },
        ],
    }
    const EIP712Domain = {
        name: "Tokenlon",
        version: "v5",
        chainId: CHAIN_ID,
        verifyingContract: l2DepositPayloadJson.L2Deposit,
    }
    const l2DepositRawSig = await signer._signTypedData(EIP712Domain, EIP712Types, deposit)
    const l2DepositSig = l2DepositRawSig + "00".repeat(32) + SignatureType.EIP712
    l2DepositPayloadJson["expectedSig"] = l2DepositSig

    fs.writeFileSync(L2DepositPath, JSON.stringify(l2DepositPayloadJson, null, 2))
}

async function main() {
    const signer = new Wallet(ammWrapperPayloadJson.signingKey, getDefaultProvider("mainnet"))
    assert((await signer.getChainId()) == CHAIN_ID, `Must sign with chain ID ${CHAIN_ID}`)

    await signAMMOrder(signer)
    await signRFQOrderAndFill(signer)
    await signLimitOrderOrderAndFill(signer)
    await signL2Deposit(signer)
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error)
        process.exit(1)
    })
