// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

string constant GS_DATA_TYPESTRING = string(
    abi.encodePacked(
        "GenericSwapData(address maker,address takerToken,uint256 takerTokenAmount,address makerToken,uint256 makerTokenAmount,uint256 minMakerTokenAmount,uint256 expiry,uint256 salt,address recipient,bytes strategyData)"
    )
);

bytes32 constant GS_DATA_TYPEHASH = 0x1b6f9d7673107802b331a5ab52a40f7d942bdf74fa821744df8b69eead3d26c1;
// keccak256(GS_DATA_TYPESTRING);

struct GenericSwapData {
    address payable maker;
    address takerToken;
    uint256 takerTokenAmount;
    address makerToken;
    uint256 makerTokenAmount;
    uint256 minMakerTokenAmount;
    uint256 expiry;
    uint256 salt;
    address payable recipient;
    bytes strategyData;
}

// solhint-disable-next-line func-visibility
function getGSDataHash(GenericSwapData memory gsData) pure returns (bytes32) {
    return
        keccak256(
            abi.encode(
                GS_DATA_TYPEHASH,
                gsData.maker,
                gsData.takerToken,
                gsData.takerTokenAmount,
                gsData.makerToken,
                gsData.makerTokenAmount,
                gsData.minMakerTokenAmount,
                gsData.expiry,
                gsData.salt,
                gsData.recipient,
                keccak256(gsData.strategyData)
            )
        );
}
