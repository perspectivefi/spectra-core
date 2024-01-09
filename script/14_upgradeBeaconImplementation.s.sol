// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "forge-std/Script.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";
import "../src/mocks/MockIBT.sol";
import "openzeppelin-contracts/interfaces/IERC20Metadata.sol";
import "openzeppelin-contracts/proxy/beacon/UpgradeableBeacon.sol";

contract UpgradeBeaconLogicScript is Script {
    address private testAddressBeacon;
    address private testAddressNewInstance;
    bool private forTest;

    function run() public {
        vm.startBroadcast();
        if (forTest) {
            UpgradeableBeacon(testAddressBeacon).upgradeTo(testAddressNewInstance);
            console.log("Instance of beacon updated to", testAddressNewInstance);
        } else {
            string memory deploymentNetwork = vm.envString("DEPLOYMENT_NETWORK");
            if (bytes(deploymentNetwork).length == 0) {
                revert("DEPLOYMENT_NETWORK is not set in .env file");
            }

            if (bytes(vm.envString(string.concat("BEACON_ADDR_", deploymentNetwork))).length == 0) {
                revert("BEACON_ADDR_ is not set in .env file");
            }
            address beacon = vm.envAddress(string.concat("BEACON_ADDR_", deploymentNetwork));

            if (
                bytes(vm.envString(string.concat("NEW_INSTANCE_ADDR_", deploymentNetwork)))
                    .length == 0
            ) {
                revert("NEW_INSTANCE_ADDR_ is not set in .env file");
            }
            address newInstance = vm.envAddress(
                string.concat("NEW_INSTANCE_ADDR_", deploymentNetwork)
            );

            UpgradeableBeacon(beacon).upgradeTo(newInstance);
            console.log("Instance of beacon updated to", newInstance);
        }
        vm.stopBroadcast();
    }

    function upgradeForTest(address beacon, address newInstance) public {
        forTest = true;
        testAddressBeacon = beacon;
        testAddressNewInstance = newInstance;
        run();
        forTest = false;
        testAddressBeacon = address(0);
        testAddressNewInstance = address(0);
    }
}
