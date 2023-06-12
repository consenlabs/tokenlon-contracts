// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";
import { Tokens } from "test/utils/Tokens.sol";
import { BalanceUtil } from "test/utils/BalanceUtil.sol";
import { getEIP712Hash } from "test/utils/Sig.sol";
import { BalanceSnapshot, Snapshot } from "test/utils/BalanceSnapshot.sol";
import { computeContractAddress } from "test/utils/Addresses.sol";
import { UniAgent } from "contracts/UniAgent.sol";
import { AllowanceTarget } from "contracts/AllowanceTarget.sol";
import { TokenCollector } from "contracts/abstracts/TokenCollector.sol";
import { Constant } from "contracts/libraries/Constant.sol";
import { IUniAgent } from "contracts/interfaces/IUniAgent.sol";
import { IWETH } from "contracts/interfaces/IWETH.sol";

contract UniAgentTest is Test, Tokens, BalanceUtil {
    uint256 userPrivateKey = uint256(1);
    address user = vm.addr(userPrivateKey);
    address uniAgentOwner = makeAddr("uniAgentOwner");
    address allowanceTargetOwner = makeAddr("allowanceTargetOwner");
    address payable recipient = payable(makeAddr("recipient"));
    uint256 defaultExpiry = block.timestamp + 1;
    uint256 defaultInputAmount = 10 * 1e6;
    address defaultInputToken = USDT_ADDRESS;
    address defaultOutputToken = CRV_ADDRESS;
    address[] defaultPath = [defaultInputToken, defaultOutputToken];
    bytes defaultUserPermit;
    UniAgent uniAgent;
    AllowanceTarget allowanceTarget;

    function setUp() public virtual {
        // deploy allowance target
        address[] memory trusted = new address[](1);
        // pre-compute UniAgent address since the whitelist of allowance target is immutable
        // NOTE: this assumes UniAgent is deployed right next to Allowance Target
        trusted[0] = computeContractAddress(address(this), uint8(vm.getNonce(address(this)) + 1));
        allowanceTarget = new AllowanceTarget(allowanceTargetOwner, trusted);

        uniAgent = new UniAgent(uniAgentOwner, UNISWAP_PERMIT2_ADDRESS, address(allowanceTarget), IWETH(WETH_ADDRESS));
        uniAgent.approveTokensToRouters(defaultPath);

        deal(user, 100 ether);
        setTokenBalanceAndApprove(user, address(uniAgent), tokens, 100000);

        defaultUserPermit = abi.encodePacked(TokenCollector.Source.Token);
    }
}
