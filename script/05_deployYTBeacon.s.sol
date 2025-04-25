// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/interfaces/IRegistry.sol";
import "../src/proxy/AMBeacon.sol";
import "../src/libraries/Roles.sol";

// script to deploy the YT Beacon
contract YTBeaconScript is Script {
    bytes4[] private selectors_beacon = new bytes4[](1);
    address private testRes;
    address private ytInstance;
    address private initialAuthority;
    address private registry;
    bool private forTest;

    function run() public {
        vm.startBroadcast();
        selectors_beacon[0] = AMBeacon(address(0)).upgradeTo.selector;
        if (forTest) {
            address ytBeacon = address(new AMBeacon(ytInstance, initialAuthority));
            console.log("YTBeaconUpgradeable deployed at", ytBeacon);
            IAccessManager(initialAuthority).setTargetFunctionRole(
                ytBeacon,
                selectors_beacon,
                Roles.UPGRADE_ROLE
            );
            console.log("Function setTargetFunctionRole Role set for ProxyAdmin");
            IRegistry(registry).setYTBeacon(ytBeacon);
            testRes = ytBeacon;
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

            envVar = string.concat("YT_INSTANCE_ADDR_", deploymentNetwork);
            if (bytes(vm.envString(envVar)).length == 0) {
                revert(string.concat(envVar, " is not set in .env file"));
            }
            ytInstance = vm.envAddress(envVar);

            envVar = string.concat("REGISTRY_ADDR_", deploymentNetwork);
            if (bytes(vm.envString(envVar)).length == 0) {
                revert(string.concat(envVar, " is not set in .env file"));
            }
            registry = vm.envAddress(envVar);

            address ytBeacon = address(new AMBeacon(ytInstance, initialAuthority));
            console.log("YTBeaconUpgradeable deployed at", ytBeacon);
            IAccessManager(initialAuthority).setTargetFunctionRole(
                ytBeacon,
                selectors_beacon,
                Roles.UPGRADE_ROLE
            );
            console.log("Function setTargetFunctionRole Role set for ProxyAdmin");
            IRegistry(registry).setYTBeacon(ytBeacon);
            testRes = ytBeacon;
        }
        vm.stopBroadcast();
    }

    function deployForTest(
        address _ytInstance,
        address _registry,
        address _initialAuthority
    ) public returns (address _testRes) {
        forTest = true;
        ytInstance = _ytInstance;
        registry = _registry;
        initialAuthority = _initialAuthority;
        run();
        forTest = false;
        _testRes = testRes;
        testRes = address(0);
        ytInstance = address(0);
        registry = address(0);
        initialAuthority = address(0);
    }
}
