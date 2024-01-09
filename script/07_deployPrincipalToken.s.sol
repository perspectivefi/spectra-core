// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/tokens/PrincipalToken.sol";
import "../src/factory/Factory.sol";

// script to deploy the PrincipalToken Proxy
contract PrincipalTokenScript is Script {
    address private testRes;
    address private factory;
    address private ibt;
    uint256 private duration;
    bool private forTest;

    function run() public {
        vm.startBroadcast();
        string memory deploymentNetwork = vm.envString("DEPLOYMENT_NETWORK");
        if (bytes(deploymentNetwork).length == 0) {
            revert("DEPLOYMENT_NETWORK is not set in .env file");
        }

        if (forTest) {
            // deploy principalToken
            address principalToken = IFactory(factory).deployPT(ibt, duration);
            console.log("PrincipalToken Beacon Proxy deployed at", address(principalToken));
            console.log("YT Beacon Proxy deployed at ", IPrincipalToken(principalToken).getYT());
            testRes = address(principalToken);
        } else {
            string memory envVar = string.concat("IBT_ADDR_", deploymentNetwork);
            if (bytes(vm.envString(envVar)).length == 0) {
                revert(string.concat(envVar, " is not set in .env file"));
            }
            ibt = vm.envAddress(envVar);

            envVar = string.concat("DURATION_", deploymentNetwork);
            if (bytes(vm.envString(envVar)).length == 0) {
                revert(string.concat(envVar, " is not set in .env file"));
            }
            duration = vm.envUint(envVar);

            envVar = string.concat("FACTORY_ADDR_", deploymentNetwork);
            if (bytes(vm.envString(envVar)).length == 0) {
                revert(string.concat(envVar, " is not set in .env file"));
            }
            factory = vm.envAddress(envVar);

            // deploy principalToken
            address principalToken = IFactory(factory).deployPT(ibt, duration);

            console.log("PrincipalToken Beacon Proxy deployed at", principalToken);
            console.log("YT Beacon Proxy deployed at ", IPrincipalToken(principalToken).getYT());
        }
        vm.stopBroadcast();
    }

    function deployForTest(
        address _factoryAddr,
        address _ibt,
        uint256 _duration
    ) public returns (address _testRes) {
        forTest = true;
        factory = _factoryAddr;
        ibt = _ibt;
        duration = _duration;
        run();
        forTest = false;
        _testRes = testRes;
        testRes = address(0);
        factory = address(0);
        ibt = address(0);
        duration = 0;
    }
}
