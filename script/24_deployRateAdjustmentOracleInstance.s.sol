// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/amm/RateAdjustmentOracle.sol";

// script to deploy the Rate Adjustment Oracle  Instance
contract RateAdjustmentOracleInstanceScript is Script {
    address private testRes;
    address private rateAdjustmentOracleInstance;
    bool private forTest;

    function run() public {
        vm.startBroadcast();
        if (forTest) {
            rateAdjustmentOracleInstance = address(new RateAdjustmentOracle());
            testRes = rateAdjustmentOracleInstance;
        } else {
            string memory deploymentNetwork = vm.envString("DEPLOYMENT_NETWORK");
            if (bytes(deploymentNetwork).length == 0) {
                revert("DEPLOYMENT_NETWORK is not set in .env file");
            }

            rateAdjustmentOracleInstance = address(new RateAdjustmentOracle());
        }
        console.log("Rate adjustment oracle instance deployed at", rateAdjustmentOracleInstance);
        vm.stopBroadcast();
    }

    function deployForTest() public returns (address _testRes) {
        forTest = true;
        run();
        forTest = false;
        _testRes = testRes;
        testRes = address(0);
    }
}
