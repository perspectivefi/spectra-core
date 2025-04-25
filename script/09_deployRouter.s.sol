// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "forge-std/Script.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";
import "../src/router/Router.sol";
import "../src/interfaces/IRegistry.sol";
import "../src/router/util/RouterUtil.sol";
import "../src/router/util/CurveLiqArbitrage.sol";
import "../src/libraries/Roles.sol";
import "../src/proxy/AMTransparentUpgradeableProxy.sol";
import "../src/proxy/AMProxyAdmin.sol";
import "openzeppelin-contracts/access/manager/AccessManager.sol";

contract RouterScript is Script {
    bytes4[] private _selectors_proxy_admin = new bytes4[](1);
    address payable private router;
    address private routerUtil;
    address private curveLiqArbitrage;
    address private kyberRouter;
    address private accessManager;
    bytes4[] private router_selector = new bytes4[](3);
    address private registry;
    bool private forTest;

    function run() public {
        _selectors_proxy_admin[0] = AMProxyAdmin(address(0)).upgradeAndCall.selector;
        router_selector[0] = Router(payable(address(0))).setRouterUtil.selector;
        router_selector[1] = Router(payable(address(0))).setKyberRouter.selector;
        vm.startBroadcast();

        if (!forTest) {
            string memory deploymentNetwork = vm.envString("DEPLOYMENT_NETWORK");
            if (bytes(deploymentNetwork).length == 0) {
                revert("DEPLOYMENT_NETWORK is not set in .env file");
            }
            string memory envVar = string.concat("REGISTRY_ADDR_", deploymentNetwork);
            if (bytes(vm.envString(envVar)).length == 0) {
                revert(string.concat(envVar, " is not set in .env file"));
            }
            registry = vm.envAddress(envVar);

            envVar = string.concat("ACCESS_MANAGER_ADDRESS_", deploymentNetwork);
            if (bytes(vm.envString(envVar)).length == 0) {
                revert(string.concat(envVar, " is not set in .env file"));
            }
            accessManager = vm.envAddress(envVar);

            envVar = string.concat("KYBER_ROUTER_ADDRESS_", deploymentNetwork);
            if (bytes(vm.envString(envVar)).length == 0) {
                revert(string.concat(envVar, " is not set in .env file"));
            }
            kyberRouter = vm.envAddress(envVar);
        }

        routerUtil = address(new RouterUtil());
        console.log("RouterUtil deployed at", routerUtil);
        curveLiqArbitrage = address(new CurveLiqArbitrage());
        console.log("CurveLiqArbitrage deployed at", curveLiqArbitrage);
        address routerInstance = address(new Router(registry));
        console.log("Router instance deployed at", routerInstance);
        router = payable(
            address(
                new AMTransparentUpgradeableProxy(
                    routerInstance,
                    accessManager,
                    abi.encodeWithSelector(
                        Router(payable(address(0))).initialize.selector,
                        routerUtil,
                        kyberRouter,
                        accessManager
                    )
                )
            )
        );
        bytes32 adminSlot = vm.load(router, ERC1967Utils.ADMIN_SLOT);
        address routerProxyAdmin = address(uint160(uint256(adminSlot)));
        console.log("Router Proxy Admin Address:", routerProxyAdmin);
        console.log("Router deployed at", router);
        IAccessManager(accessManager).setTargetFunctionRole(
            router,
            router_selector,
            Roles.UPGRADE_ROLE
        );
        IAccessManager(accessManager).setTargetFunctionRole(
            routerProxyAdmin,
            _selectors_proxy_admin,
            Roles.UPGRADE_ROLE
        );
        IRegistry(registry).setRouter(router);
        IRegistry(registry).setRouterUtil(routerUtil);
        vm.stopBroadcast();
    }

    function deployForTest(
        address _registry,
        address _kyberRouter,
        address _accessManager
    )
        public
        returns (
            address payable _testRouterRes,
            address _testRouterUtilRes,
            address _testCurveLiqArbitrage
        )
    {
        forTest = true;
        registry = _registry;
        kyberRouter = _kyberRouter;
        accessManager = _accessManager;
        run();
        _testRouterRes = router;
        _testRouterUtilRes = routerUtil;
        _testCurveLiqArbitrage = curveLiqArbitrage;
        router = payable(address(0));
        routerUtil = address(0);
        curveLiqArbitrage = address(0);
        forTest = false;
        accessManager = address(0);
    }
}
