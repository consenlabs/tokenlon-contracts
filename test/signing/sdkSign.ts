import assert from "assert"
import fs from "fs"
import path from "path"
import { getDefaultProvider, Wallet } from "ethers"
import { SignatureType } from "@tokenlon/contracts-lib/signing"
import { AMMOrder, RFQFill, RFQOrder, signingHelper } from "@tokenlon/contracts-lib/v5"

const CHAIN_ID = 1
const AmmWrapperPath = path.join(__dirname, "./payload/ammWrapper.json")
const ammWrapperPayloadJson = JSON.parse(fs.readFileSync(AmmWrapperPath).toString())
const RFQPath = path.join(__dirname, "./payload/rfq.json")
const rfqPayloadJson = JSON.parse(fs.readFileSync(RFQPath).toString())

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

async function main() {
    const signer = new Wallet(ammWrapperPayloadJson.signingKey, getDefaultProvider("mainnet"))
    assert((await signer.getChainId()) == CHAIN_ID, `Must sign with chain ID ${CHAIN_ID}`)

    await signAMMOrder(signer)
    await signRFQOrderAndFill(signer)
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error)
        process.exit(1)
    })
