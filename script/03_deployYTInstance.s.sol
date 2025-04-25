// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/tokens/YieldToken.sol";

// script to deploy the YT Instance
contract YTInstanceScript is Script {
    address private testRes;
    address private ytInstance;
    bool private forTest;

    function run() public {
        vm.startBroadcast();
        if (forTest) {
            ytInstance = address(new YieldToken());
            testRes = ytInstance;
        } else {
            ytInstance = address(new YieldToken());
        }
        console.log("YT instance deployed at", ytInstance);
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
