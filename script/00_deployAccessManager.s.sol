// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import "openzeppelin-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "openzeppelin-contracts/access/manager/AccessManager.sol";

// script to deploy the Factory Instance and Proxy
contract AccessManagerDeploymentScript is Script {
    address private testRes;
    address private initialSuperAdmin;
    bool private forTest;

    function run() public {
        vm.startBroadcast();
        if (forTest) {
            address accessManagerInstance = address(new AccessManager(initialSuperAdmin));
            console.log(
                "AccessManager instance deployed at",
                accessManagerInstance,
                "with super admin",
                initialSuperAdmin
            );
            testRes = accessManagerInstance;
        } else {
            string memory deploymentNetwork = vm.envString("DEPLOYMENT_NETWORK");
            if (bytes(deploymentNetwork).length == 0) {
                revert("DEPLOYMENT_NETWORK is not set in .env file");
            }

            string memory envVar = string.concat("ACCESS_MANAGER_ADMIN_", deploymentNetwork);
            if (bytes(vm.envString(envVar)).length == 0) {
                revert(string.concat(envVar, " is not set in .env file"));
            }
            initialSuperAdmin = vm.envAddress(envVar);

            address accessManagerInstance = address(new AccessManager(initialSuperAdmin));
            console.log(
                "AccessManager instance deployed at",
                accessManagerInstance,
                "with super admin",
                initialSuperAdmin
            );
        }
        vm.stopBroadcast();
    }

    function deployForTest(address _initialSuperAdmin) public returns (address _testRes) {
        forTest = true;
        initialSuperAdmin = _initialSuperAdmin;
        run();
        _testRes = testRes;
        forTest = false;
        testRes = address(0);
        initialSuperAdmin = address(0);
    }
}
