// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockIBT.sol";
import "../src/mocks/MockPrincipalTokenV2.sol";
import "../src/mocks/MockRateAdjustmentOracle1.sol";
import "../src/mocks/MockRateAdjustmentOracle2.sol";
import "../src/mocks/MockYieldTokenV2.sol";
import "../script/00_deployAccessManager.s.sol";
import "../script/01_deployRegistry.s.sol";
import "../script/22_deployRateOracleRegistry.s.sol";
import "../script/23_deployFactorySNG.s.sol";
import "../script/24_deployRateAdjustmentOracleInstance.s.sol";
import "../script/25_deployRateAdjustmentOracleBeacon.s.sol";
import "../script/02_deployPrincipalTokenInstance.s.sol";
import "../script/03_deployYTInstance.s.sol";
import "../script/04_deployPrincipalTokenBeacon.s.sol";
import "../script/05_deployYTBeacon.s.sol";
import "../script/06_deployFactory.s.sol";
import "../script/07_deployPrincipalToken.s.sol";
import "../script/14_upgradeBeaconImplementation.s.sol";
import "../src/libraries/Roles.sol";

contract BeaconProxyUpgrade is Test {
    struct UserDataBeforeAfter {
        uint256 userPTBalanceBefore1;
        uint256 userPTBalanceAfter1;
        uint256 userYTBalanceBefore1;
        uint256 userYTBalanceAfter1;
        uint256 userUnderlyingBalanceBefore1;
        uint256 userUnderlyingBalanceAfter1;
        uint256 userYieldBefore1;
        uint256 userYieldAfter1;
        uint256 userPTBalanceBefore2;
        uint256 userPTBalanceAfter2;
        uint256 userYTBalanceBefore2;
        uint256 userYTBalanceAfter2;
        uint256 userUnderlyingBalanceBefore2;
        uint256 userUnderlyingBalanceAfter2;
        uint256 userYieldBefore2;
        uint256 userYieldAfter2;
    }

    uint256 fork;

    Factory public factory;
    FactorySNG public factorySNG;
    AccessManager public accessManager;
    MockERC20 public underlying;
    MockIBT public ibt;
    uint256 public DURATION = 100000;
    uint256 public IBT_UNIT;
    Registry public registry;
    RateOracleRegistry raoRegistry;
    address public admin;
    address public scriptAdmin;
    address public curveFactoryAddress = address(0xfac);
    address public curveFactorySNGAddress = 0x6A8cbed756804B16E05E741eDaBd5cB544AE21bf;
    address feeCollector = 0x0000000000000000000000000000000000000FEE;
    address MOCK_ADDR_1 = 0x0000000000000000000000000000000000000001;
    address MOCK_ADDR_2 = 0x0000000000000000000000000000000000000002;
    uint256 public TOKENIZATION_FEE = 1e15;
    uint256 public YIELD_FEE = 0;
    uint256 public PT_FLASH_LOAN_FEE = 0;
    UpgradeableBeacon public principalTokenBeacon;
    UpgradeableBeacon public ytBeacon;
    UpgradeableBeacon public raoBeacon;

    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    /**
     * @dev This function is called before each test.
     */
    function setUp() public {
        fork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(fork);
        admin = address(this);
        // default account for deploying scripts contracts. refer to line 35 of
        // https://github.com/foundry-rs/foundry/blob/master/evm/src/lib.rs for more details
        scriptAdmin = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;
        // Access Manager
        AccessManagerDeploymentScript accessManagerScript = new AccessManagerDeploymentScript();
        accessManager = AccessManager(accessManagerScript.deployForTest(scriptAdmin));
        vm.prank(scriptAdmin);
        accessManager.grantRole(Roles.UPGRADE_ROLE, scriptAdmin, 0);

        // deploy the registry
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

        // grant roles for the registry
        vm.prank(scriptAdmin);
        accessManager.grantRole(Roles.REGISTRY_ROLE, scriptAdmin, 0);
        vm.prank(scriptAdmin);
        accessManager.grantRole(Roles.FEE_SETTER_ROLE, scriptAdmin, 0);

        // deploy the rate oracle registry
        RateOracleRegistryScript raoScript = new RateOracleRegistryScript();
        raoRegistry = RateOracleRegistry(raoScript.deployForTest(address(accessManager)));
        // grant roles for the rate oracle registry
        vm.prank(scriptAdmin);
        accessManager.grantRole(Roles.REGISTRY_ROLE, scriptAdmin, 0);
        vm.prank(scriptAdmin);
        accessManager.grantRole(Roles.RATE_ADJUSTMENT_ORACLE_SETTER_ROLE, scriptAdmin, 0);

        underlying = new MockERC20();
        underlying.initialize("MOCK UNDERLYING", "MUDL"); // deploys underlying mints 100000e18 token to caller
        ibt = new MockIBT();
        ibt.initialize("MOCK IBT", "MIBT", IERC20Metadata(address(underlying))); // deploys ibt which principalToken holds
        IBT_UNIT = 10 ** ibt.decimals();

        // deposit assets in IBT
        underlying.mint(address(this), 1);
        underlying.approve(address(ibt), 1);
        ibt.deposit(1, address(this));

        // PT, YT and rate adjustment oracle instances
        PrincipalTokenInstanceScript principalTokenInstanceScript = new PrincipalTokenInstanceScript();
        YTInstanceScript ytInstanceScript = new YTInstanceScript();
        PrincipalToken principalTokenInstance = PrincipalToken(
            principalTokenInstanceScript.deployForTest(address(registry))
        );
        YieldToken ytInstance = YieldToken(ytInstanceScript.deployForTest());
        RateAdjustmentOracleInstanceScript raoInstanceScript = new RateAdjustmentOracleInstanceScript();
        RateAdjustmentOracle raoInstance = RateAdjustmentOracle(raoInstanceScript.deployForTest());

        // PT, YT and Rate Adjustment Oracle beacons
        PrincipalTokenBeaconScript principalTokenBeaconScript = new PrincipalTokenBeaconScript();
        YTBeaconScript ytBeaconScript = new YTBeaconScript();
        RateAdjustmentOracleBeaconScript raoBeaconScript = new RateAdjustmentOracleBeaconScript();
        principalTokenBeacon = UpgradeableBeacon(
            principalTokenBeaconScript.deployForTest(
                address(principalTokenInstance),
                address(registry),
                address(accessManager)
            )
        );
        ytBeacon = UpgradeableBeacon(
            ytBeaconScript.deployForTest(
                address(ytInstance),
                address(registry),
                address(accessManager)
            )
        );
        raoBeacon = UpgradeableBeacon(
            raoBeaconScript.deployForTest(
                address(raoInstance),
                address(raoRegistry),
                address(accessManager)
            )
        );
        vm.prank(scriptAdmin);

        // Factory
        FactoryScript factoryScript = new FactoryScript();
        factory = Factory(
            factoryScript.deployForTest(
                address(registry),
                curveFactoryAddress,
                address(accessManager)
            )
        );

        vm.prank(scriptAdmin);
        accessManager.grantRole(Roles.ADMIN_ROLE, address(factory), 0);
        vm.prank(scriptAdmin);
        accessManager.grantRole(Roles.REGISTRY_ROLE, address(factory), 0);

        FactorySNGScript factorySNGScript = new FactorySNGScript();
        factorySNG = FactorySNG(
            factorySNGScript.deployForTest(
                address(registry),
                address(raoRegistry),
                curveFactorySNGAddress,
                address(accessManager)
            )
        );

        vm.prank(scriptAdmin);
        accessManager.grantRole(Roles.ADMIN_ROLE, address(factorySNG), 0);
        vm.prank(scriptAdmin);
        accessManager.grantRole(Roles.REGISTRY_ROLE, address(factorySNG), 0);
    }

    function testUpgradeRateAdjustmentOracleWithWrongOwner() public {
        MockRateAdjustmentOracle1 raoOracleInstance = new MockRateAdjustmentOracle1();
        bytes memory revertData = abi.encodeWithSelector(
            bytes4(keccak256("AccessManagedUnauthorized(address)")),
            admin
        );
        vm.expectRevert(revertData);
        // calling upgradeTo here as "admin", not "scriptAdmin"
        UpgradeableBeacon(raoBeacon).upgradeTo(address(raoOracleInstance));
    }

    function testUpgradePTFailsWithWrongOwner() public {
        MockPrincipalTokenV2 mockPrincipalTokenV2Instance = new MockPrincipalTokenV2(
            address(registry)
        );

        bytes memory revertData = abi.encodeWithSelector(
            bytes4(keccak256("AccessManagedUnauthorized(address)")),
            admin
        );
        vm.expectRevert(revertData);
        // calling upgradeTo here as "admin", not "scriptAdmin"
        UpgradeableBeacon(principalTokenBeacon).upgradeTo(address(mockPrincipalTokenV2Instance));
    }

    function testUpgradePTBeaconImplementation() public {
        MockPrincipalTokenV2 mockPrincipalTokenV2Instance = new MockPrincipalTokenV2(
            address(registry)
        );
        // upgrade beacon
        UpgradeBeaconLogicScript upgradeBeaconLogicScript = new UpgradeBeaconLogicScript();
        upgradeBeaconLogicScript.upgradeForTest(
            address(principalTokenBeacon),
            address(mockPrincipalTokenV2Instance)
        );
        assertEq(principalTokenBeacon.implementation(), address(mockPrincipalTokenV2Instance));
    }

    function testUpgradeRaoBeaconImplementation() public {
        MockRateAdjustmentOracle1 raoOracleInstance = new MockRateAdjustmentOracle1();
        // upgrade beacon
        UpgradeBeaconLogicScript upgradeBeaconLogicScript = new UpgradeBeaconLogicScript();
        upgradeBeaconLogicScript.upgradeForTest(address(raoBeacon), address(raoOracleInstance));
        assertEq(raoBeacon.implementation(), address(raoOracleInstance));
    }

    function testUpgradeForNewPT() public {
        UserDataBeforeAfter memory data;
        PrincipalTokenScript principalTokenScript = new PrincipalTokenScript();
        principalTokenScript.deployForTest(address(factory), address(ibt), DURATION);

        MockPrincipalTokenV2 mockPrincipalTokenV2Instance = new MockPrincipalTokenV2(
            address(registry)
        );
        // upgrade beacon
        UpgradeBeaconLogicScript upgradeBeaconLogicScript = new UpgradeBeaconLogicScript();
        upgradeBeaconLogicScript.upgradeForTest(
            address(principalTokenBeacon),
            address(mockPrincipalTokenV2Instance)
        );

        // deploys a second principalToken with same parameters
        address _principalTokenAddress2 = principalTokenScript.deployForTest(
            address(factory),
            address(ibt),
            DURATION
        );
        IPrincipalToken pt2 = IPrincipalToken(_principalTokenAddress2);
        address ytAddress2 = pt2.getYT();
        IYieldToken yt2 = IYieldToken(ytAddress2);
        assertEq(
            pt2.symbol(),
            string.concat("PT-MIBT-", vm.toString(block.timestamp + DURATION), "V2")
        );
        assertEq(principalTokenBeacon.implementation(), address(mockPrincipalTokenV2Instance));
        underlying.mint(MOCK_ADDR_1, 10e18);
        underlying.mint(MOCK_ADDR_2, 1e16);
        vm.prank(MOCK_ADDR_1);
        underlying.approve(_principalTokenAddress2, 10e18);
        vm.prank(MOCK_ADDR_2);
        underlying.approve(_principalTokenAddress2, 1e16);
        data.userPTBalanceBefore1 = pt2.balanceOf(MOCK_ADDR_1);
        data.userPTBalanceBefore2 = pt2.balanceOf(MOCK_ADDR_2);
        data.userYTBalanceBefore1 = yt2.balanceOf(MOCK_ADDR_1);
        data.userYTBalanceBefore2 = yt2.balanceOf(MOCK_ADDR_2);
        data.userUnderlyingBalanceBefore1 = underlying.balanceOf(MOCK_ADDR_1);
        data.userUnderlyingBalanceBefore2 = underlying.balanceOf(MOCK_ADDR_2);
        data.userYieldBefore1 = pt2.updateYield(MOCK_ADDR_1);
        data.userYieldBefore2 = pt2.updateYield(MOCK_ADDR_2);

        // both user deposit (very different amount)
        vm.prank(MOCK_ADDR_1);
        pt2.deposit(10e18, MOCK_ADDR_1);
        vm.prank(MOCK_ADDR_2);
        pt2.deposit(1e16, MOCK_ADDR_2);

        // checks (no yield has been generated)
        data.userPTBalanceAfter1 = pt2.balanceOf(MOCK_ADDR_1);
        data.userPTBalanceAfter2 = pt2.balanceOf(MOCK_ADDR_2);
        data.userYTBalanceAfter1 = yt2.balanceOf(MOCK_ADDR_1);
        data.userYTBalanceAfter2 = yt2.balanceOf(MOCK_ADDR_2);
        data.userUnderlyingBalanceAfter1 = underlying.balanceOf(MOCK_ADDR_1);
        data.userUnderlyingBalanceAfter2 = underlying.balanceOf(MOCK_ADDR_2);
        data.userYieldAfter1 = pt2.updateYield(MOCK_ADDR_1);
        data.userYieldAfter2 = pt2.updateYield(MOCK_ADDR_2);

        assertEq(
            data.userPTBalanceAfter1,
            data.userPTBalanceBefore1 + 10e18,
            "PT balance of user 1 is wrong"
        );
        assertEq(
            data.userPTBalanceAfter2,
            data.userPTBalanceBefore2 + 1e16,
            "PT balance of user 2 is wrong"
        );
        assertEq(
            data.userYTBalanceAfter1,
            data.userYTBalanceBefore1 + 10e18,
            "YieldToken balance of user 1 is wrong"
        );
        assertEq(
            data.userYTBalanceAfter2,
            data.userYTBalanceBefore2 + 1e16,
            "YieldToken balance of user 2 is wrong"
        );
        assertEq(
            data.userUnderlyingBalanceAfter1 + 10e18,
            data.userUnderlyingBalanceBefore1,
            "Underlying balance of user 1 is wrong"
        );
        assertEq(
            data.userUnderlyingBalanceAfter2 + 1e16,
            data.userUnderlyingBalanceBefore2,
            "Underlying balance of user 2 is wrong"
        );
        assertEq(data.userYieldBefore1, 0, "Yield balance before of user 1 is wrong");
        assertEq(data.userYieldBefore2, 0, "Yield balance before of user 2 is wrong");
        assertEq(data.userYieldAfter1, 1000000e18, "Yield balance after of user 1 is wrong");
        assertEq(data.userYieldAfter2, 1000000e18, "Yield balance after of user 2 is wrong");
    }

    function testUpgradeRaoE2E() public {
        IFactorySNG.CurvePoolParams memory curvePoolParams = IFactorySNG.CurvePoolParams({
            A: 1500,
            fee: 1000000,
            fee_mul: 20000000000,
            ma_exp_time: 600,
            initial_price: 10 ** 18,
            rate_adjustment_oracle: address(0)
        });

        vm.prank(scriptAdmin);
        (, , address curvePoolAddress) = factorySNG.deployAll(
            address(ibt),
            1_000_000,
            curvePoolParams,
            0,
            0
        );

        MockRateAdjustmentOracle2 raoOracleInstance = new MockRateAdjustmentOracle2();

        UpgradeBeaconLogicScript upgradeBeaconLogicScript = new UpgradeBeaconLogicScript();
        upgradeBeaconLogicScript.upgradeForTest(address(raoBeacon), address(raoOracleInstance));

        assertEq(raoBeacon.implementation(), address(raoOracleInstance));

        uint256[] memory stored_rates = IStableSwapNG(curvePoolAddress).stored_rates();

        // 2 * 10 ** 18 is the constant value returned by the value function of MockRateAdjustmentOracle2
        assertEq(stored_rates[1], 2 * 10 ** 18);
    }

    function testUpgradeForExistingPT() public {
        PrincipalTokenScript principalTokenScript = new PrincipalTokenScript();
        address principalTokenAddress = principalTokenScript.deployForTest(
            address(factory),
            address(ibt),
            DURATION
        );
        assertEq(IPrincipalToken(principalTokenAddress).maxDeposit(address(0)), type(uint256).max);
        vm.expectRevert();
        MockPrincipalTokenV2(principalTokenAddress).getTestUpgradeability();
        vm.expectRevert();
        MockPrincipalTokenV2(principalTokenAddress).setTestUpgradeability(address(this));

        MockPrincipalTokenV2 mockPrincipalTokenV2Instance = new MockPrincipalTokenV2(
            address(registry)
        );
        // upgrade beacon
        UpgradeBeaconLogicScript upgradeBeaconLogicScript = new UpgradeBeaconLogicScript();
        upgradeBeaconLogicScript.upgradeForTest(
            address(principalTokenBeacon),
            address(mockPrincipalTokenV2Instance)
        );
        assertEq(
            IPrincipalToken(principalTokenAddress).maxDeposit(address(0)),
            type(uint256).max - 1
        );
        assertEq(MockPrincipalTokenV2(principalTokenAddress).getTestUpgradeability(), address(0));
        MockPrincipalTokenV2(principalTokenAddress).setTestUpgradeability(address(this));
        assertEq(
            MockPrincipalTokenV2(principalTokenAddress).getTestUpgradeability(),
            address(this)
        );
        assertEq(principalTokenBeacon.implementation(), address(mockPrincipalTokenV2Instance));
    }

    function testUpgradeForExistingYT() public {
        PrincipalTokenScript principalTokenScript = new PrincipalTokenScript();
        address principalTokenAddress = principalTokenScript.deployForTest(
            address(factory),
            address(ibt),
            DURATION
        );
        address ytAddress = IPrincipalToken(principalTokenAddress).getYT();

        // checks pre-upgrade
        vm.expectRevert();
        MockYieldTokenV2(ytAddress).getPT2();
        vm.expectRevert();
        MockYieldTokenV2(ytAddress).getTestUpgradeability();
        vm.expectRevert();
        MockYieldTokenV2(ytAddress).setTestUpgradeability(0);
        assertEq(MockYieldTokenV2(ytAddress).getPT(), principalTokenAddress);

        MockYieldTokenV2 mockYieldTokenV2Instance = new MockYieldTokenV2();
        // upgrade beacon
        UpgradeBeaconLogicScript upgradeBeaconLogicScript = new UpgradeBeaconLogicScript();
        upgradeBeaconLogicScript.upgradeForTest(
            address(ytBeacon),
            address(mockYieldTokenV2Instance)
        );

        // checks post-upgrade

        assertEq(MockYieldTokenV2(ytAddress).getPT2(), address(0));
        assertEq(MockYieldTokenV2(ytAddress).getTestUpgradeability(), 0);
        MockYieldTokenV2(ytAddress).setTestUpgradeability(12);
        assertEq(MockYieldTokenV2(ytAddress).getTestUpgradeability(), 12);
        assertEq(MockYieldTokenV2(ytAddress).getPT(), principalTokenAddress);
        assertEq(ytBeacon.implementation(), address(mockYieldTokenV2Instance));
    }

    function testTransferPTProxyOwnership() public {
        PrincipalTokenScript principalTokenScript = new PrincipalTokenScript();
        address principalTokenAddress = principalTokenScript.deployForTest(
            address(factory),
            address(ibt),
            DURATION
        );

        MockPrincipalTokenV2 mockPrincipalTokenV2Instance = new MockPrincipalTokenV2(
            address(registry)
        );

        // transfer beacon ownership from scriptAdmin to MOCK_ADDR_1
        vm.startPrank(scriptAdmin);
        accessManager.grantRole(Roles.UPGRADE_ROLE, MOCK_ADDR_1, 0);
        accessManager.revokeRole(Roles.UPGRADE_ROLE, scriptAdmin);
        bytes memory revertData = abi.encodeWithSelector(
            bytes4(keccak256("AccessManagedUnauthorized(address)")),
            scriptAdmin
        );
        vm.expectRevert(revertData);
        // verify scriptAdmin cannot upgrade beacon anymore
        UpgradeableBeacon(principalTokenBeacon).upgradeTo(address(mockPrincipalTokenV2Instance));
        vm.stopPrank();
        // transfer beacon ownership from MOCK_ADDR_1 to MOCK_ADDR_2
        vm.startPrank(scriptAdmin);
        accessManager.grantRole(Roles.UPGRADE_ROLE, MOCK_ADDR_2, 0);
        accessManager.revokeRole(Roles.UPGRADE_ROLE, MOCK_ADDR_1);
        vm.stopPrank();
        vm.startPrank(MOCK_ADDR_1);
        revertData = abi.encodeWithSelector(
            bytes4(keccak256("AccessManagedUnauthorized(address)")),
            MOCK_ADDR_1
        );
        vm.expectRevert(revertData);
        // verify MOCK_ADDR_1 cannot upgrade beacon anymore
        UpgradeableBeacon(principalTokenBeacon).upgradeTo(address(mockPrincipalTokenV2Instance));
        vm.stopPrank();

        vm.prank(MOCK_ADDR_2);
        // verify MOCK_ADDR_2 can upgrade beacon
        UpgradeableBeacon(principalTokenBeacon).upgradeTo(address(mockPrincipalTokenV2Instance));
        assertEq(
            IPrincipalToken(principalTokenAddress).maxDeposit(address(0)),
            type(uint256).max - 1
        );
    }

    function testUpgradePTForInvalidImplementation() public {
        PrincipalTokenScript principalTokenScript = new PrincipalTokenScript();
        address principalTokenAddress = principalTokenScript.deployForTest(
            address(factory),
            address(ibt),
            DURATION
        );
        assertEq(IPrincipalToken(principalTokenAddress).maxDeposit(address(0)), type(uint256).max);

        // An address that has no deployed code
        address invalidImplementationAddress = address(0x1);

        bytes memory revertData = abi.encodeWithSelector(
            bytes4(keccak256("BeaconInvalidImplementation(address)")),
            invalidImplementationAddress
        );

        // upgrade beacon
        UpgradeBeaconLogicScript upgradeBeaconLogicScript = new UpgradeBeaconLogicScript();
        vm.expectRevert(revertData);
        upgradeBeaconLogicScript.upgradeForTest(
            address(principalTokenBeacon),
            address(invalidImplementationAddress)
        );
    }
}
