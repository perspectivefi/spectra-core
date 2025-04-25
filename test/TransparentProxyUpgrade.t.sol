// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.20;

import "forge-std/Test.sol";

import "../src/mocks/MockFactoryV2.sol";
import "../src/mocks/MockRouter.sol";
import "../script/00_deployAccessManager.s.sol";
import "../script/01_deployRegistry.s.sol";
import "../script/09_deployRouter.s.sol";
import "../script/06_deployFactory.s.sol";
import "../script/15_upgradeTransparentProxy.s.sol";
import "../src/libraries/Roles.sol";
import "openzeppelin-contracts/proxy/beacon/UpgradeableBeacon.sol";

contract TransparentProxyUpgrade is Test {
    Registry public registry;
    AccessManager public accessManager;
    address public admin;
    address public scriptAdmin;
    address public curveFactoryAddress = address(0xfac);
    address public kyberRouterAddr;
    address feeCollector = 0x0000000000000000000000000000000000000FEE;
    address MOCK_ADDR_1 = 0x0000000000000000000000000000000000000001;
    address MOCK_ADDR_2 = 0x0000000000000000000000000000000000000002;
    uint256 public TOKENIZATION_FEE = 1e15;
    uint256 public YIELD_FEE = 0;
    uint256 public PT_FLASH_LOAN_FEE = 0;

    /**
     * @dev This function is called before each test.
     */
    function setUp() public {
        admin = address(this);
        // default account for deploying scripts contracts. refer to line 35 of
        // https://github.com/foundry-rs/foundry/blob/master/evm/src/lib.rs for more details
        scriptAdmin = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;
        AccessManagerDeploymentScript accessManagerScript = new AccessManagerDeploymentScript();
        accessManager = AccessManager(accessManagerScript.deployForTest(scriptAdmin));
        RegistryScript registryScript = new RegistryScript();
        registry = Registry(
            registryScript.deployForTest(
                TOKENIZATION_FEE,
                YIELD_FEE,
                PT_FLASH_LOAN_FEE,
                feeCollector,
                address(accessManager)
            )
        );
        vm.startBroadcast();
        accessManager.grantRole(Roles.REGISTRY_ROLE, scriptAdmin, 0);
        accessManager.grantRole(Roles.FEE_SETTER_ROLE, scriptAdmin, 0);
        vm.stopBroadcast();
    }

    function testUpgradeFactoryFailsWithWrongOwner() public {
        FactoryScript factoryScript = new FactoryScript();
        address factory = factoryScript.deployForTest(
            address(registry),
            curveFactoryAddress,
            address(accessManager)
        );
        MockFactoryV2 mockFactoryV2Instance = new MockFactoryV2(address(registry));

        bytes32 adminSlot = vm.load(factory, ERC1967Utils.ADMIN_SLOT);
        address proxyAdmin = address(uint160(uint256(adminSlot)));

        bytes memory revertData = abi.encodeWithSelector(
            bytes4(keccak256("AccessManagedUnauthorized(address)")),
            admin
        );
        vm.expectRevert(revertData);
        // calling upgradeAndCall here as "admin", not "scriptAdmin"
        ProxyAdmin(proxyAdmin).upgradeAndCall(
            ITransparentUpgradeableProxy(factory),
            address(mockFactoryV2Instance),
            ""
        );
    }

    function testUpgradeRouterFailsWithWrongOwner() public {
        RouterScript routerScript = new RouterScript();
        (address router, , ) = routerScript.deployForTest(
            address(registry),
            kyberRouterAddr,
            address(accessManager)
        );

        address router2 = address(new Router(address(registry)));

        bytes32 adminSlot = vm.load(router, ERC1967Utils.ADMIN_SLOT);
        address proxyAdmin = address(uint160(uint256(adminSlot)));

        bytes memory revertData = abi.encodeWithSelector(
            bytes4(keccak256("AccessManagedUnauthorized(address)")),
            admin
        );
        vm.expectRevert(revertData);
        // calling upgradeAndCall here as "admin", not "scriptAdmin"
        ProxyAdmin(proxyAdmin).upgradeAndCall(
            ITransparentUpgradeableProxy(router),
            address(router2),
            ""
        );
    }

    function testUpgradeRouterFailsWithWrongProxyAdmin() public {
        RouterScript routerScript = new RouterScript();
        (address router, , ) = routerScript.deployForTest(
            address(registry),
            kyberRouterAddr,
            address(accessManager)
        );

        address router2 = address(new Router(address(registry)));

        bytes32 adminSlot = vm.load(address(registry), ERC1967Utils.ADMIN_SLOT);
        address proxyAdmin = address(uint160(uint256(adminSlot)));

        // We first need to grant UPGRADE_ROLE to scriptAdmin
        vm.prank(scriptAdmin);
        accessManager.grantRole(Roles.UPGRADE_ROLE, scriptAdmin, 0);

        vm.expectRevert(); // EvmError: Revert
        vm.prank(scriptAdmin);
        ProxyAdmin(proxyAdmin).upgradeAndCall(
            ITransparentUpgradeableProxy(router),
            address(router2),
            ""
        );
    }

    function testUpgradeRouter() public {
        RouterScript routerScript = new RouterScript();
        (address router, , ) = routerScript.deployForTest(
            address(registry),
            kyberRouterAddr,
            address(accessManager)
        );

        address router2 = address(new MockRouter());

        // We first need to grant UPGRADE_ROLE to scriptAdmin
        vm.prank(scriptAdmin);
        accessManager.grantRole(Roles.UPGRADE_ROLE, scriptAdmin, 0);

        // upgrade transparent proxy
        UpgradeTransparentProxyScript upgradeTransparentProxyScript = new UpgradeTransparentProxyScript();
        upgradeTransparentProxyScript.upgradeForTest(address(router), address(router2));
        assertTrue(MockRouter(router).upgraded());
    }

    function testUpgradeFactoryFailsWithWrongProxyAdmin() public {
        FactoryScript factoryScript = new FactoryScript();
        address factory = factoryScript.deployForTest(
            address(registry),
            curveFactoryAddress,
            address(accessManager)
        );
        MockFactoryV2 mockFactoryV2Instance = new MockFactoryV2(address(registry));

        // getting registry's proxyAdmin instead of factory's
        bytes32 adminSlot = vm.load(address(registry), ERC1967Utils.ADMIN_SLOT);
        address proxyAdmin = address(uint160(uint256(adminSlot)));

        // We first need to grant UPGRADE_ROLE to scriptAdmin
        vm.prank(scriptAdmin);
        accessManager.grantRole(Roles.UPGRADE_ROLE, scriptAdmin, 0);

        vm.startBroadcast();
        vm.expectRevert();
        ProxyAdmin(proxyAdmin).upgradeAndCall(
            ITransparentUpgradeableProxy(factory),
            address(mockFactoryV2Instance),
            ""
        );
        vm.stopBroadcast();
    }

    function testUpgradeFactory() public {
        FactoryScript factoryScript = new FactoryScript();
        address factory = factoryScript.deployForTest(
            address(registry),
            curveFactoryAddress,
            address(accessManager)
        );
        assertEq(IFactory(factory).getRegistry(), address(registry));

        MockFactoryV2 mockFactoryV2Instance = new MockFactoryV2(address(registry));
        // We first need to grant UPGRADE_ROLE to scriptAdmin
        vm.prank(scriptAdmin);
        accessManager.grantRole(Roles.UPGRADE_ROLE, scriptAdmin, 0);
        // upgrade transparent proxy
        UpgradeTransparentProxyScript upgradeTransparentProxyScript = new UpgradeTransparentProxyScript();
        upgradeTransparentProxyScript.upgradeForTest(
            address(factory),
            address(mockFactoryV2Instance)
        );
        assertEq(IFactory(factory).getRegistry(), address(1));
    }

    function testTransferFactoryProxyOwnership() public {
        FactoryScript factoryScript = new FactoryScript();
        address factory = factoryScript.deployForTest(
            address(registry),
            curveFactoryAddress,
            address(accessManager)
        );

        bytes32 adminSlot = vm.load(factory, ERC1967Utils.ADMIN_SLOT);
        address proxyAdmin = address(uint160(uint256(adminSlot)));

        MockFactoryV2 mockFactoryV2Instance = new MockFactoryV2(address(registry));

        // Set MOCK_ADDR_1 with UPGRADE_ROLE
        vm.prank(scriptAdmin);
        accessManager.grantRole(Roles.UPGRADE_ROLE, MOCK_ADDR_1, 0);
        // MOCK_ADDR_2 can't upgrade proxyAdmin
        bytes memory revertData = abi.encodeWithSelector(
            bytes4(keccak256("AccessManagedUnauthorized(address)")),
            MOCK_ADDR_2
        );
        vm.expectRevert(revertData);
        // verify MOCK_ADDR_2 cannot upgrade proxyAdmin
        vm.prank(MOCK_ADDR_2);
        ProxyAdmin(proxyAdmin).upgradeAndCall(
            ITransparentUpgradeableProxy(factory),
            address(mockFactoryV2Instance),
            ""
        );

        // transfer proxyAdmin ownership from MOCK_ADDR_1 to MOCK_ADDR_2
        vm.startPrank(scriptAdmin);
        accessManager.grantRole(Roles.UPGRADE_ROLE, MOCK_ADDR_2, 0);
        accessManager.revokeRole(Roles.UPGRADE_ROLE, MOCK_ADDR_1);
        vm.stopPrank();
        revertData = abi.encodeWithSelector(
            bytes4(keccak256("AccessManagedUnauthorized(address)")),
            MOCK_ADDR_1
        );
        // verify MOCK_ADDR_1 cannot upgrade proxyAdmin anymore
        vm.expectRevert(revertData);
        vm.prank(MOCK_ADDR_1);
        ProxyAdmin(proxyAdmin).upgradeAndCall(
            ITransparentUpgradeableProxy(factory),
            address(mockFactoryV2Instance),
            ""
        );
        vm.prank(MOCK_ADDR_2);
        // verify MOCK_ADDR_2 can upgrade proxyAdmin
        ProxyAdmin(proxyAdmin).upgradeAndCall(
            ITransparentUpgradeableProxy(factory),
            address(mockFactoryV2Instance),
            ""
        );

        assertEq(IFactory(factory).getRegistry(), address(1));
    }

    /**
     * This test is to verify that the upgradeToAndCall function of the AMTransparentProxy
     * when called from the proxyAdmin address but with a function selector other than
     * upgradeToAndCall() reverts.
     */
    function testUnauthorizeedUpgradeCall() public {
        FactoryScript factoryScript = new FactoryScript();
        address factory = factoryScript.deployForTest(
            address(registry),
            curveFactoryAddress,
            address(accessManager)
        );
        bytes32 adminSlot = vm.load(factory, ERC1967Utils.ADMIN_SLOT);
        address proxyAdmin = address(uint160(uint256(adminSlot)));

        bytes memory revertData = abi.encodeWithSelector(
            bytes4(keccak256("ProxyDeniedAdminAccess()"))
        );

        bytes4 nonUpgradeFunctionSelector = bytes4(
            keccak256("someFunctionOtherThanUpgradeToAndCall()")
        );
        bytes memory callData = abi.encodeWithSelector(nonUpgradeFunctionSelector);
        vm.prank(proxyAdmin);
        (bool success, bytes memory execData) = address(factory).call(callData);
        assertFalse(success);
        assertEq(revertData, execData);
    }
}
