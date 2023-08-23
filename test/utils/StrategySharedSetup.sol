// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import { Spender } from "contracts/Spender.sol";
import { AllowanceTarget } from "contracts/AllowanceTarget.sol";
import { PermanentStorage } from "contracts/PermanentStorage.sol";
import { ProxyPermanentStorage } from "contracts/ProxyPermanentStorage.sol";
import { UserProxy } from "contracts/UserProxy.sol";
import { Tokenlon } from "contracts/Tokenlon.sol";
import { MockERC1271Wallet } from "test/mocks/MockERC1271Wallet.sol";
import { BalanceUtil } from "test/utils/BalanceUtil.sol";
import { RegisterCurveIndexes } from "test/utils/RegisterCurveIndexes.sol";

contract StrategySharedSetup is BalanceUtil, RegisterCurveIndexes {
    using SafeERC20 for IERC20;

    address constant zxProxy = 0x95E6F48254609A6ee006F7D493c8e5fB97094ceF;

    string private constant filePath = "test/utils/config/deployedContracts.json";

    address tokenlonOperator = makeAddr("tokenlonOperator");
    address upgradeAdmin = makeAddr("upgradeAdmin");

    AllowanceTarget allowanceTarget;
    Spender spender;
    UserProxy userProxy;
    PermanentStorage permanentStorage;

    function _deployStrategyAndUpgrade() internal virtual returns (address) {}

    function _setupDeployedStrategy() internal virtual {}

    function _deployTokenlonAndUserProxy() internal {
        UserProxy userProxyImpl = new UserProxy();
        Tokenlon tokenlon = new Tokenlon(
            address(userProxyImpl),
            upgradeAdmin,
            bytes("") // Skip initialization during deployment
        );
        userProxy = UserProxy(address(tokenlon));
        // Set operator
        userProxy.initialize(tokenlonOperator);
    }

    function _deployPermanentStorageAndProxy() internal {
        PermanentStorage permanentStorageImpl = new PermanentStorage();
        ProxyPermanentStorage permanentStorageProxy = new ProxyPermanentStorage(
            address(permanentStorageImpl),
            upgradeAdmin,
            bytes("") // Skip initialization during deployment
        );
        permanentStorage = PermanentStorage(address(permanentStorageProxy));
        // Set permanent storage operator
        permanentStorage.initialize(tokenlonOperator);
        vm.startPrank(tokenlonOperator, tokenlonOperator);
        permanentStorage.upgradeWETH(address(weth));
        // Set Curve indexes
        permanentStorage.setPermission(permanentStorage.curveTokenIndexStorageId(), tokenlonOperator, true);
        _registerCurveIndexes(permanentStorage);
        vm.stopPrank();
    }

    function setUpSystemContracts() internal {
        if (vm.envBool("DEPLOYED")) {
            // Load deployed system contracts
            string memory deployedAddr = vm.readFile(filePath);
            allowanceTarget = AllowanceTarget(abi.decode(vm.parseJson(deployedAddr, "$.ALLOWANCE_TARGET_ADDRESS"), (address)));
            spender = Spender(abi.decode(vm.parseJson(deployedAddr, "$.SPENDER_ADDRESS"), (address)));
            userProxy = UserProxy(abi.decode(vm.parseJson(deployedAddr, "$.USERPROXY_ADDRESS"), (address)));
            permanentStorage = PermanentStorage(abi.decode(vm.parseJson(deployedAddr, "$.PERMANENTSTORAGE_ADDRESS"), (address)));

            // overwrite tokenlonOperator
            tokenlonOperator = userProxy.operator();

            upgradeAdmin = 0x74C3cA9431C009dC35587591Dc90780078174f8a;
            // upgrade userProxy
            UserProxy newUP = UserProxy(0x0B9F13fFAB8448089f50073Cf24BBE5C7Bd8675A);
            vm.startPrank(upgradeAdmin);
            Tokenlon(address(userProxy)).upgradeTo(address(newUP));
            vm.stopPrank();

            // upgrade pstorage
            PermanentStorage newPS = PermanentStorage(0x32c1f83D729E4a2e01398841465920B1fd42c274);
            vm.startPrank(upgradeAdmin);
            ProxyPermanentStorage(payable(address(permanentStorage))).upgradeTo(address(newPS));
            vm.stopPrank();

            _setupDeployedStrategy();
        } else {
            // Deploy
            spender = new Spender(tokenlonOperator);
            allowanceTarget = new AllowanceTarget(address(spender));
            _deployTokenlonAndUserProxy();
            _deployPermanentStorageAndProxy();
            address strategy = _deployStrategyAndUpgrade();
            // Setup
            vm.startPrank(tokenlonOperator, tokenlonOperator);
            spender.setAllowanceTarget(address(allowanceTarget));
            address[] memory authListAddress = new address[](1);
            authListAddress[0] = strategy;
            spender.authorize(authListAddress);
            vm.stopPrank();
        }
        vm.startPrank(tokenlonOperator, tokenlonOperator);
        permanentStorage.setPermission(permanentStorage.relayerValidStorageId(), tokenlonOperator, true);
        permanentStorage.setPermission(permanentStorage.curveTokenIndexStorageId(), tokenlonOperator, true);
        vm.stopPrank();

        vm.label(address(spender), "SpenderContract");
        vm.label(address(allowanceTarget), "AllowanceTargetContract");
        vm.label(address(userProxy), "UserProxyContract");
        vm.label(address(permanentStorage), "PermanentStorageContract");
    }

    function _readDeployedAddr(string memory key) internal returns (address) {
        string memory deployedAddr = vm.readFile(filePath);
        return abi.decode(vm.parseJson(deployedAddr, key), (address));
    }

    function dealWallet(address[] memory wallet, uint256 amount) internal {
        // Deal 100 ETH to each account
        for (uint256 i = 0; i < wallet.length; i++) {
            deal(wallet[i], amount);
        }
    }

    function setEOABalanceAndApprove(
        address eoa,
        IERC20[] memory tokens,
        uint256 amount
    ) internal {
        require(address(allowanceTarget) != address(0), "System contracts not setup yet");
        vm.startPrank(eoa);
        for (uint256 i = 0; i < tokens.length; i++) {
            setERC20Balance(address(tokens[i]), eoa, amount);
            tokens[i].safeApprove(address(allowanceTarget), type(uint256).max);
            tokens[i].safeApprove(zxProxy, type(uint256).max);
        }
        vm.stopPrank();
    }

    function setWalletContractBalanceAndApprove(
        address owner,
        address walletContract,
        IERC20[] memory tokens,
        uint256 amount
    ) internal {
        require(address(allowanceTarget) != address(0), "System contracts not setup yet");
        address[] memory tokenAddresses = new address[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            // Convert from type IERC20[] to address[] since wallet contract's `setAllowance` only accepts address[] type
            tokenAddresses[i] = address(tokens[i]);
            setERC20Balance(tokenAddresses[i], walletContract, amount);
        }
        vm.prank(owner);
        MockERC1271Wallet(payable(walletContract)).setAllowance(tokenAddresses, address(allowanceTarget));
    }
}
