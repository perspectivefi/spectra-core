// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "forge-std/Script.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";
import "openzeppelin-contracts/proxy/transparent/ProxyAdmin.sol";
import {ERC1967Utils} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Utils.sol";

contract UpgradeTransparentProxyScript is Script {
    address private testAddressTransparentProxy;
    address private testAddressNewInstance;
    bool private forTest;

    function run() public {
        vm.startBroadcast();
        if (forTest) {
            bytes32 adminSlot = vm.load(testAddressTransparentProxy, ERC1967Utils.ADMIN_SLOT);
            address proxyAdmin = address(uint160(uint256(adminSlot)));

            ProxyAdmin(proxyAdmin).upgradeAndCall(
                ITransparentUpgradeableProxy(testAddressTransparentProxy),
                testAddressNewInstance,
                ""
            );
            console.log("Instance of proxy updated to", testAddressNewInstance);
        } else {
            string memory deploymentNetwork = vm.envString("DEPLOYMENT_NETWORK");
            if (bytes(deploymentNetwork).length == 0) {
                revert("DEPLOYMENT_NETWORK is not set in .env file");
            }

            if (bytes(vm.envString(string.concat("PROXY_ADDR_", deploymentNetwork))).length == 0) {
                revert("Transparent PROXY_ADDR_ is not set in .env file");
            }
            address payable proxy = payable(
                vm.envAddress(string.concat("PROXY_ADDR_", deploymentNetwork))
            );

            if (
                bytes(vm.envString(string.concat("NEW_INSTANCE_ADDR_", deploymentNetwork)))
                    .length == 0
            ) {
                revert("NEW_INSTANCE_ADDR_ is not set in .env file");
            }

            bytes32 adminSlot = vm.load(proxy, ERC1967Utils.ADMIN_SLOT);
            address proxyAdmin = address(uint160(uint256(adminSlot)));

            address newInstance = vm.envAddress(
                string.concat("NEW_INSTANCE_ADDR_", deploymentNetwork)
            );

            ProxyAdmin(proxyAdmin).upgradeAndCall(
                ITransparentUpgradeableProxy(proxy),
                newInstance,
                ""
            );
            console.log("Instance of proxy updated to", newInstance);
        }
        vm.stopBroadcast();
    }

    function upgradeForTest(address proxy, address newInstance) public {
        forTest = true;
        testAddressTransparentProxy = proxy;
        testAddressNewInstance = newInstance;
        run();
        forTest = false;
        testAddressTransparentProxy = address(0);
        testAddressNewInstance = address(0);
    }
}
