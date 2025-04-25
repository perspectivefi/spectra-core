// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/tokens/PrincipalToken.sol";

// script to deploy the PrincipalToken Instance
contract PrincipalTokenInstanceScript is Script {
    address private testRes;
    address private ptInstance;
    address private registry;
    bool private forTest;

    function run() public {
        vm.startBroadcast();
        if (forTest) {
            ptInstance = address(new PrincipalToken(registry));
            testRes = ptInstance;
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
            ptInstance = address(new PrincipalToken(registry));
        }
        console.log("PrincipalToken instance deployed at", ptInstance);
        vm.stopBroadcast();
    }

    function deployForTest(address _registry) public returns (address _testRes) {
        forTest = true;
        registry = _registry;
        run();
        forTest = false;
        _testRes = testRes;
        testRes = address(0);
        registry = address(0);
    }
}
