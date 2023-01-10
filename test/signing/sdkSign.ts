import assert from "assert"
import fs from "fs"
import path from "path"
import { getDefaultProvider, Wallet } from "ethers"
import { SignatureType } from "@tokenlon/contracts-lib/signing"
import { AMMOrder, signingHelper } from "@tokenlon/contracts-lib/v5"

const AmmWrapperPath = path.join(__dirname, "./payload/ammWrapper.json")
const ammWrapperPayloadJson = JSON.parse(fs.readFileSync(AmmWrapperPath).toString())
const CHAIN_ID = 1

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

async function main() {
    const signer = new Wallet(ammWrapperPayloadJson.signingKey, getDefaultProvider("mainnet"))
    assert((await signer.getChainId()) == CHAIN_ID, `Must sign with chain ID ${CHAIN_ID}`)

    await signAMMOrder(signer)
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error)
        process.exit(1)
    })
