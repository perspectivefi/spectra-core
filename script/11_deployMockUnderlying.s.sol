// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "forge-std/Script.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";
import "../src/mocks/MockUnderlying.sol";

contract MockUnderlyingScript is Script {
    function run() public {
        vm.startBroadcast();
        string memory deploymentNetwork = vm.envString("DEPLOYMENT_NETWORK");
        if (bytes(deploymentNetwork).length == 0) {
            revert("DEPLOYMENT_NETWORK is not set in .env file");
        }
        MockUnderlying underlying = new MockUnderlying();
        underlying.initialize("Spectra USDC", "USDC");
        console.log("Underlying deployed at", address(underlying));
        vm.stopBroadcast();
    }
}
