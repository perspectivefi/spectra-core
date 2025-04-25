// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "forge-std/Script.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";
import "../src/RateOracleRegistry.sol";
import "../src/proxy/AMTransparentUpgradeableProxy.sol";
import "../src/proxy/AMProxyAdmin.sol";
import "../src/libraries/Roles.sol";
import "openzeppelin-contracts/access/manager/IAccessManager.sol";

contract RateOracleRegistryScript is Script {
    // Selectors
    bytes4[] private selectors_proxy_admin = new bytes4[](1);
    bytes4[] private registry_methods_selectors = new bytes4[](3);

    // Addresses
    address private testRes;
    address private initialAuthority;

    // True if test deployment
    bool private forTest;

    function run() public {
        vm.startBroadcast();

        // proxy admin selectors
        selectors_proxy_admin[0] = AMProxyAdmin(address(0)).upgradeAndCall.selector;

        // registry methods selectors
        registry_methods_selectors[0] = IRateOracleRegistry(address(0))
            .setRateOracleBeacon
            .selector;
        registry_methods_selectors[1] = IRateOracleRegistry(address(0)).addRateOracle.selector;
        registry_methods_selectors[2] = IRateOracleRegistry(address(0)).removeRateOracle.selector;

        if (forTest) {
            RateOracleRegistry rateOracleRegistryInstance = new RateOracleRegistry();
            console.log(
                "Rate oracle registry instance deployed at",
                address(rateOracleRegistryInstance)
            );
            address rateOracleRegistryProxy = address(
                new AMTransparentUpgradeableProxy(
                    address(rateOracleRegistryInstance),
                    initialAuthority,
                    abi.encodeWithSelector(
                        RateOracleRegistry(address(0)).initialize.selector,
                        initialAuthority
                    )
                )
            );
            console.log("Rate Oracle registry proxy deployed at", rateOracleRegistryProxy);

            // Set the roles
            IAccessManager(initialAuthority).setTargetFunctionRole(
                rateOracleRegistryProxy,
                registry_methods_selectors,
                Roles.REGISTRY_ROLE
            );

            bytes32 adminSlot = vm.load(address(rateOracleRegistryProxy), ERC1967Utils.ADMIN_SLOT);
            address proxyAdmin = address(uint160(uint256(adminSlot)));
            IAccessManager(initialAuthority).setTargetFunctionRole(
                proxyAdmin,
                selectors_proxy_admin,
                Roles.UPGRADE_ROLE
            );
            console.log("Function setTargetFunctionRole Role set for ProxyAdmin");
            testRes = rateOracleRegistryProxy;
        } else {
            string memory deploymentNetwork = vm.envString("DEPLOYMENT_NETWORK");
            if (bytes(deploymentNetwork).length == 0) {
                revert("DEPLOYMENT_NETWORK is not set in .env file");
            }

            string memory envVar = string.concat("ACCESS_MANAGER_ADDRESS_", deploymentNetwork);
            if (bytes(vm.envString(envVar)).length == 0) {
                revert(string.concat(envVar, " is not set in .env file"));
            }
            initialAuthority = vm.envAddress(envVar);

            address rateOracleRegistryInstance = address(new RateOracleRegistry());
            console.log("Registry instance deployed at", rateOracleRegistryInstance);
            address rateOracleRegistryProxy = address(
                new AMTransparentUpgradeableProxy(
                    rateOracleRegistryInstance,
                    initialAuthority,
                    abi.encodeWithSelector(
                        RateOracleRegistry(address(0)).initialize.selector,
                        initialAuthority
                    )
                )
            );
            console.log("Rate Oracle Registry proxy deployed at", rateOracleRegistryProxy);

            // set roles
            IAccessManager(initialAuthority).setTargetFunctionRole(
                rateOracleRegistryProxy,
                registry_methods_selectors,
                Roles.REGISTRY_ROLE
            );

            bytes32 adminSlot = vm.load(address(rateOracleRegistryProxy), ERC1967Utils.ADMIN_SLOT);
            address proxyAdmin = address(uint160(uint256(adminSlot)));

            console.log("Rate Oracle Registry Proxy Admin Address:", address(proxyAdmin));

            IAccessManager(initialAuthority).setTargetFunctionRole(
                proxyAdmin,
                selectors_proxy_admin,
                Roles.UPGRADE_ROLE
            );
            console.log("Function setTargetFunctionRole Role set for ProxyAdmin");
        }

        vm.stopBroadcast();
    }

    function deployForTest(address _initialAuthority) public returns (address _testRes) {
        forTest = true;
        initialAuthority = _initialAuthority;
        run();
        forTest = false;
        _testRes = testRes;
        testRes = address(0);
        initialAuthority = address(0);
    }
}
