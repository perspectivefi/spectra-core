// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "forge-std/Script.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";
import "openzeppelin-contracts/token/ERC20/IERC20.sol";
import "src/interfaces/IRegistry.sol";
import "src/interfaces/IPrincipalToken.sol";
import "src/tokens/PrincipalToken.sol";
import "src/mocks/MockIBTBeta.sol";
import "src/mocks/MockUnderlying.sol";

contract GenerateYieldScript is Script {
    function run() public {
        vm.startBroadcast();
        string memory deploymentNetwork = vm.envString("DEPLOYMENT_NETWORK");
        if (bytes(deploymentNetwork).length == 0) {
            revert("DEPLOYMENT_NETWORK is not set in .env file");
        }

        if (
            bytes(vm.envString(string.concat("PT_BEACON_PROXY_ADDR_", deploymentNetwork))).length ==
            0
        ) {
            revert("PT_BEACON_PROXY_ADDR_ is not set in .env file");
        }
        address pt = vm.envAddress(string.concat("PT_BEACON_PROXY_ADDR_", deploymentNetwork));

        if (bytes(vm.envString(string.concat("ASSET_ADDR_", deploymentNetwork))).length == 0) {
            revert("ASSET_ADDR_ is not set in .env file");
        }
        address asset = vm.envAddress(string.concat("ASSET_ADDR_", deploymentNetwork));

        if (bytes(vm.envString(string.concat("IBT_ADDR_", deploymentNetwork))).length == 0) {
            revert("IBT_ADDR_ is not set in .env file");
        }
        address ibt = vm.envAddress(string.concat("IBT_ADDR_", deploymentNetwork));

        // Generate yield
        // step 1: Get some info

        console.log("IBT underlying balance:", IERC20(asset).balanceOf(ibt));
        console.log("IBT total supply:", MockIBTBeta(ibt).totalSupply());
        console.log("IBT convertToAssets:", MockIBTBeta(ibt).convertToAssets(1e18));
        console.log("PT convertToAssets:", PrincipalToken(pt).convertToUnderlying(1e18)); // should be 1 if no neg yield generated

        // step 2: IERC20Upgradeable(asset).balanceOf(ibt) and add it times
        // (1000000000000000000000000000 / 988377723516182530234248280 - 1) * 4 * (21 / 365) -> stETH (DEPRECATED)
        // (1000000000000000000000000000 / 955109837631327602674307545 - 1) * 1 * (nbOFDays / 365) -> stETH (NEW VAULT)
        // (1000000000000000000000000000 / 988768931884272127000000000 - 1) * 2 * (14 / 365) -> Morpho
        // to the mock ibt contract
        // ex:
        // uint256 result = (IERC20Upgradeable(asset).balanceOf(ibt) * 1000000000000000000000000000 / 955109837631327602674307545 - IERC20Upgradeable(asset).balanceOf(ibt)) * 1 * 1 / 365;
        // console.log("result", result);
        /*
        console.log("minting assets towards ibt contract (generating yield)...");
        MockUnderlying(asset).mint(ibt, 256366315881003033911160);
        */

        // step 3: update the ibt rates (it's also done when depositing / withdrawing from the ibt)
        /*
        console.log("updating ibt rates...");
        MockIBTBeta(ibt).updatePricePerFullShare();
        */

        // step 4: Recheck some info
        /*
        console.log("IBT underlying balance:", IERC20Upgradeable(asset).balanceOf(ibt));
        console.log("IBT total supply:", MockIBTBeta(ibt).totalSupply());
        console.log("IBT convertToAssets:", MockIBTBeta(ibt).convertToAssets(1e18));
        console.log("PT convertToAssets:", PrincipalToken(pt).convertToUnderlying(1e18)); // should be 1 if no neg yield generated
        */

        // step 5: test claim yield of 100e18
        /*
        console.log("Deployer u balance:", IERC20Upgradeable(asset).balanceOf(deployerAddr));
        uint256 underlyingReceived = PrincipalToken(pt).claimYieldOfAmount(100e18);
        //uint256 underlyingReceived = PrincipalToken(pt).claimYield();
        console.log("Underlying received:", underlyingReceived);
        console.log("Deployer u balance:", IERC20Upgradeable(asset).balanceOf(deployerAddr));
        */

        vm.stopBroadcast();
    }
}
