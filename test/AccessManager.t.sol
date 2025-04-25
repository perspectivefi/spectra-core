// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockIBT.sol";
import "../src/mocks/MockPrincipalTokenV2.sol";
import "../script/00_deployAccessManager.s.sol";
import "../script/01_deployRegistry.s.sol";
import "../script/02_deployPrincipalTokenInstance.s.sol";
import "../script/03_deployYTInstance.s.sol";
import "../script/04_deployPrincipalTokenBeacon.s.sol";
import "../script/05_deployYTBeacon.s.sol";
import "../script/06_deployFactory.s.sol";
import "../script/07_deployPrincipalToken.s.sol";
import "../script/08_deployCurvePool.s.sol";
import "script/09_deployRouter.s.sol";
import "../script/14_upgradeBeaconImplementation.s.sol";
import "../src/libraries/Roles.sol";

import "src/mocks/MockRewardsProxy.sol";

contract AccessManagerSystem is Test {
    /* VARIABLES */
    MockIncentivesContract public incentivesContract;
    MockERC20 public rewardToken;
    MockRewardsProxy public rewardsProxy;
    Factory public factory;
    AccessManager public accessManager;
    MockERC20 public underlying;
    PrincipalToken public principalToken;
    Registry public registry;
    Router public router;
    RouterUtil public routerUtil;
    MockIBT public ibt;
    uint256 public TOKENIZATION_FEE = 1e15;
    uint256 public YIELD_FEE = 0;
    uint256 public PT_FLASH_LOAN_FEE = 0;
    uint256 public DURATION = 100000;
    uint256 public IBT_UNIT;
    address public admin;
    address public scriptAdmin;
    address public accessManagersuperAdmin = 0x00000000000000000000000000000000000000a0;
    address public accessManagersuperAdmin2 = 0x00000000000000000000000000000000000000A1;
    address MOCK_ADDR_1 = 0x0000000000000000000000000000000000000001;
    address MOCK_ADDR_2 = 0x0000000000000000000000000000000000000002;
    address feeCollector = 0x0000000000000000000000000000000000000FEE;
    address public kyberRouterAddr = 0x0000000000000000000000000000000000037BE8;
    address public curvePoolAddr;
    address public curveFactoryAddress;
    address public principalTokenAddr;
    YieldToken public yt;
    uint256 fork;
    UpgradeableBeacon public principalTokenBeacon;
    UpgradeableBeacon public ytBeacon;
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
    // Events
    event PTDeployed(address indexed principalToken, address indexed poolCreator);
    event CurvePoolDeployed(address indexed poolAddress, address indexed ibt, address indexed pt);

    // Errors
    error FailedToAddInitialLiquidity();

    /**
     * @dev This function is called before each test.
     */
    function setUp() public {
        fork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(fork);
        curveFactoryAddress = 0x98EE851a00abeE0d95D08cF4CA2BdCE32aeaAF7F;
        admin = address(this);
        // default account for deploying scripts contracts. refer to line 35 of
        // https://github.com/foundry-rs/foundry/blob/master/evm/src/lib.rs for more details
        scriptAdmin = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;
        // Setup Access Manager
        AccessManagerDeploymentScript accessManagerScript = new AccessManagerDeploymentScript();
        accessManager = AccessManager(accessManagerScript.deployForTest(accessManagersuperAdmin));
        vm.prank(accessManagersuperAdmin);
        accessManager.grantRole(Roles.ADMIN_ROLE, scriptAdmin, 0);
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
        vm.prank(scriptAdmin);
        accessManager.grantRole(Roles.REGISTRY_ROLE, scriptAdmin, 0);
        vm.prank(scriptAdmin);
        accessManager.grantRole(Roles.FEE_SETTER_ROLE, scriptAdmin, 0);
        underlying = new MockERC20();
        underlying.initialize("MOCK UNDERLYING", "MUDL"); // deploys underlying mints 100000e18 token to caller
        ibt = new MockIBT();
        ibt.initialize("MOCK IBT", "MIBT", IERC20Metadata(address(underlying))); // deploys ibt which principalToken holds
        IBT_UNIT = 10 ** ibt.decimals();
        underlying.mint(address(this), 1);
        underlying.approve(address(ibt), 1);
        ibt.deposit(1, address(this));
        PrincipalTokenInstanceScript principalTokenInstanceScript = new PrincipalTokenInstanceScript();
        YTInstanceScript ytInstanceScript = new YTInstanceScript();
        PrincipalToken principalTokenInstance = PrincipalToken(
            principalTokenInstanceScript.deployForTest(address(registry))
        );
        YieldToken ytInstance = YieldToken(ytInstanceScript.deployForTest());

        // PT and YT Beacons
        PrincipalTokenBeaconScript principalTokenBeaconScript = new PrincipalTokenBeaconScript();
        YTBeaconScript ytBeaconScript = new YTBeaconScript();
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
        PrincipalTokenScript principalTokenScript = new PrincipalTokenScript();
        vm.expectEmit(false, true, false, true);
        emit PTDeployed(address(principalTokenInstance), scriptAdmin);
        // deploys principalToken
        address principalTokenAddress = principalTokenScript.deployForTest(
            address(factory),
            address(ibt),
            DURATION
        );
        principalTokenAddr = principalTokenAddress;
        principalToken = PrincipalToken(principalTokenAddress);
        yt = YieldToken(principalToken.getYT());

        CurvePoolScript curvePoolScript = new CurvePoolScript();

        IFactory.CurvePoolParams memory curvePoolDeploymentData;
        curvePoolDeploymentData.A = 20000000;
        curvePoolDeploymentData.gamma = 100000000000000;
        curvePoolDeploymentData.mid_fee = 5000000;
        curvePoolDeploymentData.out_fee = 45000000;
        curvePoolDeploymentData.fee_gamma = 5000000000000000;
        curvePoolDeploymentData.allowed_extra_profit = 10000000000;
        curvePoolDeploymentData.adjustment_step = 5500000000000;
        curvePoolDeploymentData.ma_exp_time = 1200;
        curvePoolDeploymentData.initial_price = 1e18;

        vm.expectEmit(false, true, true, true);
        emit CurvePoolDeployed(address(0), address(ibt), principalTokenAddress);

        // deploys curvePool
        curvePoolAddr = curvePoolScript.deployForTest(
            address(factory),
            address(ibt),
            principalTokenAddress,
            curvePoolDeploymentData,
            0,
            0
        );

        underlying.mint(address(this), 1000000000e18);
        underlying.approve(address(ibt), 1000000000e18);
        underlying.approve(principalTokenAddress, 1000000000e18);
        ibt.deposit(100000000e18, address(this));
        uint256 amountIbt = ibt.deposit(100000e18, address(this));
        uint256 amountPt = principalToken.deposit(100000e18, address(this));
        principalToken.deposit(10000000e18, address(this));
        ibt.approve(curvePoolAddr, amountIbt);
        principalToken.approve(curvePoolAddr, amountPt);
        (bool success, ) = curvePoolAddr.call(
            abi.encodeWithSelector(0x0b4c7e4d, [amountIbt, amountPt], 0)
        );
        if (!success) {
            revert FailedToAddInitialLiquidity();
        }

        incentivesContract = new MockIncentivesContract(address(ibt));
        rewardToken = MockERC20(incentivesContract.rewardToken());

        // deploy router
        RouterScript routerScript = new RouterScript();
        (address payable routerAddr, address routerUtilAddr, ) = routerScript.deployForTest(
            address(registry),
            kyberRouterAddr,
            address(accessManager)
        );
        router = Router(routerAddr);
        routerUtil = RouterUtil(routerUtilAddr);
    }

    function testAccessManagerAccess() public {
        assertEq(address(accessManager), principalToken.authority());
        bytes memory revertData = abi.encodeWithSelector(
            bytes4(keccak256("AccessManagerUnauthorizedAccount(address,uint64)")),
            accessManagersuperAdmin2,
            0
        );
        // Only a super admin can grant roles. So accessManagersuperAdmin2 cannot grant super admin role to MOCK_ADDR_1
        vm.expectRevert(revertData);
        vm.prank(accessManagersuperAdmin2);
        accessManager.grantRole(Roles.ADMIN_ROLE, MOCK_ADDR_1, 0);

        // Now accessManagersuperAdmin can grant super admin role to MOCK_ADDR_1
        vm.prank(accessManagersuperAdmin);
        accessManager.grantRole(Roles.ADMIN_ROLE, MOCK_ADDR_1, 0);
    }

    function testChangeAccessManagerInstance() public {
        AccessManagerDeploymentScript accessManagerScript = new AccessManagerDeploymentScript();
        PrincipalTokenScript principalTokenScript = new PrincipalTokenScript();
        address pt1 = principalTokenScript.deployForTest(address(factory), address(ibt), DURATION);
        address pt2 = principalTokenScript.deployForTest(address(factory), address(ibt), DURATION);
        bytes memory revertData = abi.encodeWithSelector(
            bytes4(keccak256("AccessManagedUnauthorized(address)")),
            MOCK_ADDR_2
        );
        vm.startPrank(MOCK_ADDR_2);
        vm.expectRevert(revertData);
        IPrincipalToken(pt1).pause();
        vm.expectRevert(revertData);
        IPrincipalToken(pt2).pause();
        vm.stopPrank();

        // A new access manager instance is created with super admin accessManagersuperAdmin2
        AccessManager accessManager2 = AccessManager(
            accessManagerScript.deployForTest(accessManagersuperAdmin2)
        );
        // accessManagersuperAdmin2 grants PAUSER_ROLE to MOCK_ADDR_2
        vm.prank(accessManagersuperAdmin2);
        accessManager2.grantRole(Roles.PAUSER_ROLE, MOCK_ADDR_2, 0);
        // We are changing the access manager authority instance to a new one for the pt1
        vm.prank(scriptAdmin);
        accessManager.updateAuthority(pt1, address(accessManager2));

        // accessManagersuperAdmin2 set the factory to be SUPER ADMIN in accessManager2
        vm.prank(accessManagersuperAdmin2);
        accessManager2.grantRole(Roles.ADMIN_ROLE, address(factory), 0);
        vm.prank(accessManagersuperAdmin2);
        accessManager2.grantRole(Roles.REGISTRY_ROLE, address(factory), 0);

        // We are changing the access manager authority instance to a new one for the factory
        // Now all the pts deployed by the factory will be using accessManager2
        vm.prank(accessManagersuperAdmin);
        accessManager.updateAuthority(address(factory), address(accessManager2));

        address pt3 = principalTokenScript.deployForTest(address(factory), address(ibt), DURATION);
        vm.startPrank(MOCK_ADDR_2);
        vm.expectRevert(revertData);
        IPrincipalToken(pt1).pause(); // pt3 is using accessManager
        IPrincipalToken(pt3).pause(); // pt3 is using accessManager2
        vm.stopPrank();
    }

    function testPTPauserAccess() public {
        PrincipalTokenScript principalTokenScript = new PrincipalTokenScript();
        address pt1 = principalTokenScript.deployForTest(address(factory), address(ibt), DURATION);
        address pt2 = principalTokenScript.deployForTest(address(factory), address(ibt), DURATION);
        address pt3 = principalTokenScript.deployForTest(address(factory), address(ibt), DURATION);
        bytes memory revertData = abi.encodeWithSelector(
            bytes4(keccak256("AccessManagedUnauthorized(address)")),
            MOCK_ADDR_2
        );
        vm.prank(accessManagersuperAdmin);
        accessManager.grantRole(Roles.PAUSER_ROLE, MOCK_ADDR_1, 0);

        vm.startPrank(MOCK_ADDR_2);
        vm.expectRevert(revertData);
        IPrincipalToken(pt1).pause();
        vm.expectRevert(revertData);
        IPrincipalToken(pt2).pause();
        vm.expectRevert(revertData);
        IPrincipalToken(pt3).pause();
        vm.stopPrank();

        vm.startPrank(MOCK_ADDR_1);
        IPrincipalToken(pt1).pause();
        IPrincipalToken(pt2).pause();
        IPrincipalToken(pt3).pause();
        vm.stopPrank();

        // In the meantime MOCK_ADDR_1 user has been revoked access
        // to pause/unpause, and MOCK_ADDR_2 has been granted access
        vm.startPrank(accessManagersuperAdmin);
        accessManager.revokeRole(Roles.PAUSER_ROLE, MOCK_ADDR_1);
        accessManager.grantRole(Roles.PAUSER_ROLE, MOCK_ADDR_2, 0);
        vm.stopPrank();

        vm.startPrank(MOCK_ADDR_1);
        revertData = abi.encodeWithSelector(
            bytes4(keccak256("AccessManagedUnauthorized(address)")),
            MOCK_ADDR_1
        );
        vm.expectRevert(revertData);
        IPrincipalToken(pt1).unPause();
        vm.expectRevert(revertData);
        IPrincipalToken(pt2).unPause();
        vm.expectRevert(revertData);
        IPrincipalToken(pt3).unPause();
        vm.stopPrank();

        vm.startPrank(MOCK_ADDR_2);
        IPrincipalToken(pt1).unPause();
        IPrincipalToken(pt2).unPause();
        IPrincipalToken(pt3).unPause();
        vm.stopPrank();
    }

    function testPTRewardsProxyAccess() public {
        PrincipalTokenScript principalTokenScript = new PrincipalTokenScript();
        address pt = principalTokenScript.deployForTest(address(factory), address(ibt), DURATION);
        underlying.approve(address(principalToken), 500e18);
        principalToken.deposit(500e18, address(1));
        rewardsProxy = new MockRewardsProxy();

        bytes memory revertData = abi.encodeWithSelector(
            bytes4(keccak256("AccessManagedUnauthorized(address)")),
            MOCK_ADDR_2
        );
        vm.prank(accessManagersuperAdmin);
        accessManager.grantRole(Roles.REWARDS_HARVESTER_ROLE, MOCK_ADDR_1, 0);
        vm.prank(accessManagersuperAdmin);
        accessManager.grantRole(Roles.REWARDS_PROXY_SETTER_ROLE, MOCK_ADDR_1, 0);

        vm.prank(MOCK_ADDR_2);
        vm.expectRevert(revertData);
        IPrincipalToken(pt).setRewardsProxy(address(rewardsProxy));

        vm.prank(MOCK_ADDR_1);
        IPrincipalToken(pt).setRewardsProxy(address(rewardsProxy));

        // We can use it and claim rewards
        incentivesContract.testAddClaimable(100e18);
        uint256 claimableByPT = incentivesContract.claimableByUser(address(pt));
        bytes memory claimData = abi.encode(
            address(incentivesContract),
            claimableByPT,
            feeCollector,
            address(rewardToken)
        );

        vm.prank(MOCK_ADDR_2);
        vm.expectRevert(revertData);
        IPrincipalToken(pt).claimRewards(claimData);

        vm.prank(MOCK_ADDR_1);
        IPrincipalToken(pt).claimRewards(claimData);

        incentivesContract.testAddClaimable(100e18);
        claimableByPT = incentivesContract.claimableByUser(address(pt));
        claimData = abi.encode(
            address(incentivesContract),
            claimableByPT,
            feeCollector,
            address(rewardToken)
        );

        revertData = abi.encodeWithSelector(
            bytes4(keccak256("AccessManagedUnauthorized(address)")),
            MOCK_ADDR_1
        );

        vm.startPrank(accessManagersuperAdmin);
        accessManager.revokeRole(Roles.REWARDS_HARVESTER_ROLE, MOCK_ADDR_1);
        accessManager.revokeRole(Roles.REWARDS_PROXY_SETTER_ROLE, MOCK_ADDR_1);
        accessManager.grantRole(Roles.REWARDS_HARVESTER_ROLE, MOCK_ADDR_2, 0);
        accessManager.grantRole(Roles.REWARDS_PROXY_SETTER_ROLE, MOCK_ADDR_2, 0);
        vm.stopPrank();

        vm.prank(MOCK_ADDR_1);
        vm.expectRevert(revertData);
        IPrincipalToken(pt).claimRewards(claimData);

        vm.prank(MOCK_ADDR_2);
        IPrincipalToken(pt).claimRewards(claimData);

        vm.prank(MOCK_ADDR_1);
        vm.expectRevert(revertData);
        IPrincipalToken(pt).setRewardsProxy(address(0));

        vm.prank(MOCK_ADDR_2);
        IPrincipalToken(pt).setRewardsProxy(address(0));
    }

    function testFactoryAccess() public {
        assertEq(address(accessManager), factory.authority());
        bytes memory revertData = abi.encodeWithSelector(
            bytes4(keccak256("AccessManagedUnauthorized(address)")),
            MOCK_ADDR_1
        );
        vm.prank(MOCK_ADDR_1);
        vm.expectRevert(revertData);
        address newCurveFactory = address(0xfac);
        factory.setCurveFactory(newCurveFactory);
        vm.prank(accessManagersuperAdmin);
        accessManager.grantRole(Roles.REGISTRY_ROLE, MOCK_ADDR_1, 0);
        vm.prank(MOCK_ADDR_1);
        factory.setCurveFactory(newCurveFactory);
        assertEq(factory.getCurveFactory(), newCurveFactory);
    }

    function testRouterAccess() public {
        assertEq(address(accessManager), router.authority());
        bytes memory revertData = abi.encodeWithSelector(
            bytes4(keccak256("AccessManagedUnauthorized(address)")),
            MOCK_ADDR_1
        );
        assertEq(router.getRouterUtil(), address(routerUtil));
        assertEq(router.getKyberRouter(), kyberRouterAddr);

        vm.prank(MOCK_ADDR_1);
        vm.expectRevert(revertData);
        router.setRouterUtil(address(8));

        vm.prank(MOCK_ADDR_1);
        vm.expectRevert(revertData);
        router.setKyberRouter(address(9));

        vm.prank(MOCK_ADDR_1);
        vm.expectRevert(revertData);
        router.setKyberRouter(address(10));

        vm.prank(accessManagersuperAdmin);
        accessManager.grantRole(Roles.UPGRADE_ROLE, MOCK_ADDR_1, 0);

        vm.prank(MOCK_ADDR_1);
        router.setRouterUtil(address(8));

        vm.prank(MOCK_ADDR_1);
        router.setKyberRouter(address(9));

        assertEq(router.getRouterUtil(), address(8));
        assertEq(router.getKyberRouter(), address(9));
    }

    function testRegistryAccess() public {
        bytes memory revertData = abi.encodeWithSelector(
            bytes4(keccak256("AccessManagedUnauthorized(address)")),
            MOCK_ADDR_1
        );
        assertEq(address(accessManager), registry.authority());
        vm.startPrank(MOCK_ADDR_1);
        vm.expectRevert(revertData);
        registry.setFactory(address(0xa));
        vm.expectRevert(revertData);
        registry.setRouter(address(0xa));
        vm.expectRevert(revertData);
        registry.setRouterUtil(address(0xa));
        vm.expectRevert(revertData);
        registry.setPTBeacon(address(0xa));
        vm.expectRevert(revertData);
        registry.setYTBeacon(address(0xa));
        vm.expectRevert(revertData);
        registry.addPT(address(0xa));
        vm.expectRevert(revertData);
        registry.removePT(address(0xa));
        vm.stopPrank();

        vm.prank(accessManagersuperAdmin);
        accessManager.grantRole(Roles.REGISTRY_ROLE, MOCK_ADDR_1, 0);

        vm.startPrank(MOCK_ADDR_1);
        registry.setFactory(address(0xa));
        registry.setRouter(address(0xa));
        registry.setRouterUtil(address(0xa));
        registry.setPTBeacon(address(0xa));
        registry.setYTBeacon(address(0xa));
        registry.addPT(address(0xa));
        registry.removePT(address(0xa));

        vm.expectRevert(revertData);
        registry.setFeeCollector(address(0xa));
        vm.expectRevert(revertData);
        registry.setTokenizationFee(0);
        vm.expectRevert(revertData);
        registry.setYieldFee(0);
        vm.expectRevert(revertData);
        registry.setPTFlashLoanFee(0);
        vm.expectRevert(revertData);
        registry.reduceFee(address(0xa), address(0xa), 1);
        vm.stopPrank();

        vm.prank(accessManagersuperAdmin);
        accessManager.grantRole(Roles.FEE_SETTER_ROLE, MOCK_ADDR_1, 0);

        vm.startPrank(MOCK_ADDR_1);
        registry.setFeeCollector(address(0xa));
        registry.setTokenizationFee(0);
        registry.setYieldFee(0);
        registry.setPTFlashLoanFee(0);
        registry.reduceFee(address(0xa), address(0xa), 1);
        vm.stopPrank();
    }

    /** @dev Internal function to increase the current time. */
    function _increaseTime(uint256 timeToAdd) internal {
        uint256 time = block.timestamp + timeToAdd;
        vm.warp(time);
    }
}
