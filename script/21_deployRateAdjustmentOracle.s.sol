// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "forge-std/Script.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";
import "../src/amm/RateAdjustmentOracle.sol";
import "../src/RateOracleRegistry.sol";
import "../src/proxy/AMTransparentUpgradeableProxy.sol";
import "../src/libraries/Roles.sol";

contract RateAdjustmentOracleScipt is Script {
    address private initialAuthority;
    address private testRes;
    address private registry;
    address private rateOracleRegistry;

    // selectors
    bytes4[] private selectors_proxy_admin = new bytes4[](1);

    bool private forTest;

    function run() public {
        vm.startBroadcast();
        // proxy admin selectors
        selectors_proxy_admin[0] = AMProxyAdmin(address(0)).upgradeAndCall.selector;

        if (forTest) {
            address rateAdjustmentOracle = address(new RateAdjustmentOracle());

            console.log(
                "Rate Adjustment Oracle implementation deployed at: ",
                rateAdjustmentOracle
            );

            address rateAdjustmentOracleProxy = address(
                new AMTransparentUpgradeableProxy(
                    rateAdjustmentOracle,
                    initialAuthority,
                    abi.encodeWithSelector(
                        RateAdjustmentOracle.initialize.selector,
                        initialAuthority
                    )
                )
            );

            console.log(
                "Rate Adjustment Oracle Proxy implementation deployed at: ",
                rateAdjustmentOracleProxy
            );

            bytes32 adminSlot = vm.load(
                address(rateAdjustmentOracleProxy),
                ERC1967Utils.ADMIN_SLOT
            );
            address proxyAdmin = address(uint160(uint256(adminSlot)));

            IAccessManager(initialAuthority).setTargetFunctionRole(
                proxyAdmin,
                selectors_proxy_admin,
                Roles.UPGRADE_ROLE
            );
            console.log("Function setTargetFunctionRole Role set for ProxyAdmin");
            testRes = rateAdjustmentOracleProxy;
        } else {
            string memory deploymentNetwork = vm.envString("DEPLOYMENT_NETWORK");
            if (bytes(deploymentNetwork).length == 0) {
                revert("DEPLOYMENT_NETWORK is not set in .env file");
            }

            string memory envVar = string.concat("ACCESS_MANAGER_ADDRESS_", deploymentNetwork);
            if (bytes(vm.envString(envVar)).length == 0) {
                revert(string.concat(envVar, " is not set in .env file"));
            }
            initialAuthority = vm.envAddress(envVar);

            envVar = string.concat("RATE_ADJUSTMENT_ORACLE_ADDRESS_", deploymentNetwork);
            if (bytes(vm.envString(envVar)).length == 0) {
                revert(string.concat(envVar, " is not set in .env file"));
            }
            address rateAdjustmentOracle = vm.envAddress(envVar);

            address rateAdjustmentOracleProxy = address(
                new AMTransparentUpgradeableProxy(
                    rateAdjustmentOracle,
                    initialAuthority,
                    abi.encodeWithSelector(
                        RateAdjustmentOracle.initialize.selector,
                        initialAuthority
                    )
                )
            );
            console.log(
                "Rate Adjustment Oracle Proxy implementation deployed at: ",
                rateAdjustmentOracleProxy
            );

            // Set the roles

            bytes32 adminSlot = vm.load(
                address(rateAdjustmentOracleProxy),
                ERC1967Utils.ADMIN_SLOT
            );
            address proxyAdmin = address(uint160(uint256(adminSlot)));

            IAccessManager(initialAuthority).setTargetFunctionRole(
                proxyAdmin,
                selectors_proxy_admin,
                Roles.UPGRADE_ROLE
            );
            console.log("Function setTargetFunctionRole Role set for ProxyAdmin");
        }

        vm.stopBroadcast();
    }

    function deployForTest(
        address _initialAuthority,
        address _registry,
        address _rateOracleRegistry
    ) public returns (address _testRes) {
        initialAuthority = _initialAuthority;
        registry = _registry;
        rateOracleRegistry = _rateOracleRegistry;
        forTest = true;
        run();
        _testRes = testRes;
        forTest = false;
        initialAuthority = address(0);
        registry = address(0);
        rateOracleRegistry = address(0);
    }
}
