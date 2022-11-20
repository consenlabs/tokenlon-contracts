// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.7.6;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "contracts/interfaces/IAllowanceTarget.sol";
import "contracts/interfaces/ISetAllowance.sol";
import { PermanentStorage } from "contracts/PermanentStorage.sol"; // Using "import from" syntax so PermanentStorage and UserProxy's imports will not collide
import "contracts/ProxyPermanentStorage.sol";
import { UserProxy } from "contracts/UserProxy.sol"; // Using "import from" syntax so PermanentStorage and UserProxy's imports will not collide
import "contracts/Tokenlon.sol";
import "./Addresses.sol";
import "./BalanceUtil.sol";
import "./RegisterCurveIndexes.sol";

// An interface only for test setup
interface ISpenderOps {
    function authorize(address[] calldata _pendingAuthorized) external;

    function completeAuthorize() external;
}

contract StrategySharedSetup is BalanceUtil, RegisterCurveIndexes {
    using SafeERC20 for IERC20;

    address upgradeAdmin = 0x74C3cA9431C009dC35587591Dc90780078174f8a;
    address operator = 0x9aFc226Dc049B99342Ad6774Eeb08BfA2F874465;

    IAllowanceTarget allowanceTarget = IAllowanceTarget(0x8A42d311D282Bfcaa5133b2DE0a8bCDBECea3073);
    ISpenderOps spender = ISpenderOps(0x3c68dfc45dc92C9c605d92B49858073e10b857A6);
    UserProxy userProxy;
    PermanentStorage permanentStorage;

    function _deployStrategyAndUpgrade() internal virtual returns (address) {}

    function _deployTokenlonAndUserProxy() internal {
        UserProxy userProxyImpl = new UserProxy();
        Tokenlon tokenlon = Tokenlon(0x03f34bE1BF910116595dB1b11E9d1B2cA5D59659);
        vm.prank(upgradeAdmin);
        tokenlon.upgradeTo(address(userProxyImpl));
        userProxy = UserProxy(address(tokenlon));
    }

    function _deployPermanentStorageAndProxy() internal {
        PermanentStorage permanentStorageImpl = new PermanentStorage();
        ProxyPermanentStorage permanentStorageProxy = ProxyPermanentStorage(0x6D9Cc14a1d36E6fF13fc6efA9e9326FcD12E7903);
        vm.prank(upgradeAdmin);
        permanentStorageProxy.upgradeTo(address(permanentStorageImpl));
        permanentStorage = PermanentStorage(address(permanentStorageProxy));
    }

    function setUpSystemContracts() internal {
        // Deploy
        _deployTokenlonAndUserProxy();
        _deployPermanentStorageAndProxy();
        address strategy = _deployStrategyAndUpgrade();
        // Setup
        address[] memory authListAddress = new address[](1);
        authListAddress[0] = strategy;
        vm.prank(operator);
        spender.authorize(authListAddress);
        // fast farward to activate spender authorization
        vm.warp(block.timestamp + 1 days);
        spender.completeAuthorize();

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
