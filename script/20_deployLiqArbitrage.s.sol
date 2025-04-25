// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "forge-std/Script.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";
import "../src/router/util/CurveLiqArbitrage.sol";

contract CurveLiqArbitrageScript is Script {
    address private curveLiqArbitrage;

    function run() public {
        vm.startBroadcast();
        curveLiqArbitrage = address(new CurveLiqArbitrage());
        console.log("CurveLiqArbitrage deployed at", curveLiqArbitrage);
        vm.stopBroadcast();
    }
}
