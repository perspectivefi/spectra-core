// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "openzeppelin-contracts/proxy/beacon/UpgradeableBeacon.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockIBT.sol";
import "../src/mocks/MockCurveAddressProvider.sol";
import "../script/00_deployAccessManager.s.sol";
import "../script/01_deployRegistry.s.sol";
import "../script/02_deployPrincipalTokenInstance.s.sol";
import "../script/03_deployYTInstance.s.sol";
import "../script/04_deployPrincipalTokenBeacon.s.sol";
import "../script/05_deployYTBeacon.s.sol";
import "../script/06_deployFactory.s.sol";
import "../script/07_deployPrincipalToken.s.sol";
import "../script/08_deployCurvePool.s.sol";
import "../script/10_deployAll.s.sol";
import "../src/interfaces/ICurvePool.sol";
import "../src/libraries/Roles.sol";

error CouldNotFetchLPToken();
error FailedToAddInitialLiquidity();

contract ContractFactoryForkTest is Test {
    address public accessManager;
    address public registry;
    address public factory;
    address public router;
    address public routerUtil;
    address public curvePool;
    address public underlying;
    address public ibt;
    address public principalToken;
    address public yt;
    address public lpToken;
    address public curveAddressProvider;
    address public principalTokenInstance;
    address public ytInstance;
    address feeCollector = 0x0000000000000000000000000000000000000FEE;
    address MOCK_ADDR_1 = 0x0000000000000000000000000000000000000001;
    address MOCK_ADDR_2 = 0x0000000000000000000000000000000000000002;
    address MOCK_ADDR_3 = 0x0000000000000000000000000000000000000003;
    address MOCK_ADDR_4 = 0x0000000000000000000000000000000000000004;
    address MOCK_ADDR_5 = 0x0000000000000000000000000000000000000005;
    uint256 fork;

    string public GOERLI_RPC_URL = vm.envString("GOERLI_RPC_URL");
    uint256 public TOKENIZATION_FEE = 1e15;
    uint256 public YIELD_FEE = 0;
    uint256 public PT_FLASH_LOAN_FEE = 0;
    uint256 public EXPIRY = block.timestamp + 100000;
    uint256 public IBT_UNIT;

    address public testUser;
    address public scriptAdmin;

    struct CurvePoolDeploymentData {
        address[2] coins;
        uint256 A;
        uint256 gamma;
        uint256 mid_fee;
        uint256 out_fee;
        uint256 allowed_extra_profit;
        uint256 fee_gamma;
        uint256 adjustment_step;
        uint256 admin_fee;
        uint256 ma_half_time;
        uint256 initial_price;
    }

    /* Events */
    event OwnerChanged(address oldOwner, address newOwner);
    event PTDeployed(address indexed principalToken, address indexed poolCreator);
    event CurvePoolDeployed(address indexed poolAddress, address indexed ibt, address indexed pt);

    /**
     * @dev This function is called before each test.
     */
    function setUp() public {
        fork = vm.createFork(GOERLI_RPC_URL);
        vm.selectFork(fork);
        curveAddressProvider = address(0x44Ba140128cae03A13A7cD5F3Da32b5Cd73c1c7a);
        // default account for deploying scripts contracts. refer to line 35 of
        // https://github.com/foundry-rs/foundry/blob/master/evm/src/lib.rs for more details
        scriptAdmin = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;
        testUser = address(this); // to reduce number of lines and repeated vm pranks
        AccessManagerDeploymentScript accessManagerScript = new AccessManagerDeploymentScript();
        accessManager = accessManagerScript.deployForTest(scriptAdmin);
        RegistryScript registryScript = new RegistryScript();
        registry = registryScript.deployForTest(
            TOKENIZATION_FEE,
            YIELD_FEE,
            PT_FLASH_LOAN_FEE,
            feeCollector,
            address(accessManager)
        );

        vm.prank(scriptAdmin);
        IAccessManager(accessManager).grantRole(Roles.REGISTRY_ROLE, scriptAdmin, 0);
        vm.prank(scriptAdmin);
        IAccessManager(accessManager).grantRole(Roles.FEE_SETTER_ROLE, scriptAdmin, 0);

        underlying = address(new MockERC20());
        MockERC20(underlying).initialize("MOCK UNDERLYING", "MUDL"); // deploys underlying mints 100000e18 token to caller
        ibt = address(new MockIBT());
        MockIBT(ibt).initialize("MOCK IBT", "MIBT", IERC20Metadata(underlying)); // deploys ibt which principalToken holds
        MockERC20(underlying).mint(address(this), 1);
        IERC20(underlying).approve(ibt, 1);
        IERC4626(ibt).deposit(1, address(this));
        IBT_UNIT = 10 ** MockIBT(ibt).decimals();
        PrincipalTokenInstanceScript principalTokenInstanceScript = new PrincipalTokenInstanceScript();
        YTInstanceScript ytInstanceScript = new YTInstanceScript();
        principalTokenInstance = principalTokenInstanceScript.deployForTest(registry);
        ytInstance = ytInstanceScript.deployForTest();
        PrincipalTokenBeaconScript principalTokenBeaconScript = new PrincipalTokenBeaconScript();
        YTBeaconScript ytBeaconScript = new YTBeaconScript();
        principalTokenBeaconScript.deployForTest(principalTokenInstance, registry, accessManager);
        ytBeaconScript.deployForTest(ytInstance, registry, accessManager);
        FactoryScript factoryScript = new FactoryScript();
        factory = factoryScript.deployForTest(registry, accessManager);
        vm.prank(scriptAdmin);
        IAccessManager(accessManager).grantRole(Roles.ADMIN_ROLE, factory, 0);
        vm.prank(scriptAdmin);
        IAccessManager(accessManager).grantRole(Roles.REGISTRY_ROLE, factory, 0);
    }

    function testDeployPrincipalTokenWithFork() public {
        PrincipalTokenScript principalTokenScript = new PrincipalTokenScript();
        vm.expectEmit(false, true, false, true);
        emit PTDeployed(principalTokenInstance, scriptAdmin);
        // deploys principalToken
        principalToken = principalTokenScript.deployForTest(factory, ibt, EXPIRY);
        vm.prank(testUser);
        yt = IPrincipalToken(principalToken).getYT();
        assertTrue(
            PrincipalToken(principalToken).maturity() == EXPIRY + block.timestamp,
            "Factory: PT attributes do not match after deploying"
        );
    }

    function testDeployCurvePoolAndAddLiquidityWithFork() public {
        PrincipalTokenScript principalTokenScript = new PrincipalTokenScript();
        vm.expectEmit(false, true, false, true);
        emit PTDeployed(principalTokenInstance, scriptAdmin);
        // deploys principalToken
        principalToken = principalTokenScript.deployForTest(factory, ibt, EXPIRY);
        yt = IPrincipalToken(principalToken).getYT();
        assertTrue(
            IPrincipalToken(principalToken).maturity() == EXPIRY + block.timestamp,
            "Factory: PT attributes do not match after deploying"
        );
        CurvePoolScript curvePoolScript = new CurvePoolScript();

        IFactory.CurvePoolParams memory curvePoolDeploymentData;
        curvePoolDeploymentData.A = 200000000;
        curvePoolDeploymentData.gamma = 100000000000000;
        curvePoolDeploymentData.mid_fee = 5000000;
        curvePoolDeploymentData.out_fee = 45000000;
        curvePoolDeploymentData.allowed_extra_profit = 10000000000;
        curvePoolDeploymentData.fee_gamma = 5000000000000000;
        curvePoolDeploymentData.adjustment_step = 5500000000000;
        curvePoolDeploymentData.admin_fee = 5000000000;
        curvePoolDeploymentData.ma_half_time = 600;
        curvePoolDeploymentData.initial_price = 1e18;

        vm.expectEmit(false, true, true, true);
        emit CurvePoolDeployed(address(0), address(ibt), principalToken);

        // deploys curvePool
        curvePool = curvePoolScript.deployForTest(
            factory,
            ibt,
            principalToken,
            curveAddressProvider,
            curvePoolDeploymentData,
            0
        );

        (bool successLPToken, bytes memory response) = curvePool.call(
            abi.encodeWithSelector(0xfc0c546a)
        );
        if (!successLPToken) {
            revert CouldNotFetchLPToken();
        }
        lpToken = address(abi.decode(response, (address)));

        MockERC20(underlying).mint(address(this), 100000e18);
        MockERC20(underlying).approve(ibt, 1000e18);
        MockERC20(underlying).approve(principalToken, 1000e18);
        uint256 amountIbt = MockIBT(ibt).deposit(1000e18, address(this));
        uint256 amountPt = IPrincipalToken(principalToken).deposit(1000e18, address(this));
        MockIBT(ibt).approve(curvePool, amountIbt);
        IPrincipalToken(principalToken).approve(curvePool, amountPt);
        (bool success, ) = curvePool.call(
            abi.encodeWithSelector(0x0b4c7e4d, [amountIbt, amountPt], 0)
        );
        if (!success) {
            revert FailedToAddInitialLiquidity();
        }
        assertTrue(
            ICurvePool(curvePool).coins(0) == ibt,
            "Factory: Curve Pool attributes do not match after deploying 1"
        );
        assertTrue(
            ICurvePool(curvePool).coins(1) == principalToken,
            "Factory: Curve Pool attributes do not match after deploying 2"
        );
        assertTrue(
            ICurvePool(curvePool).balances(0) == amountIbt,
            "Factory: Curve Pool attributes do not match after deploying 3"
        );
        assertTrue(
            ICurvePool(curvePool).balances(1) == amountPt,
            "Factory: Curve Pool attributes do not match after deploying 4"
        );
        assertTrue(
            ICurvePool(curvePool).A() == curvePoolDeploymentData.A,
            "Factory: Curve Pool attributes do not match after deploying 5"
        );
        assertTrue(
            ICurvePool(curvePool).gamma() == curvePoolDeploymentData.gamma,
            "Factory: Curve Pool attributes do not match after deploying 6"
        );
        assertTrue(
            ICurvePool(curvePool).token() == lpToken,
            "Factory: Curve Pool attributes do not match after deploying 8"
        );
    }

    function testDeployAllWithFork() public {
        DeployAllScript deployAllScript = new DeployAllScript();

        DeployAllScript.TestInputData memory inputData;
        inputData._ibt = ibt;
        inputData._duration = EXPIRY;
        inputData._curveAddressProvider = curveAddressProvider;
        inputData._deployer = scriptAdmin;
        inputData._tokenizationFee = TOKENIZATION_FEE;
        inputData._yieldFee = YIELD_FEE;
        inputData._ptFlashLoanFee = PT_FLASH_LOAN_FEE;
        inputData._feeCollector = feeCollector;
        inputData._initialLiquidityInIBT = 0;

        DeployAllScript.ReturnData memory returnData;
        returnData = deployAllScript.deployForTest(inputData);

        registry = returnData._registry;
        factory = returnData._factory;
        principalToken = returnData._pt;
        curvePool = returnData._curvePool;
        router = returnData._router;
        routerUtil = returnData._routerUtil;

        // test tokenize + add liquidity
        MockERC20(underlying).mint(address(this), 2000e18);

        MockERC20(underlying).approve(principalToken, 1000e18);
        uint256 amountPt = IPrincipalToken(principalToken).deposit(1000e18, address(this));

        MockERC20(underlying).approve(ibt, 1000e18);
        uint256 amountIbt = MockIBT(ibt).deposit(1000e18, address(this));

        MockIBT(ibt).approve(curvePool, amountIbt);
        IPrincipalToken(principalToken).approve(curvePool, amountPt);
        (bool success, ) = curvePool.call(
            abi.encodeWithSelector(0x0b4c7e4d, [amountIbt, amountPt], 0)
        );
        if (!success) {
            revert FailedToAddInitialLiquidity();
        }
    }
}
