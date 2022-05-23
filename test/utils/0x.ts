import { ethers } from "hardhat"
import { PrivateKeyWalletSubprovider } from "@0x/subproviders"
import { getContractAddressesForNetworkOrThrow } from "@0x/contract-addresses"
import { getChainId } from "./providerUtils"
import {
    generatePseudoRandomSalt,
    orderHashUtils,
    signatureUtils,
    SignatureType,
    RPCSubprovider,
    Web3ProviderEngine,
    ContractWrappers,
    ContractAddresses,
    BigNumber,
} from "0x.js"

const EthUtils = require("ethereumjs-util")
const providerUrl = "http://127.0.0.1:8545"

export const getDomainSeparator = async () => {
    const chainId = await getChainId()
    let exchangeAddress = ""
    if (chainId === 1) {
        exchangeAddress = "0x080bf510FCbF18b91105470639e9561022937712"
    } else if (chainId === 5) {
        exchangeAddress = "0xb17DFeCAB333CAE320Fed9b84d8CADdc61F9A687"
    } else if (chainId === 42) {
        exchangeAddress = "0x30589010550762d2f0d06f650D8e8B6Ade6DBf4b"
    } else {
        throw new Error("Unsupported network")
    }

    // Hash of the EIP712 Domain Separator Schema
    const ZEROX_V2_EIP712_DOMAIN_SEPARATOR_SCHEMA_HASH = ethers.utils.keccak256(
        Buffer.concat([
            Buffer.from("EIP712Domain("),
            Buffer.from("string name,"),
            Buffer.from("string version,"),
            Buffer.from("address verifyingContract"),
            Buffer.from(")"),
        ]),
    )

    const ZEROX_V2_EIP712_DOMAIN_HASH = ethers.utils.keccak256(
        ethers.utils.solidityPack(
            ["bytes32", "bytes32", "bytes32", "bytes32"],
            [
                ZEROX_V2_EIP712_DOMAIN_SEPARATOR_SCHEMA_HASH,
                ethers.utils.keccak256(Buffer.from("0x Protocol")),
                ethers.utils.keccak256(Buffer.from("2")),
                "0x" + exchangeAddress.slice(2).padStart(64, "0"),
            ],
        ),
    )
    return ZEROX_V2_EIP712_DOMAIN_HASH
}

export const getWalletFromPrv = (privateKey: string) => {
    const provider = new Web3ProviderEngine()
    const wallet = new PrivateKeyWalletSubprovider(privateKey)

    provider.addProvider(wallet)
    provider.addProvider(new RPCSubprovider(providerUrl))
    provider.start()
    return provider
}

export const generateSaltWithFeeFactor = (feeFactor: BigNumber) => {
    const salt = generatePseudoRandomSalt()
    return salt
        .dividedToIntegerBy(2 ** 16)
        .multipliedBy(2 ** 16)
        .plus(feeFactor)
}

export const sign712Order = async (
    order: any,
    maker: any,
    feeFactor: BigNumber = new BigNumber(30),
) => {
    const o = {
        ...order,
        salt: generateSaltWithFeeFactor(feeFactor),
    }
    const EIP191_HEADER = "0x1901"
    // https://etherscan.io/address/0x080bf510fcbf18b91105470639e9561022937712#readContract
    const ZEROX_V2_EIP712_DOMAIN_SEPARATOR = await getDomainSeparator()
    // https://github.com/0xProject/0x-protocol-specification/blob/master/v2/v2-specification.md#hashing-an-order
    // "Order(address makerAddress,address takerAddress,address feeRecipientAddress,address senderAddress,uint256 makerAssetAmount,uint256 takerAssetAmount,uint256 makerFee,uint256 takerFee,uint256 expirationTimeSeconds,uint256 salt,bytes makerAssetData,bytes takerAssetData)"
    const ORDER_TYPEHASH = "0x770501f88a26ede5c04a20ef877969e961eb11fc13b78aaf414b633da0d4f86f"
    const orderHash = ethers.utils.keccak256(
        ethers.utils.solidityPack(
            ["bytes2", "bytes32", "bytes32"],
            [
                EIP191_HEADER,
                ZEROX_V2_EIP712_DOMAIN_SEPARATOR,
                ethers.utils.keccak256(
                    ethers.utils.defaultAbiCoder.encode(
                        [
                            "bytes32", // ORDER_TYPEHASH
                            "bytes32", // makerAddress
                            "bytes32", // takerAddress
                            "bytes32", // feeRecipientAddress
                            "bytes32", // senderAddress
                            "uint256", // makerAssetAmount
                            "uint256", // takerAssetAmount
                            "uint256", // makerFee
                            "uint256", // takerFee
                            "uint256", // expirationTimeSeconds
                            "uint256", // salt
                            "bytes32", // makerAssetData
                            "bytes32", // takerAssetData
                        ],
                        [
                            ORDER_TYPEHASH,
                            "0x" + o.makerAddress.slice(2).padStart(64, "0"),
                            "0x" + o.takerAddress.slice(2).padStart(64, "0"),
                            "0x" + o.feeRecipientAddress.slice(2).padStart(64, "0"),
                            "0x" + o.senderAddress.slice(2).padStart(64, "0"),
                            ethers.utils.parseUnits(o.makerAssetAmount.toString(), 0),
                            ethers.utils.parseUnits(o.takerAssetAmount.toString(), 0),
                            o.makerFee,
                            o.takerFee,
                            o.expirationTimeSeconds,
                            ethers.utils.parseUnits(o.salt.toString(), 0),
                            ethers.utils.keccak256(o.makerAssetData),
                            ethers.utils.keccak256(o.takerAssetData),
                        ],
                    ),
                ),
            ],
        ),
    )

    let signerSigningKey = new ethers.utils.SigningKey(maker.privateKey)
    const sig = signerSigningKey.signDigest(orderHash)
    // Signature type: 0x02 (EIP712)
    let eip712sig = `0x${sig.v.toString(16)}${sig.r.slice(2)}${sig.s.slice(2)}02`
    const signedOrder = {
        ...o,
        signature: eip712sig,
    }

    return signedOrder
}

