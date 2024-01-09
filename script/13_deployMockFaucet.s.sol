// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "openzeppelin-contracts/interfaces/IERC4626.sol";
import "forge-std/Script.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";
import "src/mocks/MockFaucet.sol";
import "src/interfaces/IMockToken.sol";

contract MockFaucet2Script is Script {
    function run() public {
        vm.startBroadcast();
        string memory deploymentNetwork = vm.envString("DEPLOYMENT_NETWORK");
        if (bytes(deploymentNetwork).length == 0) {
            revert("DEPLOYMENT_NETWORK is not set in .env file");
        }

        if (bytes(vm.envString(string.concat("ASSET_ADDR_", deploymentNetwork))).length == 0) {
            revert("ASSET_ADDR_ is not set in .env file");
        }
        address asset = vm.envAddress(string.concat("ASSET_ADDR_", deploymentNetwork));

        if (bytes(vm.envString(string.concat("IBT_ADDR_", deploymentNetwork))).length == 0) {
            revert("IBT_ADDR_ is not set in .env file");
        }
        address ibt = vm.envAddress(string.concat("IBT_ADDR_", deploymentNetwork));

        MockFaucet faucet = new MockFaucet();
        faucet.initialize(asset, ibt);

        // Sending 20 Million assets (half in assets and the other in IBT) to the Faucet
        console.log("Mint 20 million tokens");
        IMockToken(asset).mint(msg.sender, 20000000e18);

        console.log("Depositing 10 million assets for IBT");
        IMockToken(asset).approve(ibt, 10000000e18);
        IERC4626(ibt).deposit(10000000e18, address(faucet));

        console.log("Transfer 10 million assets to faucet");
        IMockToken(asset).transfer(address(faucet), 10000000e18);

        console.log("Faucet deployed at", address(faucet));
        vm.stopBroadcast();
    }
}
