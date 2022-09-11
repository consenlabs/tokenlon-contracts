// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "contracts/Spender.sol";
import "contracts/AllowanceTarget.sol";
import { PermanentStorage } from "contracts/PermanentStorage.sol"; // Using "import from" syntax so PermanentStorage and UserProxy's imports will not collide
import "contracts/ProxyPermanentStorage.sol";
import { UserProxy } from "contracts/UserProxy.sol"; // Using "import from" syntax so PermanentStorage and UserProxy's imports will not collide
import "contracts/Tokenlon.sol";
import "contracts/interfaces/ISetAllowance.sol";
import "./Addresses.sol";
import "./BalanceUtil.sol";
import "./RegisterCurveIndexes.sol";

contract StrategySharedSetup is BalanceUtil, RegisterCurveIndexes {
    using SafeERC20 for IERC20;

    address upgradeAdmin = address(0x5566);

    AllowanceTarget allowanceTarget;
    Spender spender;
    UserProxy userProxy;
    PermanentStorage permanentStorage;

    function _deployStrategyAndUpgrade() internal virtual returns (address) {}

    function _deployTokenlonAndUserProxy() internal {
        UserProxy userProxyImpl = new UserProxy();
        Tokenlon tokenlon = new Tokenlon(
            address(userProxyImpl),
            upgradeAdmin,
            bytes("") // Skip initialization during deployment
        );
        userProxy = UserProxy(address(tokenlon));
        // Set this contract as operator
        userProxy.initialize(address(this));
    }

    function _deployPermanentStorageAndProxy() internal {
        PermanentStorage permanentStorageImpl = new PermanentStorage();
        ProxyPermanentStorage permanentStorageProxy = new ProxyPermanentStorage(
            address(permanentStorageImpl),
            upgradeAdmin,
            bytes("") // Skip initialization during deployment
        );
        permanentStorage = PermanentStorage(address(permanentStorageProxy));
        // Set this contract as operator
        permanentStorage.initialize(address(this));
        permanentStorage.upgradeWETH(WETH_ADDRESS);
        // Set Curve indexes
        permanentStorage.setPermission(permanentStorage.curveTokenIndexStorageId(), address(this), true);
        _registerCurveIndexes(permanentStorage);
    }

    function setUpSystemContracts() internal {
        // Deploy
        spender = new Spender(address(this), new address[](1));
        allowanceTarget = new AllowanceTarget(address(spender));
        _deployTokenlonAndUserProxy();
        _deployPermanentStorageAndProxy();
        address strategy = _deployStrategyAndUpgrade();
        // Setup
        spender.setAllowanceTarget(address(allowanceTarget));
        address[] memory authListAddress = new address[](1);
        authListAddress[0] = strategy;
        spender.authorize(authListAddress);
        permanentStorage.setPermission(permanentStorage.relayerValidStorageId(), address(this), true);

        vm.label(upgradeAdmin, "UpgradeAdmin");
        vm.label(address(spender), "SpenderContract");
        vm.label(address(allowanceTarget), "AllowanceTargetContract");
        vm.label(address(userProxy), "UserProxyContract");
        vm.label(address(permanentStorage), "PermanentStorageContract");
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
        ISetAllowance(walletContract).setAllowance(tokenAddresses, address(allowanceTarget));
    }
}
