// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { AllowFill } from "contracts/libraries/AllowFill.sol";
import { GenericSwapData } from "contracts/libraries/GenericSwapData.sol";
import { LimitOrder } from "contracts/libraries/LimitOrder.sol";
import { RFQOffer } from "contracts/libraries/RFQOffer.sol";
import { SigHelper } from "test/utils/SigHelper.sol";

contract testEIP712Signing is SigHelper {
    address allowanceTarget = 0x7C0016dD693494325EB6CAfE5Abef0352EA5841e;
    address genericSwap = 0xf604B9934098C3B8475B63d9E368FF1ACdC5f7B7;
    address smartOrderStrategy = 0x979e18D403Cd3578b38aC2C7f25EAA9BA3cE58eE;
    address uniAgent = 0x41900DAded4C563Cfdba9181bF5CE4C3cd0eDd37;
    address limitOrderSwap = 0x53377C5397B61f4257818214C19FA2Dd418B160D;
    address coordinatedTaker = 0x6597f1509e7592C24c05e9354DC438f9287dFd5b;
    address feeCollector = 0xa12069fD34471AB7fca6f9d305d11D74458D9337;

    function testAllowFillSigning() public {
        string memory allowFillPayloadJson = vm.readFile("test/forkGoerli/config/allowFill.json");

        AllowFill memory allowFill = AllowFill(
            abi.decode(vm.parseJson(allowFillPayloadJson, "$.orderHash"), (bytes32)),
            abi.decode(vm.parseJson(allowFillPayloadJson, "$.taker"), (address)),
            abi.decode(vm.parseJson(allowFillPayloadJson, "$.fillAmount"), (uint256)),
            abi.decode(vm.parseJson(allowFillPayloadJson, "$.expiry"), (uint256)),
            abi.decode(vm.parseJson(allowFillPayloadJson, "$.salt"), (uint256))
        );
        uint256 signingKey = abi.decode(vm.parseJson(allowFillPayloadJson, "$.signingKey"), (uint256));
        bytes memory sig = signAllowFill(signingKey, allowFill, coordinatedTaker);

        bytes memory expectedSig = abi.decode(vm.parseJson(allowFillPayloadJson, "$.expectedSig"), (bytes));
        assertEq(sig, expectedSig);
    }

    function testGenericSwapSigning() public {
        string memory genericSwapDataPayloadJson = vm.readFile("test/forkGoerli/config/genericSwapData.json");

        GenericSwapData memory genericSwapData = GenericSwapData(
            abi.decode(vm.parseJson(genericSwapDataPayloadJson, "$.maker"), (address)),
            abi.decode(vm.parseJson(genericSwapDataPayloadJson, "$.takerToken"), (address)),
            abi.decode(vm.parseJson(genericSwapDataPayloadJson, "$.takerTokenAmount"), (uint256)),
            abi.decode(vm.parseJson(genericSwapDataPayloadJson, "$.makerToken"), (address)),
            abi.decode(vm.parseJson(genericSwapDataPayloadJson, "$.makerTokenAmount"), (uint256)),
            abi.decode(vm.parseJson(genericSwapDataPayloadJson, "$.minMakerTokenAmount"), (uint256)),
            abi.decode(vm.parseJson(genericSwapDataPayloadJson, "$.expiry"), (uint256)),
            abi.decode(vm.parseJson(genericSwapDataPayloadJson, "$.salt"), (uint256)),
            abi.decode(vm.parseJson(genericSwapDataPayloadJson, "$.recipient"), (address)),
            abi.decode(vm.parseJson(genericSwapDataPayloadJson, "$.strategyData"), (bytes))
        );
        uint256 signingKey = abi.decode(vm.parseJson(genericSwapDataPayloadJson, "$.signingKey"), (uint256));
        bytes memory sig = signGenericSwap(signingKey, genericSwapData, genericSwap);

        bytes memory expectedSig = abi.decode(vm.parseJson(genericSwapDataPayloadJson, "$.expectedSig"), (bytes));
        assertEq(sig, expectedSig);
    }

    function testLimitOrderSigning() public {
        string memory limitOrderPayloadJson = vm.readFile("test/forkGoerli/config/limitOrder.json");

        LimitOrder memory limitOrder = LimitOrder(
            abi.decode(vm.parseJson(limitOrderPayloadJson, "$.taker"), (address)),
            abi.decode(vm.parseJson(limitOrderPayloadJson, "$.maker"), (address)),
            abi.decode(vm.parseJson(limitOrderPayloadJson, "$.takerToken"), (address)),
            abi.decode(vm.parseJson(limitOrderPayloadJson, "$.takerTokenAmount"), (uint256)),
            abi.decode(vm.parseJson(limitOrderPayloadJson, "$.makerToken"), (address)),
            abi.decode(vm.parseJson(limitOrderPayloadJson, "$.makerTokenAmount"), (uint256)),
            abi.decode(vm.parseJson(limitOrderPayloadJson, "$.makerTokenPermit"), (bytes)),
            abi.decode(vm.parseJson(limitOrderPayloadJson, "$.feeFactor"), (uint256)),
            abi.decode(vm.parseJson(limitOrderPayloadJson, "$.expiry"), (uint256)),
            abi.decode(vm.parseJson(limitOrderPayloadJson, "$.salt"), (uint256))
        );

        uint256 signingKey = abi.decode(vm.parseJson(limitOrderPayloadJson, "$.signingKey"), (uint256));
        bytes memory sig = signLimitOrder(signingKey, limitOrder, limitOrderSwap);

        bytes memory expectedSig = abi.decode(vm.parseJson(limitOrderPayloadJson, "$.expectedSig"), (bytes));
        assertEq(sig, expectedSig);
    }
}