export const signEoaOrder = async (
    order: any,
    maker: any,
    feeFactor: BigNumber = new BigNumber(30),
) => {
    const o = {
        ...order,
        salt: generateSaltWithFeeFactor(feeFactor),
    }
    const orderHash = orderHashUtils.getOrderHashHex(o)
    const hashArray = ethers.utils.arrayify(orderHash)
    let signature = await maker.signMessage(hashArray)
    signature = signature.slice(2)
    const v = signature.slice(signature.length - 2, signature.length)
    const rs = signature.slice(0, signature.length - 2)
    signature = "0x" + v + rs
    const eoaSignature = signatureUtils.convertToSignatureWithType(signature, SignatureType.EthSign)

    const signedOrder = {
        ...o,
        signature: eoaSignature,
    }

    return signedOrder
}

export const signOrder = async (
    order: any,
    maker: any,
    feeFactor: BigNumber = new BigNumber(30),
    signType = SignatureType.Wallet,
) => {
    const o = {
        ...order,
        salt: generateSaltWithFeeFactor(feeFactor),
    }
    const orderHash = orderHashUtils.getOrderHashHex(o)
    const hashArray = ethers.utils.arrayify(orderHash)
    let signature = await maker.signMessage(hashArray)
    signature = signature.slice(2)
    const v = signature.slice(signature.length - 2, signature.length)
    const rs = signature.slice(0, signature.length - 2)
    signature = "0x" + v + rs
    const walletSignature = signatureUtils.convertToSignatureWithType(signature, signType)
    const signedOrder = {
        ...o,
        signature: walletSignature,
    }

    return signedOrder
}

export const contractWrappers = (wallet: any, zxExchangeAddr: string, zxERC20ProxyAddr: string) => {
    const addresses = getContractAddressesForNetworkOrThrow(1)
    const contractAddresses: ContractAddresses = {
        ...addresses,
        exchange: zxExchangeAddr,
        erc20Proxy: zxERC20ProxyAddr,
    }
    const cws = new ContractWrappers(wallet, {
        networkId: 1,
        contractAddresses,
    })
    return cws
}

export const signTx = async (
    wrappedContract: any,
    signedOrder: any,
    receiverAddr: string,
    user: any,
) => {
    const transactionEncoder = await wrappedContract.exchange.transactionEncoderAsync()
    const fillData = transactionEncoder.fillOrKillOrderTx(signedOrder, signedOrder.takerAssetAmount)
    const takerTransactionSalt = generatePseudoRandomSalt()
    const EIP191_HEADER = "0x1901"
    const ZEROX_V2_EIP712_DOMAIN_SEPARATOR = await getDomainSeparator()
    // https://github.com/0xProject/0x-protocol-specification/blob/master/v2/v2-specification.md#hash-of-a-transaction
    // keccak256(ZeroExTransaction(uint256 salt,address signerAddress,bytes data))
    const ZEROEX_TRANSACTION_TYPEHASH =
        "0x213c6f636f3ea94e701c0adf9b2624aa45a6c694f9a292c094f9a81c24b5df4c"
    const executeTransactionHex = ethers.utils.keccak256(
        ethers.utils.solidityPack(
            ["bytes2", "bytes32", "bytes32"],
            [
                EIP191_HEADER,
                ZEROX_V2_EIP712_DOMAIN_SEPARATOR,
                ethers.utils.keccak256(
                    ethers.utils.defaultAbiCoder.encode(
                        [
                            "bytes32", // ZEROEX_TRANSACTION_TYPEHASH
                            "uint256", // salt
                            "bytes32", // signerAddress
                            "bytes32", // data
                        ],
                        [
                            ZEROEX_TRANSACTION_TYPEHASH,
                            ethers.utils.parseUnits(takerTransactionSalt.toString(), 0),
                            "0x" + signedOrder.takerAddress.slice(2).padStart(64, "0"),
                            ethers.utils.keccak256(fillData),
                        ],
                    ),
                ),
            ],
        ),
    )
    const hash = ethers.utils.keccak256(
        EthUtils.bufferToHex(
            Buffer.concat([
                EthUtils.toBuffer(executeTransactionHex),
                EthUtils.toBuffer(receiverAddr),
            ]),
        ),
    )
    const hashArray = ethers.utils.arrayify(hash)
    const signerSigningKey = new ethers.utils.SigningKey(user.privateKey)
    const sig = signerSigningKey.signDigest(hashArray)
    const { v, r, s } = ethers.utils.splitSignature(sig)
    const signature = `0x${v.toString(16)}${r.slice(2)}${s.slice(2)}`
    const sign712 = EthUtils.bufferToHex(
        Buffer.concat([EthUtils.toBuffer(signature), EthUtils.toBuffer(receiverAddr)]),
    )

    return {
        fillData: fillData,
        salt: takerTransactionSalt,
        signature: sign712,
    }
}
