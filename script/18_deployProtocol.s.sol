// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "forge-std/Script.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";
import "../src/Registry.sol";
import "../src/tokens/PrincipalToken.sol";
import "../src/tokens/YieldToken.sol";
import "../src/factory/Factory.sol";
import "../src/proxy/AMBeacon.sol";
import "../src/proxy/AMTransparentUpgradeableProxy.sol";
import "../src/proxy/AMProxyAdmin.sol";
import "../src/router/Router.sol";
import "../src/router/util/RouterUtil.sol";
import "../src/router/util/CurveLiqArbitrage.sol";
import "../src/libraries/Roles.sol";
import "openzeppelin-contracts/access/manager/AccessManager.sol";

// single script similar to scripts 00 to 12
contract DeployProtocolScript is Script {
    bytes4[] private _selectors_proxy_admin = new bytes4[](1);
    bytes4[] private _selectors_beacon = new bytes4[](1);
    bytes4[] private router_selectors = new bytes4[](2);
    bytes4[] private factory_selector = new bytes4[](1);
    bytes4[] private fee_methods_selectors = new bytes4[](5);
    bytes4[] private registry_methods_selectors = new bytes4[](7);

    // params passed as arguments for tests or read in .env otherwise
    address private curveFactoryAddress;
    address private deployer;
    uint256 private tokenizationFee;
    uint256 private yieldFee;
    uint256 private ptFlashLoanFee;
    address private feeCollector;
    address private kyberRouter;

    // addresses returned in tests
    address private registry;
    address private factory;
    address private pt;
    address private curvePool;
    address private router;
    address private routerUtil;
    address private curveLiqArbitrage;

    bool private forTest;

    // struct passed as input
    struct TestInputData {
        address _curveFactoryAddress;
        address _deployer;
        uint256 _tokenizationFee;
        uint256 _yieldFee;
        uint256 _ptFlashLoanFee;
        address _feeCollector;
        address _kyberRouter;
    }

    // misc variables
    struct DeployData {
        string deploymentNetwork;
        address accessManager;
        address accessManagerSuperAdmin;
        address routerInstance;
        address routerProxyAdmin;
        address registryInstance;
        address registryProxyAdmin;
        address factoryInstance;
        address factoryProxyAdmin;
        address ptInstance;
        address ptBeacon;
        address ytInstance;
        address ytBeacon;
        bytes32 adminSlot;
    }

    // struct returned as output
    struct ReturnData {
        address _registry;
        address _factory;
        address _router;
        address _routerUtil;
        address _curveLiqArbitrage;
    }

    function run() public {
        _selectors_proxy_admin[0] = AMProxyAdmin(address(0)).upgradeAndCall.selector;
        _selectors_beacon[0] = AMBeacon(address(0)).upgradeTo.selector;
        fee_methods_selectors[0] = IRegistry(address(0)).setTokenizationFee.selector;
        fee_methods_selectors[1] = IRegistry(address(0)).setYieldFee.selector;
        fee_methods_selectors[2] = IRegistry(address(0)).setPTFlashLoanFee.selector;
        fee_methods_selectors[3] = IRegistry(address(0)).setFeeCollector.selector;
        fee_methods_selectors[4] = IRegistry(address(0)).reduceFee.selector;

        registry_methods_selectors[0] = IRegistry(address(0)).setFactory.selector;
        registry_methods_selectors[1] = IRegistry(address(0)).setPTBeacon.selector;
        registry_methods_selectors[2] = IRegistry(address(0)).setYTBeacon.selector;
        registry_methods_selectors[3] = IRegistry(address(0)).removePT.selector;
        registry_methods_selectors[4] = IRegistry(address(0)).addPT.selector;
        registry_methods_selectors[5] = IRegistry(address(0)).setRouter.selector;
        registry_methods_selectors[6] = IRegistry(address(0)).setRouterUtil.selector;

        router_selectors[0] = Router(payable(address(0))).setRouterUtil.selector;
        router_selectors[1] = Router(payable(address(0))).setKyberRouter.selector;
        factory_selector[0] = Factory(payable(address(0))).setCurveFactory.selector;

        vm.startBroadcast();

        DeployData memory data;

        data.deploymentNetwork = vm.envString("DEPLOYMENT_NETWORK");
        if (bytes(data.deploymentNetwork).length == 0) {
            revert("DEPLOYMENT_NETWORK is not set in .env file");
        }

        string memory envVar;

        // --- Access Manager (script 00) ---
        // We assume here that the deployer is the initial SUPER_ADMIN of the AccessManager
        // The deployer needs to perform super admin operations and later grant the super
        // admin role to another address and revoke its roles
        if (!forTest) {
            // get deployer address from .env
            envVar = string.concat("DEPLOYER_ADDRESS_", data.deploymentNetwork);
            if (bytes(vm.envString(envVar)).length == 0) {
                revert(string.concat(envVar, " is not set in .env file"));
            }
            deployer = vm.envAddress(envVar);
            if (deployer == address(0)) {
                revert("Deployer cannot be address 0");
            }
            envVar = string.concat("ACCESS_MANAGER_ADMIN_", data.deploymentNetwork);
            if (bytes(vm.envString(envVar)).length == 0) {
                revert(string.concat(envVar, " is not set in .env file"));
            }
            data.accessManagerSuperAdmin = vm.envAddress(envVar);
            if (data.accessManagerSuperAdmin == address(0)) {
                revert("Access Manager Super Admin cannot be address 0");
            }
        }

        data.accessManager = address(new AccessManager(deployer));

        console.log(
            "AccessManager instance deployed at",
            data.accessManager,
            "with super admin",
            deployer
        );

        IAccessManager(data.accessManager).grantRole(Roles.REGISTRY_ROLE, deployer, 0);
        IAccessManager(data.accessManager).grantRole(Roles.FEE_SETTER_ROLE, deployer, 0);

        // --- Registry Instance and Proxy (script 01) ---
        data.registryInstance = address(new Registry());
        console.log("Registry instance deployed at", data.registryInstance);

        registry = address(
            new AMTransparentUpgradeableProxy(
                data.registryInstance,
                data.accessManager,
                abi.encodeWithSelector(Registry(address(0)).initialize.selector, data.accessManager)
            )
        );

        console.log("Registry proxy deployed at", registry);

        if (!forTest) {
            // get tokenization fee from .env
            envVar = string.concat("TOKENIZATION_FEE_", data.deploymentNetwork);
            if (bytes(vm.envString(envVar)).length == 0) {
                revert(string.concat(envVar, " is not set in .env file"));
            }
            tokenizationFee = vm.envUint(envVar);

            // get yield fee from .env
            envVar = string.concat("YIELD_FEE_", data.deploymentNetwork);
            if (bytes(vm.envString(envVar)).length == 0) {
                revert(string.concat(envVar, " is not set in .env file"));
            }
            yieldFee = vm.envUint(envVar);

            // get pt flashloan fee from .env
            envVar = string.concat("PT_FLASH_LOAN_FEE_", data.deploymentNetwork);
            if (bytes(vm.envString(envVar)).length == 0) {
                revert(string.concat(envVar, " is not set in .env file"));
            }
            ptFlashLoanFee = vm.envUint(envVar);

            // get fee collector from .env
            envVar = string.concat("FEE_COLLECTOR_", data.deploymentNetwork);
            if (bytes(vm.envString(envVar)).length == 0) {
                revert(string.concat(envVar, " is not set in .env file"));
            }
            feeCollector = vm.envAddress(envVar);

            // get Curve Address Provider from .env
            envVar = string.concat("CURVE_FACTORY_", data.deploymentNetwork);
            if (bytes(vm.envString(envVar)).length == 0) {
                revert(string.concat(envVar, " is not set in .env file"));
            }
            curveFactoryAddress = vm.envAddress(envVar);

            // get Kyber Router from .env
            envVar = string.concat("KYBER_ROUTER_", data.deploymentNetwork);
            if (bytes(vm.envString(envVar)).length == 0) {
                revert(string.concat(envVar, " is not set in .env file"));
            }
            kyberRouter = vm.envAddress(envVar);
        }

        IRegistry(registry).setTokenizationFee(tokenizationFee);
        IRegistry(registry).setYieldFee(yieldFee);
        IRegistry(registry).setPTFlashLoanFee(ptFlashLoanFee);
        IRegistry(registry).setFeeCollector(feeCollector);

        IAccessManager(data.accessManager).setTargetFunctionRole(
            registry,
            fee_methods_selectors,
            Roles.FEE_SETTER_ROLE
        );
        IAccessManager(data.accessManager).setTargetFunctionRole(
            registry,
            registry_methods_selectors,
            Roles.REGISTRY_ROLE
        );

        data.adminSlot = vm.load(registry, ERC1967Utils.ADMIN_SLOT);
        data.registryProxyAdmin = address(uint160(uint256(data.adminSlot)));
        console.log("Registry Proxy Admin Address:", data.registryProxyAdmin);
        IAccessManager(data.accessManager).setTargetFunctionRole(
            data.registryProxyAdmin,
            _selectors_proxy_admin,
            Roles.UPGRADE_ROLE
        );
        console.log("Function setTargetFunctionRole Role set for Registry ProxyAdmin");

        // --- PrincipalToken Instance (script 02) ---
        data.ptInstance = address(new PrincipalToken(registry));
        console.log("PrincipalToken instance deployed at", data.ptInstance);

        // --- YT Instance (script 03) ---
        data.ytInstance = address(new YieldToken());
        console.log("YT instance deployed at", data.ytInstance);

        // --- PrincipalToken Beacon Upgradeable (script 04) ---
        data.ptBeacon = address(new AMBeacon(data.ptInstance, data.accessManager));
        console.log("PrincipalTokenBeaconUpgradeable deployed at", data.ptBeacon);
        IAccessManager(data.accessManager).setTargetFunctionRole(
            data.ptBeacon,
            _selectors_beacon,
            Roles.UPGRADE_ROLE
        );
        console.log("Function setTargetFunctionRole Role set for PrincipalTokenBeacon");
        IRegistry(registry).setPTBeacon(data.ptBeacon);

        // --- YT Beacon Upgradeable (script 05) ---
        data.ytBeacon = address(new AMBeacon(data.ytInstance, data.accessManager));
        console.log("YTBeaconUpgradeable deployed at", data.ytBeacon);
        IAccessManager(data.accessManager).setTargetFunctionRole(
            data.ytBeacon,
            _selectors_beacon,
            Roles.UPGRADE_ROLE
        );
        console.log("Function setTargetFunctionRole Role set for YTBeacon");
        IRegistry(registry).setYTBeacon(data.ytBeacon);

        // --- Factory Instance and Proxy (script 06) ---
        data.factoryInstance = address(new Factory(registry));
        console.log("Factory instance deployed at", data.factoryInstance);
        factory = address(
            new AMTransparentUpgradeableProxy(
                data.factoryInstance,
                data.accessManager,
                abi.encodeWithSelector(
                    Factory(address(0)).initialize.selector,
                    data.accessManager,
                    curveFactoryAddress
                )
            )
        );
        console.log("Factory proxy deployed at", factory);
        data.adminSlot = vm.load(factory, ERC1967Utils.ADMIN_SLOT);
        data.factoryProxyAdmin = address(uint160(uint256(data.adminSlot)));
        console.log("Factory Proxy Admin Address:", data.factoryProxyAdmin);

        IAccessManager(data.accessManager).setTargetFunctionRole(
            data.factoryProxyAdmin,
            _selectors_proxy_admin,
            Roles.UPGRADE_ROLE
        );
        IAccessManager(data.accessManager).setTargetFunctionRole(
            factory,
            factory_selector,
            Roles.REGISTRY_ROLE
        );
        console.log("Function setTargetFunctionRole Role set for Factory ProxyAdmin");
        // Whitelisting the factory proxy in the AccessManager
        IAccessManager(data.accessManager).grantRole(Roles.ADMIN_ROLE, factory, 0);
        IAccessManager(data.accessManager).grantRole(Roles.REGISTRY_ROLE, factory, 0);
        console.log("Factory role added to AccessManager contract");
        IRegistry(registry).setFactory(factory);

        // --- Router and RouterUtil (script 09) ---
        routerUtil = address(new RouterUtil());
        console.log("RouterUtil deployed at", routerUtil);
        curveLiqArbitrage = address(new CurveLiqArbitrage());
        console.log("CurveLiqArbitrage deployed at", curveLiqArbitrage);
        data.routerInstance = address(new Router(registry));
        console.log("Router instance deployed at", data.routerInstance);
        router = address(
            new AMTransparentUpgradeableProxy(
                data.routerInstance,
                data.accessManager,
                abi.encodeWithSelector(
                    Router(payable(address(0))).initialize.selector,
                    routerUtil,
                    kyberRouter,
                    data.accessManager
                )
            )
        );
        data.adminSlot = vm.load(router, ERC1967Utils.ADMIN_SLOT);
        data.routerProxyAdmin = address(uint160(uint256(data.adminSlot)));
        console.log("Router Proxy Admin Address:", data.routerProxyAdmin);
        console.log("Router deployed at", router);
        IAccessManager(data.accessManager).setTargetFunctionRole(
            router,
            router_selectors,
            Roles.UPGRADE_ROLE
        );
        IAccessManager(data.accessManager).setTargetFunctionRole(
            data.routerProxyAdmin,
            _selectors_proxy_admin,
            Roles.UPGRADE_ROLE
        );
        IRegistry(registry).setRouter(router);
        IRegistry(registry).setRouterUtil(routerUtil);

        if (!forTest) {
            // At the end of deployment Grand role in AccessManager
            // to the super admin and remove the deployer roles
            IAccessManager(data.accessManager).grantRole(
                Roles.ADMIN_ROLE,
                data.accessManagerSuperAdmin,
                0
            );
            IAccessManager(data.accessManager).grantRole(
                Roles.UPGRADE_ROLE,
                data.accessManagerSuperAdmin,
                0
            );
            IAccessManager(data.accessManager).grantRole(
                Roles.PAUSER_ROLE,
                data.accessManagerSuperAdmin,
                0
            );
            IAccessManager(data.accessManager).grantRole(
                Roles.REGISTRY_ROLE,
                data.accessManagerSuperAdmin,
                0
            );
            IAccessManager(data.accessManager).grantRole(
                Roles.FEE_SETTER_ROLE,
                data.accessManagerSuperAdmin,
                0
            );
            IAccessManager(data.accessManager).grantRole(
                Roles.REWARDS_HARVESTER_ROLE,
                data.accessManagerSuperAdmin,
                0
            );
            IAccessManager(data.accessManager).grantRole(
                Roles.REWARDS_PROXY_SETTER_ROLE,
                data.accessManagerSuperAdmin,
                0
            );
            if (data.accessManagerSuperAdmin != deployer) {
                IAccessManager(data.accessManager).revokeRole(Roles.REGISTRY_ROLE, deployer);
                IAccessManager(data.accessManager).revokeRole(Roles.FEE_SETTER_ROLE, deployer);
                IAccessManager(data.accessManager).revokeRole(Roles.ADMIN_ROLE, deployer);
            }
        }
        vm.stopBroadcast();
    }

    function deployForTest(
        TestInputData memory inputData
    ) public returns (ReturnData memory _returnData) {
        forTest = true;
        curveFactoryAddress = inputData._curveFactoryAddress;
        deployer = inputData._deployer;
        tokenizationFee = inputData._tokenizationFee;
        yieldFee = inputData._yieldFee;
        ptFlashLoanFee = inputData._ptFlashLoanFee;
        feeCollector = inputData._feeCollector;
        kyberRouter = inputData._kyberRouter;
        run();
        forTest = false;
        curveFactoryAddress = address(0);
        deployer = address(0);
        tokenizationFee = 0;
        yieldFee = 0;
        ptFlashLoanFee = 0;
        feeCollector = address(0);
        kyberRouter = address(0);
        _returnData._registry = registry;
        _returnData._factory = factory;
        _returnData._router = router;
        _returnData._routerUtil = routerUtil;
        _returnData._curveLiqArbitrage = curveLiqArbitrage;
        registry = address(0);
        factory = address(0);
        pt = address(0);
        curvePool = address(0);
        router = address(0);
        routerUtil = address(0);
        curveLiqArbitrage = address(0);
    }
}
