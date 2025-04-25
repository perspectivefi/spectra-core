// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/proxy/AMBeacon.sol";
import "../src/interfaces/IRateOracleRegistry.sol";
import "../src/libraries/Roles.sol";

// script to deploy the PrincipalToken Beacon
contract RateAdjustmentOracleBeaconScript is Script {
    bytes4[] private selectors_beacon = new bytes4[](1);
    address private testRes;
    address private rateAdjustmentOracleInstance;
    address private initialAuthority;
    address private registry;
    bool private forTest;

    function run() public {
        vm.startBroadcast();
        selectors_beacon[0] = AMBeacon(address(0)).upgradeTo.selector;
        if (forTest) {
            address rateAdjustmentOracleBeacon = address(
                new AMBeacon(rateAdjustmentOracleInstance, initialAuthority)
            );
            console.log(
                "RateAdjusmtentOracle1BeaconUpgradeable deployed at",
                rateAdjustmentOracleBeacon
            );
            IAccessManager(initialAuthority).setTargetFunctionRole(
                rateAdjustmentOracleBeacon,
                selectors_beacon,
                Roles.UPGRADE_ROLE
            );
            console.log("Function setTargetFunctionRole Role set for ProxyAdmin");
            IRateOracleRegistry(registry).setRateOracleBeacon(rateAdjustmentOracleBeacon);
            testRes = rateAdjustmentOracleBeacon;
        } else {
            string memory deploymentNetwork = vm.envString("DEPLOYMENT_NETWORK");
            if (bytes(deploymentNetwork).length == 0) {
                revert("DEPLOYMENT_NETWORK is not set in .env file");
            }

            string memory envVar = string.concat("REGISTRY_ADDR_", deploymentNetwork);
            if (bytes(vm.envString(envVar)).length == 0) {
                revert(string.concat(envVar, " is not set in .env file"));
            }
            registry = vm.envAddress(envVar);

            envVar = string.concat("ACCESS_MANAGER_ADDRESS_", deploymentNetwork);
            if (bytes(vm.envString(envVar)).length == 0) {
                revert(string.concat(envVar, " is not set in .env file"));
            }
            initialAuthority = vm.envAddress(envVar);

            envVar = string.concat("RATE_ADJUSTMENT_ORACLE_INSTANCE_ADDR_", deploymentNetwork);
            if (bytes(vm.envString(envVar)).length == 0) {
                revert(string.concat(envVar, " is not set in .env file"));
            }
            rateAdjustmentOracleInstance = vm.envAddress(envVar);

            address rateAdjustmentOracleBeacon = address(
                new AMBeacon(rateAdjustmentOracleInstance, initialAuthority)
            );
            console.log(
                "Principal Token Beacon Upgradeable deployed at",
                rateAdjustmentOracleInstance
            );
            IAccessManager(initialAuthority).setTargetFunctionRole(
                rateAdjustmentOracleBeacon,
                selectors_beacon,
                Roles.UPGRADE_ROLE
            );
            IRateOracleRegistry(registry).setRateOracleBeacon(rateAdjustmentOracleBeacon);
            console.log("Function setTargetFunctionRole Role set for ProxyAdmin");
        }
        vm.stopBroadcast();
    }

    function deployForTest(
        address _rateOracleInstance,
        address _registry,
        address _initialAuthority
    ) public returns (address _testRes) {
        forTest = true;
        rateAdjustmentOracleInstance = _rateOracleInstance;
        registry = _registry;
        initialAuthority = _initialAuthority;
        run();
        forTest = false;
        _testRes = testRes;
        testRes = address(0);
        rateAdjustmentOracleInstance = address(0);
        registry = address(0);
        initialAuthority = address(0);
    }
}
