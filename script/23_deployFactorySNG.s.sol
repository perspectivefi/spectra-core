// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/factory/FactorySNG.sol";
import "../src/proxy/AMTransparentUpgradeableProxy.sol";
import "../src/proxy/AMProxyAdmin.sol";
import "../src/libraries/Roles.sol";
import "openzeppelin-contracts/access/manager/IAccessManager.sol";

// script to deploy the Factory SNG Instance and Proxy
contract FactorySNGScript is Script {
    bytes4[] private selectors_proxy_admin = new bytes4[](1);
    bytes4[] private factory_selector = new bytes4[](1);
    address private testRes;
    address private registry;
    address private rateOracleRegistry;
    address private curveFactoryAddress;
    address private accessManager;
    bool private forTest;

    function run() public {
        vm.startBroadcast();
        selectors_proxy_admin[0] = AMProxyAdmin(address(0)).upgradeAndCall.selector;
        factory_selector[0] = FactorySNG(address(0)).setCurveFactory.selector;
        if (forTest) {
            address factorySNGInstance = address(new FactorySNG(registry, rateOracleRegistry));
            console.log("Factory SNG instance deployed at", factorySNGInstance);

            address FactorySNGProxy = address(
                new AMTransparentUpgradeableProxy(
                    factorySNGInstance,
                    accessManager,
                    abi.encodeWithSelector(
                        FactorySNG(address(0)).initialize.selector,
                        accessManager,
                        curveFactoryAddress
                    )
                )
            );
            console.log("Factory SNG proxy deployed at", FactorySNGProxy);

            // Set the admin role
            bytes32 adminSlot = vm.load(address(FactorySNGProxy), ERC1967Utils.ADMIN_SLOT);
            address proxyAdmin = address(uint160(uint256(adminSlot)));
            IRegistry(registry).setFactory(FactorySNGProxy);
            IAccessManager(accessManager).setTargetFunctionRole(
                proxyAdmin,
                selectors_proxy_admin,
                Roles.UPGRADE_ROLE
            );

            // Set the registry role
            IAccessManager(accessManager).setTargetFunctionRole(
                FactorySNGProxy,
                factory_selector,
                Roles.REGISTRY_ROLE
            );
            console.log("Function setTargetFunctionRole Role set for ProxyAdmin");
            testRes = FactorySNGProxy;
        } else {
            string memory deploymentNetwork = vm.envString("DEPLOYMENT_NETWORK");
            if (bytes(deploymentNetwork).length == 0) {
                revert("DEPLOYMENT_NETWORK is not set in .env file");
            }

            string memory envVar = string.concat("ACCESS_MANAGER_ADDRESS_", deploymentNetwork);
            if (bytes(vm.envString(envVar)).length == 0) {
                revert(string.concat(envVar, " is not set in .env file"));
            }
            accessManager = vm.envAddress(envVar);

            envVar = string.concat("REGISTRY_ADDR_", deploymentNetwork);
            if (bytes(vm.envString(envVar)).length == 0) {
                revert(string.concat(envVar, " is not set in .env file"));
            }
            registry = vm.envAddress(envVar);

            envVar = string.concat("RATE_ORACLE_REGISTRY_ADDR_", deploymentNetwork);
            if (bytes(vm.envString(envVar)).length == 0) {
                revert(string.concat(envVar, " is not set in .env file"));
            }
            rateOracleRegistry = vm.envAddress(envVar);

            envVar = string.concat("CURVE_FACTORY_", deploymentNetwork);
            if (bytes(vm.envString(envVar)).length == 0) {
                revert(string.concat(envVar, " is not set in .env file"));
            }
            curveFactoryAddress = vm.envAddress(envVar);

            address factorySNGInstance = address(new FactorySNG(registry, rateOracleRegistry));
            console.log("Factory instance deployed at", factorySNGInstance);

            address FactorySNGProxy = address(
                new AMTransparentUpgradeableProxy(
                    factorySNGInstance,
                    accessManager,
                    abi.encodeWithSelector(
                        FactorySNG(address(0)).initialize.selector,
                        accessManager,
                        curveFactoryAddress
                    )
                )
            );
            console.log("Factory SNG proxy deployed at", FactorySNGProxy);
            IRegistry(registry).setFactory(FactorySNGProxy);
            bytes32 adminSlot = vm.load(address(FactorySNGProxy), ERC1967Utils.ADMIN_SLOT);
            address proxyAdmin = address(uint160(uint256(adminSlot)));
            console.log("Factory Proxy Admin Address:", address(proxyAdmin));
            IAccessManager(accessManager).setTargetFunctionRole(
                proxyAdmin,
                selectors_proxy_admin,
                Roles.UPGRADE_ROLE
            );
            IAccessManager(accessManager).setTargetFunctionRole(
                FactorySNGProxy,
                factory_selector,
                Roles.REGISTRY_ROLE
            );
            console.log("Function setTargetFunctionRole Role set for ProxyAdmin");
        }
        vm.stopBroadcast();
    }

    function deployForTest(
        address _registry,
        address _rateOracleRegistry,
        address _curveFactoryAddress,
        address _accessManager
    ) public returns (address _testRes) {
        forTest = true;
        registry = _registry;
        rateOracleRegistry = _rateOracleRegistry;
        curveFactoryAddress = _curveFactoryAddress;
        accessManager = _accessManager;
        run();
        forTest = false;
        _testRes = testRes;
        testRes = address(0);
        curveFactoryAddress = address(0);
        registry = address(0);
        rateOracleRegistry = address(0);
        accessManager = address(0);
    }
}
