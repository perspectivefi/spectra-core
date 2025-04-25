// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.20;

import "forge-std/Test.sol";

import "script/00_deployAccessManager.s.sol";
import "script/01_deployRegistry.s.sol";
import "script/02_deployPrincipalTokenInstance.s.sol";
import "script/03_deployYTInstance.s.sol";
import "script/04_deployPrincipalTokenBeacon.s.sol";
import "script/05_deployYTBeacon.s.sol";
import "script/06_deployFactory.s.sol";
import "script/07_deployPrincipalToken.s.sol";
import "src/mocks/MockERC20.sol";
import "src/mocks/MockIBT.sol";
import "src/libraries/Roles.sol";
import "openzeppelin-contracts/proxy/beacon/UpgradeableBeacon.sol";
import "src/libraries/RayMath.sol";

contract ContractPrincipalToken2 is Test {
    using Math for uint256;

    struct Rate {
        uint256 oldPTRateUser1;
        uint256 newPTRateUser1;
        uint256 oldIBTRateUser1;
        uint256 newIBTRateUser1;
        uint256 oldPTRateUser2;
        uint256 newPTRateUser2;
        uint256 oldIBTRateUser2;
        uint256 newIBTRateUser2;
        uint256 oldPTRateUser3;
        uint256 newPTRateUser3;
        uint256 oldIBTRateUser3;
        uint256 newIBTRateUser3;
        uint256 oldPTRateUser4;
        uint256 newPTRateUser4;
        uint256 oldIBTRateUser4;
        uint256 newIBTRateUser4;
        uint256 oldRate;
        uint256 newRate;
        uint256 oldIBTRate;
        uint256 newIBTRate;
        uint256 oldPTRate;
        uint256 newPTRate;
    }
    struct YieldData {
        uint256 oldYieldUser1;
        uint256 oldYieldUser2;
        uint256 oldYieldUser3;
        uint256 oldYieldUser4;
        uint256 ibtOfYTUser1;
        uint256 ibtOfYTUser2;
        uint256 ibtOfYTUser3;
        uint256 ibtOfYTUser4;
        uint256 yieldInUnderlyingUser1;
        uint256 yieldInUnderlyingUser2;
        uint256 yieldInUnderlyingUser3;
        uint256 yieldInUnderlyingUser4;
        uint256 expectedYieldInIBTUser1;
        uint256 expectedYieldInIBTUser2;
        uint256 expectedYieldInIBTUser3;
        uint256 expectedYieldInIBTUser4;
        uint256 actualYieldUser1;
        uint256 actualYieldUser2;
        uint256 actualYieldUser3;
        uint256 actualYieldUser4;
        uint256 ytBalanceBeforeUser3;
        uint256 ytBalanceBeforeUser4;
        uint256 ytBalanceAfterUser3;
        uint256 ytBalanceAfterUser4;
        uint256 fee1;
        uint256 fee2;
        uint256 fee3;
        uint256 fee4;
        uint256 yieldClaimed;
        uint256 underlyingBalanceBefore;
        uint256 underlyingLostThroughPTDepegForYTUser1;
        uint256 underlyingLostThroughPTDepegForYTUser2;
        uint256 underlyingLostThroughPTDepegForYTUser3;
        uint256 underlyingLostThroughPTDepegForYTUser4;
    }
    struct UserDataBeforeAfter {
        uint256 userYTBalanceBefore;
        uint256 userYTBalanceAfter;
        uint256 userPTBalanceBefore;
        uint256 userPTBalanceAfter;
        uint256 userUnderlyingBalanceBefore;
        uint256 userUnderlyingBalanceAfter;
        uint256 underlyingRedeemed1;
        uint256 claimedYield1;
        uint256 underlyingRedeemed2;
        uint256 claimedYield2;
        uint256 totalUnderlyingEarned1;
        uint256 totalUnderlyingEarned2;
    }
    struct DepositData {
        uint256 amountToDeposit;
        uint256 expectedIBT;
        uint256 expected;
        uint256 actual;
    }
    PrincipalToken public principalToken;
    Factory public factory;
    AccessManager public accessManager;
    MockERC20 public underlying;
    MockIBT public ibt;
    UpgradeableBeacon public principalTokenBeacon;
    UpgradeableBeacon public ytBeacon;
    YieldToken public yt;
    Registry public registry;
    address public curveFactoryAddress = address(0xfac);
    address feeCollector = 0x0000000000000000000000000000000000000FEE;
    address MOCK_ADDR_1 = 0x0000000000000000000000000000000000000001;
    address MOCK_ADDR_2 = 0x0000000000000000000000000000000000000002;
    address MOCK_ADDR_3 = 0x0000000000000000000000000000000000000003;
    address MOCK_ADDR_4 = 0x0000000000000000000000000000000000000004;
    address MOCK_ADDR_5 = 0x0000000000000000000000000000000000000005;
    uint256 public TOKENIZATION_FEE = 1e15;
    uint256 public YIELD_FEE = 0;
    uint256 public PT_FLASH_LOAN_FEE = 0;
    uint256 public EXPIRY = block.timestamp + 100000;
    uint256 public IBT_UNIT;
    address public admin;
    address public scriptAdmin;
    uint256 totalFeesTill;
    uint256 public ptRate;

    // Events
    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );
    event Paused(address account);
    event Unpaused(address account);
    event YieldUpdated(address indexed user, uint256 indexed yieldInIBT);
    event Redeem(address indexed from, address indexed to, uint256 shares);
    event PTDeployed(address indexed principalToken, address indexed poolCreator);

    /**
     * @dev This is the function to deploy principalToken and other mock contracts
     * for testing. It is called before each test.
     */
    function setUp() public {
        admin = address(this); // to reduce number of lines and repeated vm pranks
        // default account for deploying scripts contracts. refer to line 35 of
        // https://github.com/foundry-rs/foundry/blob/master/evm/src/lib.rs for more details
        scriptAdmin = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;
        // Access Manager
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
        vm.prank(scriptAdmin);
        accessManager.grantRole(Roles.REGISTRY_ROLE, scriptAdmin, 0);
        vm.prank(scriptAdmin);
        accessManager.grantRole(Roles.FEE_SETTER_ROLE, scriptAdmin, 0);
        // setting tokenization fees to 0 (for convenience since they were added after all those tests)
        vm.prank(scriptAdmin);
        registry.setTokenizationFee(0);
        underlying = new MockERC20();
        underlying.initialize("MOCK UNDERLYING", "MUDL"); // deploys underlying mints 100000e18 token to caller
        ibt = new MockIBT();
        ibt.initialize("MOCK IBT", "MIBT", IERC20Metadata(address(underlying))); // deploys ibt which principalToken holds
        IBT_UNIT = 10 ** ibt.decimals();
        underlying.mint(address(ibt), 10000000e18); // mints 10000000e18 underlying tokens to ibt.

        // PT and YieldToken Instances
        PrincipalTokenInstanceScript principalTokenInstanceScript = new PrincipalTokenInstanceScript();
        YTInstanceScript ytInstanceScript = new YTInstanceScript();
        PrincipalToken principalTokenInstance = PrincipalToken(
            principalTokenInstanceScript.deployForTest(address(registry))
        );
        YieldToken ytInstance = YieldToken(ytInstanceScript.deployForTest());

        // PT and YieldToken Beacons
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
            EXPIRY
        );
        principalToken = PrincipalToken(principalTokenAddress);
        ptRate = principalToken.convertToUnderlying(IBT_UNIT);
        yt = YieldToken(principalToken.getYT());
    }

    /**
     * @dev Fuzz tests Claim Yield of amount for 4 users with positive yield.
     */
    function testClaimPositiveYieldOfAmountFuzz(
        uint128 rateFuzz,
        uint256 depositAmountFuzz,
        uint256 transferAmountFuzz
    ) public {
        // bounding variables passed as parameters
        rateFuzz = uint128(bound(rateFuzz, 25, 75)); // the test will use rateFuzz, rateFuzz - 25, rateFuzz + 25, and their complement to 100 (e.g. 100 - rateFuzz)
        depositAmountFuzz = bound(depositAmountFuzz, 0, 1000e18); // the test will use depositAmountFuzz and depositAmountFuzz * 2

        DepositData memory data;
        Rate memory rateData;
        YieldData memory yieldData;

        // deposit depositAmountFuzz for user1
        data.amountToDeposit = depositAmountFuzz;
        data.expected = principalToken.previewDeposit(data.amountToDeposit);
        data.actual = _testDeposit(data.amountToDeposit, MOCK_ADDR_1);
        assertEq(
            data.expected,
            data.actual,
            "After deposit for user1, balance is not equal to expected value"
        ); // checks if balances are accurate after deposit

        // deposit depositAmountFuzz for user2
        data.actual = _testDeposit(data.amountToDeposit, MOCK_ADDR_2);
        assertEq(
            data.expected,
            data.actual,
            "After deposit for user2, balance is not equal to expected value"
        ); // checks if balances are accurate after deposit

        yieldData.oldYieldUser1 = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_1);
        assertEq(yieldData.oldYieldUser1, 0, "Yield of user 1 is wrong");
        yieldData.oldYieldUser2 = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_2);
        assertEq(yieldData.oldYieldUser2, 0, "Yield of user 2 is wrong");
        rateData.oldIBTRate = ibt.previewRedeem(IBT_UNIT);

        // increase rate and time
        _increaseRate(int128(rateFuzz));
        vm.warp(block.timestamp + 100);

        rateData.newIBTRate = ibt.previewRedeem(IBT_UNIT);

        // computing yield generated by last step
        // for user1
        yieldData.ibtOfYTUser1 = _convertToSharesWithRate(
            principalToken.convertToUnderlying(yt.actualBalanceOf(MOCK_ADDR_1)),
            rateData.oldIBTRate,
            Math.Rounding.Floor
        );
        yieldData.yieldInUnderlyingUser1 = _convertToAssetsWithRate(
            yieldData.ibtOfYTUser1,
            (rateData.newIBTRate - rateData.oldIBTRate),
            Math.Rounding.Floor
        );
        yieldData.expectedYieldInIBTUser1 = ibt.convertToShares(yieldData.yieldInUnderlyingUser1);
        yieldData.actualYieldUser1 = _updateYield(MOCK_ADDR_1);

        // for user 2
        yieldData.ibtOfYTUser2 = _convertToSharesWithRate(
            principalToken.convertToUnderlying(yt.actualBalanceOf(MOCK_ADDR_2)),
            rateData.oldIBTRate,
            Math.Rounding.Floor
        );
        yieldData.yieldInUnderlyingUser2 = _convertToAssetsWithRate(
            yieldData.ibtOfYTUser2,
            (rateData.newIBTRate - rateData.oldIBTRate),
            Math.Rounding.Floor
        );
        yieldData.expectedYieldInIBTUser2 = ibt.convertToShares(yieldData.yieldInUnderlyingUser2);
        yieldData.expectedYieldInIBTUser2 -= _calcFees(
            yieldData.expectedYieldInIBTUser2,
            registry.getYieldFee()
        );
        yieldData.actualYieldUser2 = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_2);

        assertApproxEqAbs(
            yieldData.actualYieldUser1,
            yieldData.oldYieldUser1 + yieldData.expectedYieldInIBTUser1,
            10,
            "After rate change, yield for user1 is not equal to expected value"
        );

        assertApproxEqAbs(
            yieldData.actualYieldUser2,
            yieldData.oldYieldUser2 + yieldData.expectedYieldInIBTUser2,
            10,
            "After rate change, yield for user2 is not equal to expected value"
        );

        // update variables
        yieldData.oldYieldUser1 = yieldData.actualYieldUser1;
        yieldData.oldYieldUser2 = yieldData.actualYieldUser2;
        rateData.oldIBTRate = rateData.newIBTRate;

        // user 2 claims his yield
        yieldData.underlyingBalanceBefore = underlying.balanceOf(MOCK_ADDR_2);
        yieldData.yieldClaimed = yieldData.actualYieldUser2;

        vm.startPrank(MOCK_ADDR_2);
        principalToken.claimYield(MOCK_ADDR_2, 0);
        vm.stopPrank();
        assertEq(
            underlying.balanceOf(MOCK_ADDR_2),
            yieldData.underlyingBalanceBefore + ibt.previewRedeem(yieldData.yieldClaimed),
            "After claiming yield, underlying balance of user2 is not equal to expected value"
        );
        yieldData.actualYieldUser2 = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_2);
        assertApproxEqAbs(
            yieldData.actualYieldUser2,
            yieldData.oldYieldUser2 - yieldData.yieldClaimed,
            10,
            "After claiming yield, stored yield of user2 is not equal to expected value"
        );
        yieldData.oldYieldUser2 = yieldData.actualYieldUser2;

        // increase time (no rate change)
        vm.warp(block.timestamp + 100);

        // user 2 claims his yield
        yieldData.underlyingBalanceBefore = underlying.balanceOf(MOCK_ADDR_2);
        yieldData.yieldClaimed = yieldData.actualYieldUser2;
        vm.startPrank(MOCK_ADDR_2);
        principalToken.claimYield(MOCK_ADDR_2, 0);
        vm.stopPrank();
        assertEq(
            underlying.balanceOf(MOCK_ADDR_2),
            yieldData.underlyingBalanceBefore + ibt.previewRedeem(yieldData.yieldClaimed),
            "After claiming yield, underlying balance of user2 is not equal to expected value"
        );
        yieldData.actualYieldUser2 = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_2);
        assertApproxEqAbs(
            yieldData.actualYieldUser2,
            yieldData.oldYieldUser2 - yieldData.yieldClaimed,
            10,
            "After claiming yield, stored yield of user2 is not equal to expected value"
        );
        yieldData.oldYieldUser2 = yieldData.actualYieldUser2;
        assertEq(yieldData.oldYieldUser2, 0, "After claiming yield, yield of user2 should be 0");
        assertEq(_updateYield(MOCK_ADDR_2), 0, "After claiming yield, yield of user2 should be 0");

        rateData.oldIBTRate = rateData.newIBTRate;

        // deposit 2 * depositAmountFuzz for user3
        data.amountToDeposit = depositAmountFuzz * 2;
        data.expected = principalToken.previewDeposit(data.amountToDeposit);
        data.actual = _testDeposit(data.amountToDeposit, MOCK_ADDR_3);
        assertEq(
            data.expected,
            data.actual,
            "After deposit for user3, balance is not equal to expected value"
        );

        // deposit 2 * depositAmountFuzz for user4
        data.actual = _testDeposit(data.amountToDeposit, MOCK_ADDR_4);
        assertEq(
            data.expected,
            data.actual,
            "After deposit for user4, balance is not equal to expected value"
        );

        yieldData.oldYieldUser3 = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_3);
        yieldData.oldYieldUser4 = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_4);
        assertEq(yieldData.oldYieldUser3, 0, "Yield of user3 is wrong");
        assertEq(yieldData.oldYieldUser4, 0, "Yield of user4 is wrong");

        // increase time and rate
        vm.warp(block.timestamp + 100);
        _increaseRate(int128(rateFuzz + 25));

        rateData.newIBTRate = ibt.previewRedeem(IBT_UNIT);

        // computes yield for the last step for the 4 users
        yieldData.ibtOfYTUser1 = _convertToSharesWithRate(
            principalToken.convertToUnderlying(yt.actualBalanceOf(MOCK_ADDR_1)),
            rateData.oldIBTRate,
            Math.Rounding.Floor
        );
        yieldData.ibtOfYTUser2 = _convertToSharesWithRate(
            principalToken.convertToUnderlying(yt.actualBalanceOf(MOCK_ADDR_2)),
            rateData.oldIBTRate,
            Math.Rounding.Floor
        );
        yieldData.ibtOfYTUser3 = _convertToSharesWithRate(
            principalToken.convertToUnderlying(yt.actualBalanceOf(MOCK_ADDR_3)),
            rateData.oldIBTRate,
            Math.Rounding.Floor
        );
        yieldData.ibtOfYTUser4 = _convertToSharesWithRate(
            principalToken.convertToUnderlying(yt.actualBalanceOf(MOCK_ADDR_4)),
            rateData.oldIBTRate,
            Math.Rounding.Floor
        );

        yieldData.yieldInUnderlyingUser1 = _convertToAssetsWithRate(
            yieldData.ibtOfYTUser1,
            (rateData.newIBTRate - rateData.oldIBTRate),
            Math.Rounding.Floor
        );
        yieldData.yieldInUnderlyingUser2 = _convertToAssetsWithRate(
            yieldData.ibtOfYTUser2,
            (rateData.newIBTRate - rateData.oldIBTRate),
            Math.Rounding.Floor
        );
        yieldData.yieldInUnderlyingUser3 = _convertToAssetsWithRate(
            yieldData.ibtOfYTUser3,
            (rateData.newIBTRate - rateData.oldIBTRate),
            Math.Rounding.Floor
        );
        yieldData.yieldInUnderlyingUser4 = _convertToAssetsWithRate(
            yieldData.ibtOfYTUser4,
            (rateData.newIBTRate - rateData.oldIBTRate),
            Math.Rounding.Floor
        );

        yieldData.expectedYieldInIBTUser1 = ibt.convertToShares(yieldData.yieldInUnderlyingUser1);
        yieldData.actualYieldUser1 = _updateYield(MOCK_ADDR_1);

        yieldData.expectedYieldInIBTUser2 = ibt.convertToShares(yieldData.yieldInUnderlyingUser2);
        yieldData.actualYieldUser2 = _updateYield(MOCK_ADDR_2);

        yieldData.expectedYieldInIBTUser3 = ibt.convertToShares(yieldData.yieldInUnderlyingUser3);
        yieldData.actualYieldUser3 = _updateYield(MOCK_ADDR_3);

        yieldData.expectedYieldInIBTUser4 = ibt.convertToShares(yieldData.yieldInUnderlyingUser4);
        yieldData.actualYieldUser4 = _updateYield(MOCK_ADDR_4);

        assertApproxEqAbs(
            yieldData.actualYieldUser1,
            yieldData.oldYieldUser1 + yieldData.expectedYieldInIBTUser1,
            10,
            "After rate change, yield for user1 is not equal to expected value"
        );
        assertApproxEqAbs(
            yieldData.actualYieldUser2,
            yieldData.oldYieldUser2 + yieldData.expectedYieldInIBTUser2,
            10,
            "After rate change, yield for user2 is not equal to expected value"
        );
        assertApproxEqAbs(
            yieldData.actualYieldUser3,
            yieldData.oldYieldUser3 + yieldData.expectedYieldInIBTUser3,
            10,
            "After rate change, yield for user3 is not equal to expected value"
        );
        assertApproxEqAbs(
            yieldData.actualYieldUser4,
            yieldData.oldYieldUser4 + yieldData.expectedYieldInIBTUser4,
            10,
            "After rate change, yield for user4 is not equal to expected value"
        );

        yieldData.oldYieldUser1 = yieldData.actualYieldUser1;
        yieldData.oldYieldUser2 = yieldData.actualYieldUser2;
        yieldData.oldYieldUser3 = yieldData.actualYieldUser3;
        yieldData.oldYieldUser4 = yieldData.actualYieldUser4;

        // user 2 claims his yield
        yieldData.fee2 = _calcFees(yieldData.actualYieldUser2, registry.getYieldFee());
        yieldData.underlyingBalanceBefore = underlying.balanceOf(MOCK_ADDR_2);
        yieldData.yieldClaimed = yieldData.actualYieldUser2;
        vm.startPrank(MOCK_ADDR_2);
        principalToken.claimYield(MOCK_ADDR_2, 0);
        vm.stopPrank();
        assertEq(
            underlying.balanceOf(MOCK_ADDR_2),
            yieldData.underlyingBalanceBefore +
                ibt.previewRedeem(yieldData.yieldClaimed - yieldData.fee2),
            "After claiming yield, underlying balance of user2 is not equal to expected value"
        );

        yieldData.actualYieldUser2 = _updateYield(MOCK_ADDR_2);
        assertApproxEqAbs(
            yieldData.actualYieldUser2,
            yieldData.oldYieldUser2 - yieldData.yieldClaimed,
            10,
            "After claiming yield, stored yield of user2 is not equal to expected value"
        );
        yieldData.oldYieldUser2 = yieldData.actualYieldUser2;

        // user 3 claims his yield
        yieldData.fee3 = _calcFees(yieldData.actualYieldUser3, registry.getYieldFee());
        yieldData.underlyingBalanceBefore = underlying.balanceOf(MOCK_ADDR_3);
        yieldData.yieldClaimed = yieldData.actualYieldUser3;
        vm.startPrank(MOCK_ADDR_3);
        principalToken.claimYield(MOCK_ADDR_3, 0);
        vm.stopPrank();
        assertEq(
            underlying.balanceOf(MOCK_ADDR_3),
            yieldData.underlyingBalanceBefore +
                ibt.previewRedeem(yieldData.yieldClaimed - yieldData.fee3),
            "After claiming yield, underlying balance of user3 is not equal to expected value"
        );
        yieldData.actualYieldUser3 = _updateYield(MOCK_ADDR_3);
        assertApproxEqAbs(
            yieldData.actualYieldUser3,
            yieldData.oldYieldUser3 - yieldData.yieldClaimed,
            10,
            "After claiming yield, stored yield of user3 is not equal to expected value"
        );
        yieldData.oldYieldUser3 = yieldData.actualYieldUser3;

        rateData.oldIBTRate = rateData.newIBTRate;

        // increase time and rate
        vm.warp(block.timestamp + 100);
        _increaseRate(int128(rateFuzz - 25));

        rateData.newIBTRate = ibt.previewRedeem(IBT_UNIT);

        // computes the yield generated by the last step for the four users
        yieldData.ibtOfYTUser1 = _convertToSharesWithRate(
            principalToken.convertToUnderlying(yt.actualBalanceOf(MOCK_ADDR_1)),
            rateData.oldIBTRate,
            Math.Rounding.Floor
        );
        yieldData.ibtOfYTUser2 = _convertToSharesWithRate(
            principalToken.convertToUnderlying(yt.actualBalanceOf(MOCK_ADDR_2)),
            rateData.oldIBTRate,
            Math.Rounding.Floor
        );
        yieldData.ibtOfYTUser3 = _convertToSharesWithRate(
            principalToken.convertToUnderlying(yt.actualBalanceOf(MOCK_ADDR_3)),
            rateData.oldIBTRate,
            Math.Rounding.Floor
        );
        yieldData.ibtOfYTUser4 = _convertToSharesWithRate(
            principalToken.convertToUnderlying(yt.actualBalanceOf(MOCK_ADDR_4)),
            rateData.oldIBTRate,
            Math.Rounding.Floor
        );

        yieldData.yieldInUnderlyingUser1 = _convertToAssetsWithRate(
            yieldData.ibtOfYTUser1,
            (rateData.newIBTRate - rateData.oldIBTRate),
            Math.Rounding.Floor
        );
        yieldData.yieldInUnderlyingUser2 = _convertToAssetsWithRate(
            yieldData.ibtOfYTUser2,
            (rateData.newIBTRate - rateData.oldIBTRate),
            Math.Rounding.Floor
        );
        yieldData.yieldInUnderlyingUser3 = _convertToAssetsWithRate(
            yieldData.ibtOfYTUser3,
            (rateData.newIBTRate - rateData.oldIBTRate),
            Math.Rounding.Floor
        );
        yieldData.yieldInUnderlyingUser4 = _convertToAssetsWithRate(
            yieldData.ibtOfYTUser4,
            (rateData.newIBTRate - rateData.oldIBTRate),
            Math.Rounding.Floor
        );

        yieldData.expectedYieldInIBTUser1 = ibt.convertToShares(yieldData.yieldInUnderlyingUser1);
        yieldData.actualYieldUser1 = _updateYield(MOCK_ADDR_1);

        yieldData.expectedYieldInIBTUser2 = ibt.convertToShares(yieldData.yieldInUnderlyingUser2);
        yieldData.actualYieldUser2 = _updateYield(MOCK_ADDR_2);

        yieldData.expectedYieldInIBTUser3 = ibt.convertToShares(yieldData.yieldInUnderlyingUser3);
        yieldData.actualYieldUser3 = _updateYield(MOCK_ADDR_3);

        yieldData.expectedYieldInIBTUser4 = ibt.convertToShares(yieldData.yieldInUnderlyingUser4);
        yieldData.actualYieldUser4 = _updateYield(MOCK_ADDR_4);

        assertApproxEqAbs(
            yieldData.actualYieldUser1,
            yieldData.expectedYieldInIBTUser1 + yieldData.oldYieldUser1,
            10,
            "After rate chang, yield for user1 is not equal to expected value"
        );
        assertApproxEqAbs(
            yieldData.actualYieldUser2,
            yieldData.expectedYieldInIBTUser2 + yieldData.oldYieldUser2,
            10,
            "After rate change, yield for user2 is not equal to expected value"
        );
        assertApproxEqAbs(
            yieldData.actualYieldUser3,
            yieldData.expectedYieldInIBTUser3 + yieldData.oldYieldUser3,
            10,
            "After rate change, yield for user3 is not equal to expected value"
        );
        assertApproxEqAbs(
            yieldData.actualYieldUser4,
            yieldData.expectedYieldInIBTUser4 + yieldData.oldYieldUser4,
            10,
            "After rate change, yield for user4 is not equal to expected value"
        );

        yieldData.oldYieldUser1 = yieldData.actualYieldUser1;
        yieldData.oldYieldUser2 = yieldData.actualYieldUser2;
        yieldData.oldYieldUser3 = yieldData.actualYieldUser3;
        yieldData.oldYieldUser4 = yieldData.actualYieldUser4;

        // user 2 claims his yield
        yieldData.fee2 = _calcFees(yieldData.actualYieldUser2, registry.getYieldFee());
        yieldData.underlyingBalanceBefore = underlying.balanceOf(MOCK_ADDR_2);
        yieldData.yieldClaimed = yieldData.actualYieldUser2;
        vm.startPrank(MOCK_ADDR_2);
        principalToken.claimYield(MOCK_ADDR_2, 0);
        vm.stopPrank();
        assertEq(
            underlying.balanceOf(MOCK_ADDR_2),
            yieldData.underlyingBalanceBefore +
                ibt.previewRedeem(yieldData.yieldClaimed - yieldData.fee2),
            "After claiming yield, underlying balance of user2 is not equal to expected value"
        );

        yieldData.actualYieldUser2 = _updateYield(MOCK_ADDR_2);
        assertApproxEqAbs(
            yieldData.actualYieldUser2,
            yieldData.oldYieldUser2 - yieldData.yieldClaimed,
            1000,
            "After claiming yield, stored yield of user2 is not equal to expected value"
        );
        yieldData.oldYieldUser2 = yieldData.actualYieldUser2;

        rateData.oldIBTRate = rateData.newIBTRate;

        // increase time and rate
        vm.warp(block.timestamp + 100);
        _increaseRate(int128(100 - rateFuzz));

        rateData.newIBTRate = ibt.convertToAssets(IBT_UNIT);

        // computes the yield of the last step for the 4 users
        yieldData.ibtOfYTUser1 = _convertToSharesWithRate(
            principalToken.convertToUnderlying(yt.actualBalanceOf(MOCK_ADDR_1)),
            rateData.oldIBTRate,
            Math.Rounding.Floor
        );
        yieldData.ibtOfYTUser2 = _convertToSharesWithRate(
            principalToken.convertToUnderlying(yt.actualBalanceOf(MOCK_ADDR_2)),
            rateData.oldIBTRate,
            Math.Rounding.Floor
        );
        yieldData.ibtOfYTUser3 = _convertToSharesWithRate(
            principalToken.convertToUnderlying(yt.actualBalanceOf(MOCK_ADDR_3)),
            rateData.oldIBTRate,
            Math.Rounding.Floor
        );
        yieldData.ibtOfYTUser4 = _convertToSharesWithRate(
            principalToken.convertToUnderlying(yt.actualBalanceOf(MOCK_ADDR_4)),
            rateData.oldIBTRate,
            Math.Rounding.Floor
        );

        yieldData.yieldInUnderlyingUser1 = _convertToAssetsWithRate(
            yieldData.ibtOfYTUser1,
            (rateData.newIBTRate - rateData.oldIBTRate),
            Math.Rounding.Floor
        );
        yieldData.yieldInUnderlyingUser2 = _convertToAssetsWithRate(
            yieldData.ibtOfYTUser2,
            (rateData.newIBTRate - rateData.oldIBTRate),
            Math.Rounding.Floor
        );
        yieldData.yieldInUnderlyingUser3 = _convertToAssetsWithRate(
            yieldData.ibtOfYTUser3,
            (rateData.newIBTRate - rateData.oldIBTRate),
            Math.Rounding.Floor
        );
        yieldData.yieldInUnderlyingUser4 = _convertToAssetsWithRate(
            yieldData.ibtOfYTUser4,
            (rateData.newIBTRate - rateData.oldIBTRate),
            Math.Rounding.Floor
        );

        yieldData.expectedYieldInIBTUser1 = ibt.convertToShares(yieldData.yieldInUnderlyingUser1);
        yieldData.actualYieldUser1 = _updateYield(MOCK_ADDR_1);

        yieldData.expectedYieldInIBTUser2 = ibt.convertToShares(yieldData.yieldInUnderlyingUser2);
        yieldData.actualYieldUser2 = _updateYield(MOCK_ADDR_2);

        yieldData.expectedYieldInIBTUser3 = ibt.convertToShares(yieldData.yieldInUnderlyingUser3);
        yieldData.actualYieldUser3 = _updateYield(MOCK_ADDR_3);

        yieldData.expectedYieldInIBTUser4 = ibt.convertToShares(yieldData.yieldInUnderlyingUser4);
        yieldData.actualYieldUser4 = _updateYield(MOCK_ADDR_4);

        assertApproxEqAbs(
            yieldData.actualYieldUser1,
            yieldData.oldYieldUser1 + yieldData.expectedYieldInIBTUser1,
            1000,
            "After rate change, yield for user1 is not equal to expected value"
        );
        assertApproxEqAbs(
            yieldData.actualYieldUser2,
            yieldData.oldYieldUser2 + yieldData.expectedYieldInIBTUser2,
            1000,
            "After rate change, yield for user2 is not equal to expected value"
        );
        assertApproxEqAbs(
            yieldData.actualYieldUser3,
            yieldData.oldYieldUser3 + yieldData.expectedYieldInIBTUser3,
            1000,
            "After rate change, yield for user3 is not equal to expected value"
        );
        assertApproxEqAbs(
            yieldData.actualYieldUser4,
            yieldData.oldYieldUser4 + yieldData.expectedYieldInIBTUser4,
            1000,
            "After rate change, yield for user4 is not equal to expected value"
        );

        yieldData.oldYieldUser1 = yieldData.actualYieldUser1;
        yieldData.oldYieldUser2 = yieldData.actualYieldUser2;
        yieldData.oldYieldUser3 = yieldData.actualYieldUser3;
        yieldData.oldYieldUser4 = yieldData.actualYieldUser4;

        // user 4 transfers 1/5th of his YTs to user3
        yieldData.ytBalanceBeforeUser3 = yt.actualBalanceOf(MOCK_ADDR_3);
        yieldData.ytBalanceBeforeUser4 = yt.actualBalanceOf(MOCK_ADDR_4);
        transferAmountFuzz = bound(transferAmountFuzz, 0, yieldData.ytBalanceBeforeUser4 / 5);
        vm.prank(MOCK_ADDR_4);
        yt.transfer(MOCK_ADDR_3, transferAmountFuzz);
        yieldData.ytBalanceAfterUser3 = yt.actualBalanceOf(MOCK_ADDR_3);
        yieldData.ytBalanceAfterUser4 = yt.actualBalanceOf(MOCK_ADDR_4);
        assertEq(
            yieldData.ytBalanceAfterUser3,
            yieldData.ytBalanceBeforeUser3 + transferAmountFuzz
        );
        assertEq(
            yieldData.ytBalanceAfterUser4,
            yieldData.ytBalanceBeforeUser4 - transferAmountFuzz
        );

        // update yield with user3 and 4
        yieldData.actualYieldUser3 = _updateYield(MOCK_ADDR_3);
        yieldData.actualYieldUser4 = _updateYield(MOCK_ADDR_4);
        assertEq(
            yieldData.actualYieldUser3,
            yieldData.oldYieldUser3,
            "After transfer, yield of user 3 is unchanged"
        );
        assertEq(
            yieldData.actualYieldUser4,
            yieldData.oldYieldUser4,
            "After transfer, yield of user 4 is unchanged"
        );

        // user 3 claims his yield (and no additional yield due to above transfer)
        yieldData.fee3 = _calcFees(yieldData.actualYieldUser3, registry.getYieldFee());
        yieldData.underlyingBalanceBefore = underlying.balanceOf(MOCK_ADDR_3);
        yieldData.yieldClaimed = yieldData.actualYieldUser3;
        vm.startPrank(MOCK_ADDR_3);
        principalToken.claimYield(MOCK_ADDR_3, 0);
        vm.stopPrank();
        assertEq(
            underlying.balanceOf(MOCK_ADDR_3),
            yieldData.underlyingBalanceBefore +
                ibt.previewRedeem(yieldData.yieldClaimed - yieldData.fee3),
            "After claiming yield, underlying balance of user3 is not equal to expected value"
        );
        yieldData.actualYieldUser3 = _updateYield(MOCK_ADDR_3);
        assertApproxEqAbs(
            yieldData.actualYieldUser3,
            yieldData.oldYieldUser3 - yieldData.yieldClaimed,
            10,
            "After claiming yield, stored yield of user3 is not equal to expected value"
        );
        yieldData.oldYieldUser3 = yieldData.actualYieldUser3;
        assertApproxEqAbs(
            yieldData.oldYieldUser3,
            0,
            10,
            "After Claiming all yield of amount, stored yield of user3 should be 0"
        );

        rateData.oldIBTRate = rateData.newIBTRate;

        // increase time and rate
        vm.warp(block.timestamp + 100);
        _increaseRate(int128(100 - (rateFuzz - 25)));

        rateData.newIBTRate = ibt.previewRedeem(IBT_UNIT);

        // computes yield of last step for the 4 users
        yieldData.ibtOfYTUser1 = _convertToSharesWithRate(
            principalToken.convertToUnderlying(yt.actualBalanceOf(MOCK_ADDR_1)),
            rateData.oldIBTRate,
            Math.Rounding.Floor
        );
        yieldData.ibtOfYTUser2 = _convertToSharesWithRate(
            principalToken.convertToUnderlying(yt.actualBalanceOf(MOCK_ADDR_2)),
            rateData.oldIBTRate,
            Math.Rounding.Floor
        );
        yieldData.ibtOfYTUser3 = _convertToSharesWithRate(
            principalToken.convertToUnderlying(yt.actualBalanceOf(MOCK_ADDR_3)),
            rateData.oldIBTRate,
            Math.Rounding.Floor
        );
        yieldData.ibtOfYTUser4 = _convertToSharesWithRate(
            principalToken.convertToUnderlying(yt.actualBalanceOf(MOCK_ADDR_4)),
            rateData.oldIBTRate,
            Math.Rounding.Floor
        );

        yieldData.yieldInUnderlyingUser1 = _convertToAssetsWithRate(
            yieldData.ibtOfYTUser1,
            (rateData.newIBTRate - rateData.oldIBTRate),
            Math.Rounding.Floor
        );
        yieldData.yieldInUnderlyingUser2 = _convertToAssetsWithRate(
            yieldData.ibtOfYTUser2,
            (rateData.newIBTRate - rateData.oldIBTRate),
            Math.Rounding.Floor
        );
        yieldData.yieldInUnderlyingUser3 = _convertToAssetsWithRate(
            yieldData.ibtOfYTUser3,
            (rateData.newIBTRate - rateData.oldIBTRate),
            Math.Rounding.Floor
        );
        yieldData.yieldInUnderlyingUser4 = _convertToAssetsWithRate(
            yieldData.ibtOfYTUser4,
            (rateData.newIBTRate - rateData.oldIBTRate),
            Math.Rounding.Floor
        );

        yieldData.expectedYieldInIBTUser1 = ibt.convertToShares(yieldData.yieldInUnderlyingUser1);
        yieldData.actualYieldUser1 = _updateYield(MOCK_ADDR_1);

        yieldData.expectedYieldInIBTUser2 = ibt.convertToShares(yieldData.yieldInUnderlyingUser2);
        yieldData.actualYieldUser2 = _updateYield(MOCK_ADDR_2);

        yieldData.expectedYieldInIBTUser3 = ibt.convertToShares(yieldData.yieldInUnderlyingUser3);
        yieldData.actualYieldUser3 = _updateYield(MOCK_ADDR_3);

        yieldData.expectedYieldInIBTUser4 = ibt.convertToShares(yieldData.yieldInUnderlyingUser4);
        yieldData.actualYieldUser4 = _updateYield(MOCK_ADDR_4);

        assertApproxEqAbs(
            yieldData.actualYieldUser1,
            yieldData.expectedYieldInIBTUser1 + yieldData.oldYieldUser1,
            10,
            "After rate change, yield for user1 is not equal to expected value"
        );
        assertApproxEqAbs(
            yieldData.actualYieldUser2,
            yieldData.expectedYieldInIBTUser2 + yieldData.oldYieldUser2,
            10,
            "After rate change, yield for user2 is not equal to expected value"
        );
        assertApproxEqAbs(
            yieldData.actualYieldUser3,
            yieldData.expectedYieldInIBTUser3 + yieldData.oldYieldUser3,
            10,
            "After rate change, yield for user3 is not equal to expected value"
        );
        assertApproxEqAbs(
            yieldData.actualYieldUser4,
            yieldData.expectedYieldInIBTUser4 + yieldData.oldYieldUser4,
            10,
            "After rate change, yield for user4 is not equal to expected value"
        );

        yieldData.oldYieldUser1 = yieldData.actualYieldUser1;
        yieldData.oldYieldUser2 = yieldData.actualYieldUser2;
        yieldData.oldYieldUser3 = yieldData.actualYieldUser3;
        yieldData.oldYieldUser4 = yieldData.actualYieldUser4;

        // user 2 claims his yield
        yieldData.fee2 = _calcFees(yieldData.actualYieldUser2, registry.getYieldFee());
        yieldData.underlyingBalanceBefore = underlying.balanceOf(MOCK_ADDR_2);
        yieldData.yieldClaimed = yieldData.actualYieldUser2;
        vm.startPrank(MOCK_ADDR_2);
        principalToken.claimYield(MOCK_ADDR_2, 0);
        vm.stopPrank();
        assertEq(
            underlying.balanceOf(MOCK_ADDR_2),
            yieldData.underlyingBalanceBefore +
                ibt.convertToAssets(yieldData.yieldClaimed - yieldData.fee2),
            "After claiming yield, underlying balance of user2 is not equal to expected value"
        );
        yieldData.actualYieldUser2 = _updateYield(MOCK_ADDR_2);
        assertApproxEqAbs(
            yieldData.actualYieldUser2,
            yieldData.oldYieldUser2 - yieldData.yieldClaimed,
            10,
            "After claiming yield, underlying balance of user2 is not equal to expected value"
        );
        yieldData.oldYieldUser2 = yieldData.actualYieldUser2;

        // user 4 claims his yield
        yieldData.fee4 = _calcFees(yieldData.actualYieldUser4, registry.getYieldFee());
        yieldData.underlyingBalanceBefore = underlying.balanceOf(MOCK_ADDR_4);
        yieldData.yieldClaimed = yieldData.actualYieldUser4;
        vm.startPrank(MOCK_ADDR_4);
        principalToken.claimYield(MOCK_ADDR_4, 0);
        vm.stopPrank();
        assertEq(
            underlying.balanceOf(MOCK_ADDR_4),
            yieldData.underlyingBalanceBefore +
                ibt.convertToAssets(yieldData.yieldClaimed - yieldData.fee4),
            "After Claiming yield, underlying balance of user4 is not equal to expected value"
        );

        yieldData.actualYieldUser4 = _updateYield(MOCK_ADDR_4);
        assertApproxEqAbs(
            yieldData.actualYieldUser4,
            yieldData.oldYieldUser4 - yieldData.yieldClaimed,
            10,
            "After Claiming yield, stored yield of user4 is not equal to expected value"
        );
        yieldData.oldYieldUser4 = yieldData.actualYieldUser4;

        // user 3 claims his yield
        yieldData.fee3 = _calcFees(yieldData.actualYieldUser3, registry.getYieldFee());
        yieldData.underlyingBalanceBefore = underlying.balanceOf(MOCK_ADDR_3);
        yieldData.yieldClaimed = yieldData.actualYieldUser3;
        vm.startPrank(MOCK_ADDR_3);
        principalToken.claimYield(MOCK_ADDR_3, 0);
        vm.stopPrank();
        assertEq(
            underlying.balanceOf(MOCK_ADDR_3),
            yieldData.underlyingBalanceBefore +
                ibt.convertToAssets(yieldData.yieldClaimed - yieldData.fee3),
            "After claiming yield, underlying balance of user3 is not equal to expected value"
        );
        yieldData.actualYieldUser3 = _updateYield(MOCK_ADDR_3);
        assertApproxEqAbs(
            yieldData.actualYieldUser3,
            yieldData.oldYieldUser3 - yieldData.yieldClaimed,
            10,
            "After claiming yield, stored yield of user3 is not equal to expected value"
        );
        yieldData.oldYieldUser3 = yieldData.actualYieldUser3;

        // user 4 transfers all his YTs to user 3
        yieldData.ytBalanceBeforeUser3 = yt.actualBalanceOf(MOCK_ADDR_3);
        yieldData.ytBalanceBeforeUser4 = yt.actualBalanceOf(MOCK_ADDR_4);
        vm.prank(MOCK_ADDR_4);
        yt.transfer(MOCK_ADDR_3, yieldData.ytBalanceBeforeUser4);
        yieldData.ytBalanceAfterUser3 = yt.actualBalanceOf(MOCK_ADDR_3);
        yieldData.ytBalanceAfterUser4 = yt.actualBalanceOf(MOCK_ADDR_4);
        assertEq(
            yieldData.ytBalanceAfterUser3,
            yieldData.ytBalanceBeforeUser3 + yieldData.ytBalanceBeforeUser4
        );
        assertEq(yieldData.ytBalanceAfterUser4, 0);
        yieldData.actualYieldUser3 = _updateYield(MOCK_ADDR_3);
        yieldData.actualYieldUser4 = _updateYield(MOCK_ADDR_4);
        assertEq(
            yieldData.actualYieldUser3,
            yieldData.oldYieldUser3,
            "After transfer, yield of user 3 is changed"
        );
        assertEq(
            yieldData.actualYieldUser4,
            yieldData.oldYieldUser4,
            "After transfer, yield of user 4 is changed"
        );

        // user 4 claims his yield
        yieldData.fee4 = _calcFees(yieldData.actualYieldUser4, registry.getYieldFee());
        yieldData.underlyingBalanceBefore = underlying.balanceOf(MOCK_ADDR_4);
        yieldData.yieldClaimed = yieldData.actualYieldUser4;
        vm.prank(MOCK_ADDR_4);
        principalToken.claimYield(MOCK_ADDR_4, 0);
        assertEq(
            underlying.balanceOf(MOCK_ADDR_4),
            yieldData.underlyingBalanceBefore +
                ibt.convertToAssets(yieldData.yieldClaimed - yieldData.fee4),
            "After claiming yield, underlying balance of user4 is not equal to expected value"
        );
        yieldData.actualYieldUser4 = _updateYield(MOCK_ADDR_4);
        assertApproxEqAbs(
            yieldData.actualYieldUser4,
            yieldData.oldYieldUser4 - yieldData.yieldClaimed,
            10,
            "After claiming yield, stored yield of user4 is not equal to expected value"
        );
        yieldData.oldYieldUser4 = yieldData.actualYieldUser4;
        assertEq(
            yieldData.oldYieldUser4,
            0,
            "After Claiming all yield of amount, stored yield of user4 should be 0"
        );

        rateData.oldIBTRate = rateData.newIBTRate;

        // increase time and rate
        vm.warp(block.timestamp + 100);
        _increaseRate(int128(rateFuzz + 25));

        rateData.newIBTRate = ibt.previewRedeem(IBT_UNIT);

        // computes the yield of the last step for the 4 users
        yieldData.ibtOfYTUser1 = _convertToSharesWithRate(
            principalToken.convertToUnderlying(yt.actualBalanceOf(MOCK_ADDR_1)),
            rateData.oldIBTRate,
            Math.Rounding.Floor
        );
        yieldData.ibtOfYTUser2 = _convertToSharesWithRate(
            principalToken.convertToUnderlying(yt.actualBalanceOf(MOCK_ADDR_2)),
            rateData.oldIBTRate,
            Math.Rounding.Floor
        );
        yieldData.ibtOfYTUser3 = _convertToSharesWithRate(
            principalToken.convertToUnderlying(yt.actualBalanceOf(MOCK_ADDR_3)),
            rateData.oldIBTRate,
            Math.Rounding.Floor
        );
        yieldData.ibtOfYTUser4 = _convertToSharesWithRate(
            principalToken.convertToUnderlying(yt.actualBalanceOf(MOCK_ADDR_4)),
            rateData.oldIBTRate,
            Math.Rounding.Floor
        );
        assertEq(
            yieldData.ibtOfYTUser4,
            0,
            "After transfering every YieldToken user 4 should have 0 ibtOfYT"
        );

        yieldData.yieldInUnderlyingUser1 = _convertToAssetsWithRate(
            yieldData.ibtOfYTUser1,
            (rateData.newIBTRate - rateData.oldIBTRate),
            Math.Rounding.Floor
        );
        yieldData.yieldInUnderlyingUser2 = _convertToAssetsWithRate(
            yieldData.ibtOfYTUser2,
            (rateData.newIBTRate - rateData.oldIBTRate),
            Math.Rounding.Floor
        );
        yieldData.yieldInUnderlyingUser3 = _convertToAssetsWithRate(
            yieldData.ibtOfYTUser3,
            (rateData.newIBTRate - rateData.oldIBTRate),
            Math.Rounding.Floor
        );
        yieldData.yieldInUnderlyingUser4 = _convertToAssetsWithRate(
            yieldData.ibtOfYTUser4,
            (rateData.newIBTRate - rateData.oldIBTRate),
            Math.Rounding.Floor
        );

        assertEq(
            yieldData.yieldInUnderlyingUser4,
            0,
            "After claiming all his yield and having 0 YieldToken, user 4 should have 0 yield"
        );

        yieldData.expectedYieldInIBTUser1 = ibt.convertToShares(yieldData.yieldInUnderlyingUser1);
        yieldData.actualYieldUser1 = _updateYield(MOCK_ADDR_1);

        yieldData.expectedYieldInIBTUser2 = ibt.convertToShares(yieldData.yieldInUnderlyingUser2);
        yieldData.actualYieldUser2 = _updateYield(MOCK_ADDR_2);

        yieldData.expectedYieldInIBTUser3 = ibt.convertToShares(yieldData.yieldInUnderlyingUser3);
        yieldData.actualYieldUser3 = _updateYield(MOCK_ADDR_3);

        yieldData.expectedYieldInIBTUser4 = ibt.convertToShares(yieldData.yieldInUnderlyingUser4);
        yieldData.actualYieldUser4 = _updateYield(MOCK_ADDR_4);

        assertEq(
            yieldData.actualYieldUser4,
            0,
            "After claiming all his yield and having 0 YieldToken, user 4 should have 0 yield"
        );
        assertEq(
            yieldData.expectedYieldInIBTUser4,
            0,
            "After claiming all his yield and having 0 YieldToken, user 4 should have 0 yield"
        );

        assertApproxEqAbs(
            yieldData.actualYieldUser1,
            yieldData.oldYieldUser1 + yieldData.expectedYieldInIBTUser1,
            10,
            "After rate change, yield for user1 is not equal to expected value"
        );
        assertApproxEqAbs(
            yieldData.actualYieldUser2,
            yieldData.expectedYieldInIBTUser2 + yieldData.oldYieldUser2,
            10,
            "After rate change, yield for user2 is not equal to expected value"
        );
        assertApproxEqAbs(
            yieldData.actualYieldUser3,
            yieldData.expectedYieldInIBTUser3 + yieldData.oldYieldUser3,
            10,
            "After rate change, yield for user3 is not equal to expected value 1"
        );

        // claim everything with all users
        yieldData.fee1 = _calcFees(yieldData.actualYieldUser1, registry.getYieldFee());
        yieldData.fee2 = _calcFees(yieldData.actualYieldUser2, registry.getYieldFee());
        yieldData.fee3 = _calcFees(yieldData.actualYieldUser3, registry.getYieldFee());
        yieldData.fee4 = _calcFees(yieldData.actualYieldUser4, registry.getYieldFee());
        assertEq(
            yieldData.fee4,
            0,
            "After claiming all his yield and having 0 YT, user 4 should have 0 yield hence 0 fees"
        );

        yieldData.underlyingBalanceBefore = underlying.balanceOf(MOCK_ADDR_1);
        vm.prank(MOCK_ADDR_1);
        principalToken.claimYield(MOCK_ADDR_1, 0);
        assertEq(
            underlying.balanceOf(MOCK_ADDR_1),
            yieldData.underlyingBalanceBefore +
                ibt.convertToAssets(yieldData.actualYieldUser1 - yieldData.fee1),
            "After Claiming yield, balance of user1 is not equal to expected value"
        );
        yieldData.actualYieldUser1 = _updateYield(MOCK_ADDR_1);
        assertApproxEqAbs(
            yieldData.actualYieldUser1,
            0,
            10,
            "After claiming yield, stored yield of user1 is not equal to expected value"
        );

        yieldData.underlyingBalanceBefore = underlying.balanceOf(MOCK_ADDR_2);
        vm.startPrank(MOCK_ADDR_2);
        principalToken.claimYield(MOCK_ADDR_2, 0);
        vm.stopPrank();
        assertEq(
            underlying.balanceOf(MOCK_ADDR_2),
            yieldData.underlyingBalanceBefore +
                ibt.convertToAssets(yieldData.actualYieldUser2 - yieldData.fee2),
            "After Claiming yield, balance of user2 is not equal to expected value"
        );
        yieldData.actualYieldUser2 = _updateYield(MOCK_ADDR_2);
        assertApproxEqAbs(
            yieldData.actualYieldUser2,
            0,
            10,
            "After claiming yield, stored yield of user2 is not equal to expected value"
        );

        yieldData.underlyingBalanceBefore = underlying.balanceOf(MOCK_ADDR_3);
        vm.startPrank(MOCK_ADDR_3);
        principalToken.claimYield(MOCK_ADDR_3, 0);
        vm.stopPrank();
        assertEq(
            underlying.balanceOf(MOCK_ADDR_3),
            yieldData.underlyingBalanceBefore +
                ibt.convertToAssets(yieldData.actualYieldUser3 - yieldData.fee3),
            "After Claiming yield, balance of user3 is not equal to expected value"
        );
        yieldData.actualYieldUser3 = _updateYield(MOCK_ADDR_3);
        assertApproxEqAbs(
            yieldData.actualYieldUser3,
            0,
            10,
            "After claiming yield, stored yield of user3 is not equal to expected value"
        );

        yieldData.underlyingBalanceBefore = underlying.balanceOf(MOCK_ADDR_4);
        vm.startPrank(MOCK_ADDR_4);
        principalToken.claimYield(MOCK_ADDR_4, 0);
        vm.stopPrank();
        assertEq(
            underlying.balanceOf(MOCK_ADDR_4),
            yieldData.underlyingBalanceBefore +
                ibt.convertToAssets(yieldData.actualYieldUser4 - yieldData.fee4),
            "After Claiming yield, balance of user4 is not equal to expected value"
        );
        yieldData.actualYieldUser4 = _updateYield(MOCK_ADDR_4);
        assertApproxEqAbs(
            yieldData.actualYieldUser4,
            0,
            10,
            "After claiming yield, stored yield of user4 is not equal to expected value"
        );
        assertApproxEqAbs(
            underlying.balanceOf(MOCK_ADDR_4),
            yieldData.underlyingBalanceBefore,
            10,
            "After Claiming yield, balance of user4 is not equal to expected value"
        );
    }

    /**
     * @dev Fuzz tests Claim Yield of amount for 4 users with a mix of positive and negative yield.
     */
    function testClaimPAndNYieldOfAmountFuzz(
        uint128 rateFuzz,
        uint256 depositAmountFuzz,
        uint256 claimProportionFuzz,
        uint256 transferAmountFuzz
    ) public {
        // bounding variables passed as parameters
        rateFuzz = uint128(bound(rateFuzz, 25, 74)); // we'll be using rateFuzz, rateFuzz - 25, rateFuzz + 25, and their complement to 100 (e.g. 100 - rateFuzz)
        depositAmountFuzz = bound(depositAmountFuzz, 0, 1000e18); // we'll be using depositAmountFuzz and depositAmountFuzz * 2
        claimProportionFuzz = bound(claimProportionFuzz, IBT_UNIT / 4, (3 * IBT_UNIT) / 4);

        DepositData memory data;
        Rate memory rateData;
        YieldData memory yieldData;

        // deposit 1 underlying for user1
        data.amountToDeposit = depositAmountFuzz;
        data.expected = principalToken.convertToPrincipal(data.amountToDeposit);
        data.actual = _testDeposit(data.amountToDeposit, MOCK_ADDR_1); // deposits amountToDeposit with second argument being receiver
        assertTrue(
            data.expected == data.actual,
            "After deposit for user1 balance is not equal to expected value"
        ); // checks if balances are accurate after deposit

        // deposit 1 underlying for user2
        data.actual = _testDeposit(data.amountToDeposit, MOCK_ADDR_2); // deposits amountToDeposit with second argument being receiver
        assertTrue(
            data.expected == data.actual,
            "After deposit for user2 balance is not equal to expected value"
        ); // checks if balances are accurate after deposit

        yieldData.oldYieldUser1 = _updateYield(MOCK_ADDR_1);
        assertEq(yieldData.oldYieldUser1, 0, "Yield of user 1 is wrong");
        yieldData.oldYieldUser2 = _updateYield(MOCK_ADDR_2);
        assertEq(yieldData.oldYieldUser2, 0, "Yield of user 2 is wrong");
        rateData.oldIBTRate = ibt.convertToAssets(IBT_UNIT);

        // decrease rate and increase time
        _increaseRate(-1 * int128(rateFuzz));
        vm.warp(block.timestamp + 100);

        // only negative yield so no yield should be generated
        rateData.newIBTRate = ibt.convertToAssets(IBT_UNIT);

        // computing yield generated by last step
        yieldData.actualYieldUser1 = _updateYield(MOCK_ADDR_1);
        assertEq(yieldData.actualYieldUser1, 0, "Yield of user 1 is wrong");
        assertEq(
            principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_1),
            0,
            "Yield of user 1 is wrong 2"
        );
        yieldData.actualYieldUser2 = _updateYield(MOCK_ADDR_2);
        assertEq(yieldData.actualYieldUser2, 0, "Yield of user 2 is wrong");
        assertEq(
            principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_2),
            0,
            "Yield of user 2 is wrong 2"
        );

        // update variables
        yieldData.oldYieldUser1 = yieldData.actualYieldUser1;
        yieldData.oldYieldUser2 = yieldData.actualYieldUser2;
        rateData.oldIBTRate = rateData.newIBTRate;

        // user 2 claims his yield
        yieldData.underlyingBalanceBefore = underlying.balanceOf(MOCK_ADDR_2);
        yieldData.yieldClaimed = yieldData.actualYieldUser2;
        yieldData.yieldClaimed -= _calcFees(yieldData.yieldClaimed, registry.getYieldFee());
        vm.startPrank(MOCK_ADDR_2);
        principalToken.claimYield(MOCK_ADDR_2, 0);
        vm.stopPrank();
        assertApproxEqAbs(
            underlying.balanceOf(MOCK_ADDR_2),
            yieldData.underlyingBalanceBefore + ibt.convertToAssets(yieldData.yieldClaimed),
            10000,
            "After claiming yield, underlying balance of user2 is not equal to expected value 1"
        );
        yieldData.actualYieldUser2 = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_2);
        assertApproxEqAbs(
            yieldData.actualYieldUser2,
            yieldData.oldYieldUser2 - yieldData.yieldClaimed,
            1000,
            "After claiming yield, stored yield of user2 is not equal to expected value 1"
        );
        yieldData.oldYieldUser2 = yieldData.actualYieldUser2;

        // increase time (no rate change)
        vm.warp(block.timestamp + 100);

        // user 2 claims his yield
        yieldData.underlyingBalanceBefore = underlying.balanceOf(MOCK_ADDR_2);
        yieldData.yieldClaimed = yieldData.actualYieldUser2;
        vm.startPrank(MOCK_ADDR_2);
        principalToken.claimYield(MOCK_ADDR_2, 0);
        vm.stopPrank();
        assertApproxEqAbs(
            underlying.balanceOf(MOCK_ADDR_2),
            yieldData.underlyingBalanceBefore + ibt.convertToAssets(yieldData.yieldClaimed),
            10000,
            "After claiming yield, underlying balance of user2 is not equal to expected value 2"
        );
        yieldData.actualYieldUser2 = _updateYield(MOCK_ADDR_2);
        assertApproxEqAbs(
            yieldData.actualYieldUser2,
            yieldData.oldYieldUser2 - yieldData.yieldClaimed,
            1000,
            "After claiming yield, stored yield of user2 is not equal to expected value 2"
        );
        yieldData.oldYieldUser2 = yieldData.actualYieldUser2;
        assertApproxEqAbs(
            yieldData.oldYieldUser2,
            0,
            1000,
            "After Claiming all yield of amount, yield of user2 should be 0"
        );

        rateData.oldIBTRate = rateData.newIBTRate;

        // deposit 2underlying for user3
        data.amountToDeposit = depositAmountFuzz * 2;
        data.expected = principalToken.convertToPrincipal(data.amountToDeposit);
        data.actual = _testDeposit(data.amountToDeposit, MOCK_ADDR_3); // deposits amountToDeposit with second argument being receiver
        assertApproxEqAbs(
            data.expected,
            data.actual,
            1000,
            "After deposit for user3 balance is not equal to expected value"
        ); // checks if balances are accurate after deposit

        // deposits 2 underlying for user4
        data.actual = _testDeposit(data.amountToDeposit, MOCK_ADDR_4); // deposits amountToDeposit with second argument being receiver
        assertApproxEqAbs(
            data.expected,
            data.actual,
            1000,
            "After deposit for user4 balance is not equal to expected value"
        ); // checks if balances are accurate after deposit

        yieldData.oldYieldUser3 = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_3);
        yieldData.oldYieldUser4 = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_4);
        assertEq(yieldData.oldYieldUser3, 0, "Yield of user3 is wrong");
        assertEq(yieldData.oldYieldUser4, 0, "Yield of user4 is wrong");

        // Several rates variations but ends up with more - yield
        rateData.oldPTRate = principalToken.convertToUnderlying(IBT_UNIT);

        // increase time and rate
        vm.warp(block.timestamp + 100);
        _increaseRate(int128(rateFuzz));
        // here only ibt depegs as no negative yield
        yieldData.oldYieldUser1 = _updateYield(MOCK_ADDR_1);
        rateData.oldIBTRateUser1 = ibt.convertToAssets(IBT_UNIT);
        // increase time and decrease rate
        vm.warp(block.timestamp + 100);
        _increaseRate(-1 * int128(rateFuzz));

        // PT depegs only after interaction with protocol
        _updateYield(MOCK_ADDR_1);

        rateData.newIBTRate = ibt.convertToAssets(IBT_UNIT);
        rateData.newPTRate = principalToken.convertToUnderlying(IBT_UNIT);

        // computes yield for the last step for the 4 users
        yieldData.underlyingLostThroughPTDepegForYTUser1 = _convertToAssetsWithRate(
            yt.actualBalanceOf(MOCK_ADDR_1),
            (rateData.oldPTRate - rateData.newPTRate),
            Math.Rounding.Floor
        );
        yieldData.underlyingLostThroughPTDepegForYTUser2 = _convertToAssetsWithRate(
            yt.actualBalanceOf(MOCK_ADDR_2),
            (rateData.oldPTRate - rateData.newPTRate),
            Math.Rounding.Floor
        );
        yieldData.underlyingLostThroughPTDepegForYTUser3 = _convertToAssetsWithRate(
            yt.actualBalanceOf(MOCK_ADDR_3),
            (rateData.oldPTRate - rateData.newPTRate),
            Math.Rounding.Floor
        );
        yieldData.underlyingLostThroughPTDepegForYTUser4 = _convertToAssetsWithRate(
            yt.actualBalanceOf(MOCK_ADDR_4),
            (rateData.oldPTRate - rateData.newPTRate),
            Math.Rounding.Floor
        );

        yieldData.ibtOfYTUser1 = _convertToSharesWithRate(
            _convertToAssetsWithRate(
                yt.actualBalanceOf(MOCK_ADDR_1),
                rateData.oldPTRate,
                Math.Rounding.Floor
            ),
            rateData.oldIBTRateUser1,
            Math.Rounding.Floor
        );
        yieldData.ibtOfYTUser2 = _convertToSharesWithRate(
            _convertToAssetsWithRate(
                yt.actualBalanceOf(MOCK_ADDR_2),
                rateData.oldPTRate,
                Math.Rounding.Floor
            ),
            rateData.oldIBTRate,
            Math.Rounding.Floor
        );
        yieldData.ibtOfYTUser3 = _convertToSharesWithRate(
            _convertToAssetsWithRate(
                yt.actualBalanceOf(MOCK_ADDR_3),
                rateData.oldPTRate,
                Math.Rounding.Floor
            ),
            rateData.oldIBTRate,
            Math.Rounding.Floor
        );
        yieldData.ibtOfYTUser4 = _convertToSharesWithRate(
            _convertToAssetsWithRate(
                yt.actualBalanceOf(MOCK_ADDR_4),
                rateData.oldPTRate,
                Math.Rounding.Floor
            ),
            rateData.oldIBTRate,
            Math.Rounding.Floor
        );

        yieldData.yieldInUnderlyingUser1 = _convertToAssetsWithRate(
            yieldData.ibtOfYTUser1,
            (rateData.oldIBTRateUser1 - rateData.newIBTRate),
            Math.Rounding.Floor
        );

        yieldData.yieldInUnderlyingUser2 = _convertToAssetsWithRate(
            yieldData.ibtOfYTUser2,
            (rateData.oldIBTRate - rateData.newIBTRate),
            Math.Rounding.Floor
        );

        yieldData.yieldInUnderlyingUser3 = _convertToAssetsWithRate(
            yieldData.ibtOfYTUser3,
            (rateData.oldIBTRate - rateData.newIBTRate),
            Math.Rounding.Floor
        );

        yieldData.yieldInUnderlyingUser4 = _convertToAssetsWithRate(
            yieldData.ibtOfYTUser4,
            (rateData.oldIBTRate - rateData.newIBTRate),
            Math.Rounding.Floor
        );

        yieldData.expectedYieldInIBTUser1 = ibt.convertToShares(
            yieldData.underlyingLostThroughPTDepegForYTUser1 - yieldData.yieldInUnderlyingUser1
        );
        yieldData.actualYieldUser1 = _updateYield(MOCK_ADDR_1);

        yieldData.expectedYieldInIBTUser2 = ibt.convertToShares(
            yieldData.underlyingLostThroughPTDepegForYTUser2 - yieldData.yieldInUnderlyingUser2
        );
        yieldData.actualYieldUser2 = _updateYield(MOCK_ADDR_2);

        yieldData.expectedYieldInIBTUser3 = ibt.convertToShares(
            yieldData.underlyingLostThroughPTDepegForYTUser3 - yieldData.yieldInUnderlyingUser3
        );
        yieldData.actualYieldUser3 = _updateYield(MOCK_ADDR_3);

        yieldData.expectedYieldInIBTUser4 = ibt.convertToShares(
            yieldData.underlyingLostThroughPTDepegForYTUser4 - yieldData.yieldInUnderlyingUser4
        );
        yieldData.actualYieldUser4 = _updateYield(MOCK_ADDR_4);

        assertApproxEqAbs(
            yieldData.actualYieldUser1,
            yieldData.oldYieldUser1 + yieldData.expectedYieldInIBTUser1,
            10000,
            "After rate change, yield for user1 is not equal to expected value 1"
        );
        assertApproxEqAbs(
            yieldData.actualYieldUser2,
            yieldData.oldYieldUser2 + yieldData.expectedYieldInIBTUser2,
            10000,
            "After rate change, yield for user2 is not equal to expected value 1"
        );
        assertApproxEqAbs(
            yieldData.actualYieldUser3,
            yieldData.oldYieldUser3 + yieldData.expectedYieldInIBTUser3,
            100000,
            "After rate change, yield for user3 is not equal to expected value 2"
        );
        assertApproxEqAbs(
            yieldData.actualYieldUser4,
            yieldData.oldYieldUser4 + yieldData.expectedYieldInIBTUser4,
            100000,
            "After rate change, yield for user4 is not equal to expected value 1"
        );

        yieldData.oldYieldUser1 = yieldData.actualYieldUser1;
        yieldData.oldYieldUser2 = yieldData.actualYieldUser2;
        yieldData.oldYieldUser3 = yieldData.actualYieldUser3;
        yieldData.oldYieldUser4 = yieldData.actualYieldUser4;

        // user 2 claims his yield
        yieldData.fee2 = (yieldData.actualYieldUser2 * registry.getYieldFee()) / 1e18;
        yieldData.underlyingBalanceBefore = underlying.balanceOf(MOCK_ADDR_2);
        yieldData.yieldClaimed = yieldData.actualYieldUser2;
        vm.startPrank(MOCK_ADDR_2);
        principalToken.claimYield(MOCK_ADDR_2, 0);
        vm.stopPrank();
        assertApproxEqAbs(
            underlying.balanceOf(MOCK_ADDR_2),
            yieldData.underlyingBalanceBefore +
                ibt.convertToAssets(yieldData.yieldClaimed - yieldData.fee2),
            10000,
            "After claiming yield, underlying balance of user2 is not equal to expected value 3"
        );

        yieldData.actualYieldUser2 = _updateYield(MOCK_ADDR_2);
        assertApproxEqAbs(
            yieldData.actualYieldUser2,
            yieldData.oldYieldUser2 - yieldData.yieldClaimed,
            1000,
            "After claiming yield, stored yield of user2 is not equal to expected value 3"
        );
        yieldData.oldYieldUser2 = yieldData.actualYieldUser2;

        // user 3 claims his yield
        yieldData.fee3 = (yieldData.actualYieldUser3 * registry.getYieldFee()) / 1e18;
        yieldData.underlyingBalanceBefore = underlying.balanceOf(MOCK_ADDR_3);
        yieldData.yieldClaimed = yieldData.actualYieldUser3;
        vm.startPrank(MOCK_ADDR_3);
        principalToken.claimYield(MOCK_ADDR_3, 0);
        vm.stopPrank();
        assertApproxEqAbs(
            underlying.balanceOf(MOCK_ADDR_3),
            yieldData.underlyingBalanceBefore +
                ibt.convertToAssets(yieldData.yieldClaimed - yieldData.fee3),
            10000,
            "After claiming yield, underlying balance of user3 is not equal to expected value"
        );
        yieldData.actualYieldUser3 = _updateYield(MOCK_ADDR_3);
        assertApproxEqAbs(
            yieldData.actualYieldUser3,
            yieldData.oldYieldUser3 - yieldData.yieldClaimed,
            10000,
            "After claiming yield, stored yield of user3 is not equal to expected value"
        );
        yieldData.oldYieldUser3 = yieldData.actualYieldUser3;

        rateData.oldIBTRate = rateData.newIBTRate;

        // Several rates variations but ends up with more + yield
        rateData.oldPTRate = principalToken.convertToUnderlying(IBT_UNIT);

        // increase time and decrease rate
        vm.warp(block.timestamp + 100);
        _increaseRate(-1 * int128(rateFuzz - 25));
        // PT depegs only after interaction with protocol
        yieldData.oldYieldUser3 = _updateYield(MOCK_ADDR_3);
        rateData.oldIBTRateUser3 = ibt.convertToAssets(IBT_UNIT);
        rateData.oldPTRateUser3 = principalToken.convertToUnderlying(IBT_UNIT);
        // increase time and rate
        vm.warp(block.timestamp + 100);
        _increaseRate(100 * int128(rateFuzz - 25));

        rateData.newIBTRate = ibt.convertToAssets(IBT_UNIT);
        rateData.newPTRate = principalToken.convertToUnderlying(IBT_UNIT);

        // computes yield for the last step for the 4 users
        yieldData.underlyingLostThroughPTDepegForYTUser1 = _convertToAssetsWithRate(
            yt.actualBalanceOf(MOCK_ADDR_1),
            (rateData.oldPTRate - rateData.newPTRate),
            Math.Rounding.Floor
        );
        yieldData.underlyingLostThroughPTDepegForYTUser2 = _convertToAssetsWithRate(
            yt.actualBalanceOf(MOCK_ADDR_2),
            (rateData.oldPTRate - rateData.newPTRate),
            Math.Rounding.Floor
        );
        yieldData.underlyingLostThroughPTDepegForYTUser3 = _convertToAssetsWithRate(
            yt.actualBalanceOf(MOCK_ADDR_3),
            (rateData.oldPTRateUser3 - rateData.newPTRate),
            Math.Rounding.Floor
        );
        yieldData.underlyingLostThroughPTDepegForYTUser4 = _convertToAssetsWithRate(
            yt.actualBalanceOf(MOCK_ADDR_4),
            (rateData.oldPTRate - rateData.newPTRate),
            Math.Rounding.Floor
        );

        yieldData.ibtOfYTUser1 = _convertToSharesWithRate(
            _convertToAssetsWithRate(
                yt.actualBalanceOf(MOCK_ADDR_1),
                rateData.oldPTRate,
                Math.Rounding.Floor
            ),
            rateData.oldIBTRate,
            Math.Rounding.Floor
        );
        yieldData.ibtOfYTUser2 = _convertToSharesWithRate(
            _convertToAssetsWithRate(
                yt.actualBalanceOf(MOCK_ADDR_2),
                rateData.oldPTRate,
                Math.Rounding.Floor
            ),
            rateData.oldIBTRate,
            Math.Rounding.Floor
        );
        yieldData.ibtOfYTUser3 = _convertToSharesWithRate(
            _convertToAssetsWithRate(
                yt.actualBalanceOf(MOCK_ADDR_3),
                rateData.oldPTRateUser3,
                Math.Rounding.Floor
            ),
            rateData.oldIBTRateUser3,
            Math.Rounding.Floor
        );
        yieldData.ibtOfYTUser4 = _convertToSharesWithRate(
            _convertToAssetsWithRate(
                yt.actualBalanceOf(MOCK_ADDR_4),
                rateData.oldPTRate,
                Math.Rounding.Floor
            ),
            rateData.oldIBTRate,
            Math.Rounding.Floor
        );

        yieldData.yieldInUnderlyingUser1 = _convertToAssetsWithRate(
            yieldData.ibtOfYTUser1,
            (rateData.newIBTRate - rateData.oldIBTRate),
            Math.Rounding.Floor
        );
        yieldData.yieldInUnderlyingUser2 = _convertToAssetsWithRate(
            yieldData.ibtOfYTUser2,
            (rateData.newIBTRate - rateData.oldIBTRate),
            Math.Rounding.Floor
        );
        yieldData.yieldInUnderlyingUser3 = _convertToAssetsWithRate(
            yieldData.ibtOfYTUser3,
            (rateData.newIBTRate - rateData.oldIBTRateUser3),
            Math.Rounding.Floor
        );
        yieldData.yieldInUnderlyingUser4 = _convertToAssetsWithRate(
            yieldData.ibtOfYTUser4,
            (rateData.newIBTRate - rateData.oldIBTRate),
            Math.Rounding.Floor
        );

        yieldData.expectedYieldInIBTUser1 = ibt.convertToShares(
            yieldData.underlyingLostThroughPTDepegForYTUser1 + yieldData.yieldInUnderlyingUser1
        );
        yieldData.actualYieldUser1 = _updateYield(MOCK_ADDR_1);

        yieldData.expectedYieldInIBTUser2 = ibt.convertToShares(
            yieldData.underlyingLostThroughPTDepegForYTUser2 + yieldData.yieldInUnderlyingUser2
        );
        yieldData.actualYieldUser2 = _updateYield(MOCK_ADDR_2);

        yieldData.expectedYieldInIBTUser3 = ibt.convertToShares(
            yieldData.underlyingLostThroughPTDepegForYTUser3 + yieldData.yieldInUnderlyingUser3
        );
        yieldData.actualYieldUser3 = _updateYield(MOCK_ADDR_3);

        yieldData.expectedYieldInIBTUser4 = ibt.convertToShares(
            yieldData.underlyingLostThroughPTDepegForYTUser4 + yieldData.yieldInUnderlyingUser4
        );
        yieldData.actualYieldUser4 = _updateYield(MOCK_ADDR_4);

        if (depositAmountFuzz < IBT_UNIT / 1000) {
            assertApproxEqAbs(
                yieldData.actualYieldUser1,
                yieldData.expectedYieldInIBTUser1 + yieldData.oldYieldUser1,
                10000,
                "After rate chang, yield for user1 is not equal to expected value 1"
            );
            assertApproxEqAbs(
                yieldData.actualYieldUser2,
                yieldData.expectedYieldInIBTUser2 + yieldData.oldYieldUser2,
                10000,
                "After rate change, yield for user2 is not equal to expected value 2"
            );
            assertApproxEqAbs(
                yieldData.actualYieldUser3,
                yieldData.expectedYieldInIBTUser3 + yieldData.oldYieldUser3,
                10000,
                "After rate change, yield for user3 is not equal to expected value 3"
            );
            assertApproxEqAbs(
                yieldData.actualYieldUser4,
                yieldData.expectedYieldInIBTUser4 + yieldData.oldYieldUser4,
                10000,
                "After rate change, yield for user4 is not equal to expected value 2"
            );
        } else {
            assertApproxEqRel(
                yieldData.actualYieldUser1,
                yieldData.expectedYieldInIBTUser1 + yieldData.oldYieldUser1,
                1e15,
                "After rate chang, yield for user1 is not equal to expected value 1"
            );
            assertApproxEqRel(
                yieldData.actualYieldUser2,
                yieldData.expectedYieldInIBTUser2 + yieldData.oldYieldUser2,
                1e15,
                "After rate change, yield for user2 is not equal to expected value 2"
            );
            assertApproxEqRel(
                yieldData.actualYieldUser3,
                yieldData.expectedYieldInIBTUser3 + yieldData.oldYieldUser3,
                1e15,
                "After rate change, yield for user3 is not equal to expected value 3"
            );
            assertApproxEqRel(
                yieldData.actualYieldUser4,
                yieldData.expectedYieldInIBTUser4 + yieldData.oldYieldUser4,
                1e15,
                "After rate change, yield for user4 is not equal to expected value 2"
            );
        }

        yieldData.oldYieldUser1 = yieldData.actualYieldUser1;
        yieldData.oldYieldUser2 = yieldData.actualYieldUser2;
        yieldData.oldYieldUser3 = yieldData.actualYieldUser3;
        yieldData.oldYieldUser4 = yieldData.actualYieldUser4;

        // user 2 claims his yield
        yieldData.fee2 = (yieldData.actualYieldUser2 * registry.getYieldFee()) / 1e18;
        yieldData.underlyingBalanceBefore = underlying.balanceOf(MOCK_ADDR_2);
        yieldData.yieldClaimed = yieldData.actualYieldUser2;
        vm.startPrank(MOCK_ADDR_2);
        principalToken.claimYield(MOCK_ADDR_2, 0);
        vm.stopPrank();
        assertApproxEqAbs(
            underlying.balanceOf(MOCK_ADDR_2),
            yieldData.underlyingBalanceBefore +
                ibt.convertToAssets(yieldData.yieldClaimed - yieldData.fee2),
            10000,
            "After claiming yield, underlying balance of user2 is not equal to expected value 4"
        );

        yieldData.actualYieldUser2 = _updateYield(MOCK_ADDR_2);
        assertApproxEqAbs(
            yieldData.actualYieldUser2,
            yieldData.oldYieldUser2 - yieldData.yieldClaimed,
            1000,
            "After claiming yield, stored yield of user2 is not equal to expected value 4"
        );
        yieldData.oldYieldUser2 = yieldData.actualYieldUser2;

        rateData.oldIBTRate = rateData.newIBTRate;

        // increase time and rate
        vm.warp(block.timestamp + 100);
        _increaseRate(int128(100 - rateFuzz));

        rateData.newIBTRate = ibt.convertToAssets(IBT_UNIT);

        // computes the yield of the last step for the 4 users
        yieldData.ibtOfYTUser1 = _convertToSharesWithRate(
            principalToken.convertToUnderlying(yt.actualBalanceOf(MOCK_ADDR_1)),
            rateData.oldIBTRate,
            Math.Rounding.Floor
        );
        yieldData.ibtOfYTUser2 = _convertToSharesWithRate(
            principalToken.convertToUnderlying(yt.actualBalanceOf(MOCK_ADDR_2)),
            rateData.oldIBTRate,
            Math.Rounding.Floor
        );
        yieldData.ibtOfYTUser3 = _convertToSharesWithRate(
            principalToken.convertToUnderlying(yt.actualBalanceOf(MOCK_ADDR_3)),
            rateData.oldIBTRate,
            Math.Rounding.Floor
        );
        yieldData.ibtOfYTUser4 = _convertToSharesWithRate(
            principalToken.convertToUnderlying(yt.actualBalanceOf(MOCK_ADDR_4)),
            rateData.oldIBTRate,
            Math.Rounding.Floor
        );

        yieldData.yieldInUnderlyingUser1 = _convertToAssetsWithRate(
            yieldData.ibtOfYTUser1,
            (rateData.newIBTRate - rateData.oldIBTRate),
            Math.Rounding.Floor
        );
        yieldData.yieldInUnderlyingUser2 = _convertToAssetsWithRate(
            yieldData.ibtOfYTUser2,
            (rateData.newIBTRate - rateData.oldIBTRate),
            Math.Rounding.Floor
        );
        yieldData.yieldInUnderlyingUser3 = _convertToAssetsWithRate(
            yieldData.ibtOfYTUser3,
            (rateData.newIBTRate - rateData.oldIBTRate),
            Math.Rounding.Floor
        );
        yieldData.yieldInUnderlyingUser4 = _convertToAssetsWithRate(
            yieldData.ibtOfYTUser4,
            (rateData.newIBTRate - rateData.oldIBTRate),
            Math.Rounding.Floor
        );

        yieldData.expectedYieldInIBTUser1 = ibt.convertToShares(yieldData.yieldInUnderlyingUser1);
        yieldData.actualYieldUser1 = _updateYield(MOCK_ADDR_1);

        yieldData.expectedYieldInIBTUser2 = ibt.convertToShares(yieldData.yieldInUnderlyingUser2);
        yieldData.actualYieldUser2 = _updateYield(MOCK_ADDR_2);

        yieldData.expectedYieldInIBTUser3 = ibt.convertToShares(yieldData.yieldInUnderlyingUser3);
        yieldData.actualYieldUser3 = _updateYield(MOCK_ADDR_3);

        yieldData.expectedYieldInIBTUser4 = ibt.convertToShares(yieldData.yieldInUnderlyingUser4);
        yieldData.actualYieldUser4 = _updateYield(MOCK_ADDR_4);

        assertApproxEqAbs(
            yieldData.actualYieldUser1,
            yieldData.oldYieldUser1 + yieldData.expectedYieldInIBTUser1,
            1000,
            "After rate change, yield for user1 is not equal to expected value 2"
        );
        assertApproxEqAbs(
            yieldData.actualYieldUser2,
            yieldData.oldYieldUser2 + yieldData.expectedYieldInIBTUser2,
            1000,
            "After rate change, yield for user2 is not equal to expected value 3"
        );
        assertApproxEqAbs(
            yieldData.actualYieldUser3,
            yieldData.oldYieldUser3 + yieldData.expectedYieldInIBTUser3,
            1000,
            "After rate change, yield for user3 is not equal to expected value 4"
        );
        assertApproxEqAbs(
            yieldData.actualYieldUser4,
            yieldData.oldYieldUser4 + yieldData.expectedYieldInIBTUser4,
            1000,
            "After rate change, yield for user4 is not equal to expected value 3"
        );

        yieldData.oldYieldUser1 = yieldData.actualYieldUser1;
        yieldData.oldYieldUser2 = yieldData.actualYieldUser2;
        yieldData.oldYieldUser3 = yieldData.actualYieldUser3;
        yieldData.oldYieldUser4 = yieldData.actualYieldUser4;

        // user 4 transfers 1/5th of his YTs to user3
        yieldData.ytBalanceBeforeUser3 = yt.actualBalanceOf(MOCK_ADDR_3);
        yieldData.ytBalanceBeforeUser4 = yt.actualBalanceOf(MOCK_ADDR_4);
        // The following shouldn't be exact balance of user 4 otherwise the next claim will claim everything
        // whereas the tests are expecting to claim only part of the balance
        transferAmountFuzz = bound(
            transferAmountFuzz,
            0,
            (98 * yieldData.ytBalanceBeforeUser4) / 100
        );
        vm.prank(MOCK_ADDR_4);
        yt.transfer(MOCK_ADDR_3, transferAmountFuzz);
        yieldData.ytBalanceAfterUser3 = yt.actualBalanceOf(MOCK_ADDR_3);
        yieldData.ytBalanceAfterUser4 = yt.actualBalanceOf(MOCK_ADDR_4);
        assertEq(
            yieldData.ytBalanceAfterUser3,
            yieldData.ytBalanceBeforeUser3 + transferAmountFuzz
        );
        assertEq(
            yieldData.ytBalanceAfterUser4,
            yieldData.ytBalanceBeforeUser4 - transferAmountFuzz
        );

        // update yield with user3 and 4
        yieldData.actualYieldUser3 = _updateYield(MOCK_ADDR_3);
        yieldData.actualYieldUser4 = _updateYield(MOCK_ADDR_4);
        assertEq(
            yieldData.actualYieldUser3,
            yieldData.oldYieldUser3,
            "After transfer, yield of user 3 is unchanged"
        );
        assertEq(
            yieldData.actualYieldUser4,
            yieldData.oldYieldUser4,
            "After transfer, yield of user 4 is unchanged"
        );

        // user 3 claims his yield (and no additional due to transfer)
        yieldData.fee3 = (yieldData.actualYieldUser3 * registry.getYieldFee()) / 1e18;
        yieldData.underlyingBalanceBefore = underlying.balanceOf(MOCK_ADDR_3);
        yieldData.yieldClaimed = yieldData.actualYieldUser3;
        vm.startPrank(MOCK_ADDR_3);
        principalToken.claimYield(MOCK_ADDR_3, 0);
        vm.stopPrank();
        assertApproxEqAbs(
            underlying.balanceOf(MOCK_ADDR_3),
            yieldData.underlyingBalanceBefore +
                ibt.convertToAssets(yieldData.yieldClaimed - yieldData.fee3),
            10000,
            "After claiming yield, underlying balance of user3 is not equal to expected value"
        );
        yieldData.actualYieldUser3 = _updateYield(MOCK_ADDR_3);
        assertApproxEqAbs(
            yieldData.actualYieldUser3,
            yieldData.oldYieldUser3 - yieldData.yieldClaimed,
            10000,
            "After claiming yield, stored yield of user3 is not equal to expected value"
        );
        yieldData.oldYieldUser3 = yieldData.actualYieldUser3;
        assertApproxEqAbs(
            yieldData.oldYieldUser3,
            0,
            1000,
            "After Claiming all yield of amount, stored yield of user3 should be 0"
        );

        rateData.oldIBTRate = rateData.newIBTRate;

        // increase time and rate
        vm.warp(block.timestamp + 100);
        _increaseRate(int128(100 - (rateFuzz - 25)));

        rateData.newIBTRate = ibt.convertToAssets(IBT_UNIT);

        // computes yield of last step for the 4 users
        yieldData.ibtOfYTUser1 = _convertToSharesWithRate(
            principalToken.convertToUnderlying(yt.actualBalanceOf(MOCK_ADDR_1)),
            rateData.oldIBTRate,
            Math.Rounding.Floor
        );
        yieldData.ibtOfYTUser2 = _convertToSharesWithRate(
            principalToken.convertToUnderlying(yt.actualBalanceOf(MOCK_ADDR_2)),
            rateData.oldIBTRate,
            Math.Rounding.Floor
        );
        yieldData.ibtOfYTUser3 = _convertToSharesWithRate(
            principalToken.convertToUnderlying(yt.actualBalanceOf(MOCK_ADDR_3)),
            rateData.oldIBTRate,
            Math.Rounding.Floor
        );
        yieldData.ibtOfYTUser4 = _convertToSharesWithRate(
            principalToken.convertToUnderlying(yt.actualBalanceOf(MOCK_ADDR_4)),
            rateData.oldIBTRate,
            Math.Rounding.Floor
        );

        yieldData.yieldInUnderlyingUser1 = _convertToAssetsWithRate(
            yieldData.ibtOfYTUser1,
            (rateData.newIBTRate - rateData.oldIBTRate),
            Math.Rounding.Floor
        );
        yieldData.yieldInUnderlyingUser2 = _convertToAssetsWithRate(
            yieldData.ibtOfYTUser2,
            (rateData.newIBTRate - rateData.oldIBTRate),
            Math.Rounding.Floor
        );
        yieldData.yieldInUnderlyingUser3 = _convertToAssetsWithRate(
            yieldData.ibtOfYTUser3,
            (rateData.newIBTRate - rateData.oldIBTRate),
            Math.Rounding.Floor
        );
        yieldData.yieldInUnderlyingUser4 = _convertToAssetsWithRate(
            yieldData.ibtOfYTUser4,
            (rateData.newIBTRate - rateData.oldIBTRate),
            Math.Rounding.Floor
        );

        yieldData.expectedYieldInIBTUser1 = ibt.convertToShares(yieldData.yieldInUnderlyingUser1);
        yieldData.actualYieldUser1 = _updateYield(MOCK_ADDR_1);

        yieldData.expectedYieldInIBTUser2 = ibt.convertToShares(yieldData.yieldInUnderlyingUser2);
        yieldData.actualYieldUser2 = _updateYield(MOCK_ADDR_2);

        yieldData.expectedYieldInIBTUser3 = ibt.convertToShares(yieldData.yieldInUnderlyingUser3);
        yieldData.actualYieldUser3 = _updateYield(MOCK_ADDR_3);

        yieldData.expectedYieldInIBTUser4 = ibt.convertToShares(yieldData.yieldInUnderlyingUser4);
        yieldData.actualYieldUser4 = _updateYield(MOCK_ADDR_4);

        assertApproxEqAbs(
            yieldData.actualYieldUser1,
            yieldData.expectedYieldInIBTUser1 + yieldData.oldYieldUser1,
            1000,
            "After rate change, yield for user1 is not equal to expected value 3"
        );
        assertApproxEqAbs(
            yieldData.actualYieldUser2,
            yieldData.expectedYieldInIBTUser2 + yieldData.oldYieldUser2,
            1000,
            "After rate change, yield for user2 is not equal to expected value 4"
        );
        assertApproxEqAbs(
            yieldData.actualYieldUser3,
            yieldData.expectedYieldInIBTUser3 + yieldData.oldYieldUser3,
            1000,
            "After rate change, yield for user3 is not equal to expected value 5"
        );
        assertApproxEqAbs(
            yieldData.actualYieldUser4,
            yieldData.expectedYieldInIBTUser4 + yieldData.oldYieldUser4,
            1000,
            "After rate change, yield for user4 is not equal to expected value 4"
        );

        yieldData.oldYieldUser1 = yieldData.actualYieldUser1;
        yieldData.oldYieldUser2 = yieldData.actualYieldUser2;
        yieldData.oldYieldUser3 = yieldData.actualYieldUser3;
        yieldData.oldYieldUser4 = yieldData.actualYieldUser4;

        // user 2 claims his yield
        yieldData.fee2 = (yieldData.actualYieldUser2 * registry.getYieldFee()) / 1e18;
        yieldData.underlyingBalanceBefore = underlying.balanceOf(MOCK_ADDR_2);
        yieldData.yieldClaimed = yieldData.actualYieldUser2;
        vm.startPrank(MOCK_ADDR_2);
        principalToken.claimYield(MOCK_ADDR_2, 0);
        vm.stopPrank();
        assertApproxEqAbs(
            underlying.balanceOf(MOCK_ADDR_2),
            yieldData.underlyingBalanceBefore + ibt.convertToAssets(yieldData.yieldClaimed),
            10000,
            "After claiming yield, underlying balance of user2 is not equal to expected value 5"
        );
        yieldData.actualYieldUser2 = _updateYield(MOCK_ADDR_2);
        assertApproxEqAbs(
            yieldData.actualYieldUser2,
            yieldData.oldYieldUser2 - yieldData.yieldClaimed,
            1000,
            "After claiming yield, stored yield of user2 is not equal to expected value 5"
        );
        yieldData.oldYieldUser2 = yieldData.actualYieldUser2;

        // user 4 claims his yield
        yieldData.fee4 = (yieldData.actualYieldUser4 * registry.getYieldFee()) / 1e18;
        yieldData.underlyingBalanceBefore = underlying.balanceOf(MOCK_ADDR_4);
        yieldData.yieldClaimed = yieldData.actualYieldUser4;
        vm.startPrank(MOCK_ADDR_4);
        principalToken.claimYield(MOCK_ADDR_4, 0);
        vm.stopPrank();
        assertApproxEqAbs(
            underlying.balanceOf(MOCK_ADDR_4),
            yieldData.underlyingBalanceBefore +
                ibt.convertToAssets(yieldData.yieldClaimed - yieldData.fee4),
            10000,
            "After claiming yield, underlying balance of user4 is not equal to expected value"
        );

        yieldData.actualYieldUser4 = _updateYield(MOCK_ADDR_4);
        assertApproxEqAbs(
            yieldData.actualYieldUser4,
            yieldData.oldYieldUser4 - yieldData.yieldClaimed,
            10000,
            "After claiming yield, stored yield of user4 is not equal to expected value"
        );
        yieldData.oldYieldUser4 = yieldData.actualYieldUser4;

        // claim 3/5th with user 3
        yieldData.fee3 = (yieldData.actualYieldUser3 * registry.getYieldFee()) / 1e18;
        yieldData.underlyingBalanceBefore = underlying.balanceOf(MOCK_ADDR_3);
        yieldData.yieldClaimed = yieldData.actualYieldUser3;
        vm.startPrank(MOCK_ADDR_3);
        principalToken.claimYield(MOCK_ADDR_3, 0);
        vm.stopPrank();
        assertApproxEqAbs(
            underlying.balanceOf(MOCK_ADDR_3),
            yieldData.underlyingBalanceBefore +
                ibt.convertToAssets(yieldData.yieldClaimed - yieldData.fee3),
            10000,
            "After claiming yield, underlying balance of user3 is not equal to expected value"
        );
        yieldData.actualYieldUser3 = _updateYield(MOCK_ADDR_3);
        assertApproxEqAbs(
            yieldData.actualYieldUser3,
            yieldData.oldYieldUser3 - yieldData.yieldClaimed,
            10000,
            "After claiming yield, stored yield of user3 is not equal to expected value"
        );
        yieldData.oldYieldUser3 = yieldData.actualYieldUser3;

        // user 4 transfers every YieldToken to user 3
        yieldData.ytBalanceBeforeUser3 = yt.actualBalanceOf(MOCK_ADDR_3);
        yieldData.ytBalanceBeforeUser4 = yt.actualBalanceOf(MOCK_ADDR_4);
        vm.prank(MOCK_ADDR_4);
        yt.transfer(MOCK_ADDR_3, yieldData.ytBalanceBeforeUser4);
        yieldData.ytBalanceAfterUser3 = yt.actualBalanceOf(MOCK_ADDR_3);
        yieldData.ytBalanceAfterUser4 = yt.actualBalanceOf(MOCK_ADDR_4);
        assertEq(
            yieldData.ytBalanceAfterUser3,
            yieldData.ytBalanceBeforeUser3 + yieldData.ytBalanceBeforeUser4
        );
        assertEq(yieldData.ytBalanceAfterUser4, 0);
        yieldData.actualYieldUser3 = _updateYield(MOCK_ADDR_3);
        yieldData.actualYieldUser4 = _updateYield(MOCK_ADDR_4);
        assertEq(
            yieldData.actualYieldUser3,
            yieldData.oldYieldUser3,
            "After transfer, yield of user 3 is changed"
        );
        assertEq(
            yieldData.actualYieldUser4,
            yieldData.oldYieldUser4,
            "After transfer, yield of user 4 is changed"
        );

        // user 4 claims his yield
        yieldData.fee4 = (yieldData.actualYieldUser4 * registry.getYieldFee()) / 1e18;
        yieldData.underlyingBalanceBefore = underlying.balanceOf(MOCK_ADDR_4);
        yieldData.yieldClaimed = yieldData.actualYieldUser4;
        vm.prank(MOCK_ADDR_4);
        principalToken.claimYield(MOCK_ADDR_4, 0);
        assertApproxEqAbs(
            underlying.balanceOf(MOCK_ADDR_4),
            yieldData.underlyingBalanceBefore +
                ibt.convertToAssets(yieldData.yieldClaimed - yieldData.fee4),
            10000,
            "After claiming yield, underlying balance of user4 is not equal to expected value"
        );
        yieldData.actualYieldUser4 = _updateYield(MOCK_ADDR_4);
        assertApproxEqAbs(
            yieldData.actualYieldUser4,
            yieldData.oldYieldUser4 - yieldData.yieldClaimed,
            10000,
            "After claiming yield, stored yield of user4 is not equal to expected value"
        );
        yieldData.oldYieldUser4 = yieldData.actualYieldUser4;
        assertApproxEqAbs(
            yieldData.oldYieldUser4,
            0,
            1000,
            "After Claiming all yield of amount, stored yield of user4 should be 0"
        );

        rateData.oldIBTRate = rateData.newIBTRate;

        // increase time and rate
        vm.warp(block.timestamp + 100);
        _increaseRate(int128(rateFuzz + 25));

        rateData.newIBTRate = ibt.convertToAssets(IBT_UNIT);

        // computes the yield of the last step for the 4 users
        yieldData.ibtOfYTUser1 = _convertToSharesWithRate(
            principalToken.convertToUnderlying(yt.actualBalanceOf(MOCK_ADDR_1)),
            rateData.oldIBTRate,
            Math.Rounding.Floor
        );
        yieldData.ibtOfYTUser2 = _convertToSharesWithRate(
            principalToken.convertToUnderlying(yt.actualBalanceOf(MOCK_ADDR_2)),
            rateData.oldIBTRate,
            Math.Rounding.Floor
        );
        yieldData.ibtOfYTUser3 = _convertToSharesWithRate(
            principalToken.convertToUnderlying(yt.actualBalanceOf(MOCK_ADDR_3)),
            rateData.oldIBTRate,
            Math.Rounding.Floor
        );
        yieldData.ibtOfYTUser4 = _convertToSharesWithRate(
            principalToken.convertToUnderlying(yt.actualBalanceOf(MOCK_ADDR_4)),
            rateData.oldIBTRate,
            Math.Rounding.Floor
        );
        assertEq(
            yieldData.ibtOfYTUser4,
            0,
            "After transfering every YieldToken user 4 should have 0 ibtOfYT"
        );

        yieldData.yieldInUnderlyingUser1 =
            (yieldData.ibtOfYTUser1 * (rateData.newIBTRate - rateData.oldIBTRate)) /
            IBT_UNIT;
        yieldData.yieldInUnderlyingUser2 =
            (yieldData.ibtOfYTUser2 * (rateData.newIBTRate - rateData.oldIBTRate)) /
            IBT_UNIT;
        yieldData.yieldInUnderlyingUser3 =
            (yieldData.ibtOfYTUser3 * (rateData.newIBTRate - rateData.oldIBTRate)) /
            IBT_UNIT;
        yieldData.yieldInUnderlyingUser4 =
            (yieldData.ibtOfYTUser4 * (rateData.newIBTRate - rateData.oldIBTRate)) /
            IBT_UNIT;
        assertEq(
            yieldData.yieldInUnderlyingUser4,
            0,
            "After claiming all his yield and having 0 YieldToken, user 4 should have 0 yield"
        );

        yieldData.expectedYieldInIBTUser1 = ibt.convertToShares(yieldData.yieldInUnderlyingUser1);
        yieldData.actualYieldUser1 = _updateYield(MOCK_ADDR_1);

        yieldData.expectedYieldInIBTUser2 = ibt.convertToShares(yieldData.yieldInUnderlyingUser2);
        yieldData.actualYieldUser2 = _updateYield(MOCK_ADDR_2);

        yieldData.expectedYieldInIBTUser3 = ibt.convertToShares(yieldData.yieldInUnderlyingUser3);
        yieldData.actualYieldUser3 = _updateYield(MOCK_ADDR_3);

        yieldData.expectedYieldInIBTUser4 = ibt.convertToShares(yieldData.yieldInUnderlyingUser4);
        yieldData.actualYieldUser4 = _updateYield(MOCK_ADDR_4);
        assertEq(
            yieldData.actualYieldUser4,
            0,
            "After claiming all his yield and having 0 YieldToken, user 4 should have 0 yield"
        );
        assertEq(
            yieldData.expectedYieldInIBTUser4,
            0,
            "After claiming all his yield and having 0 YieldToken, user 4 should have 0 yield"
        );

        assertApproxEqAbs(
            yieldData.actualYieldUser1,
            yieldData.oldYieldUser1 + yieldData.expectedYieldInIBTUser1,
            1000,
            "After rate change, yield for user1 is not equal to expected value 4"
        );
        assertApproxEqAbs(
            yieldData.actualYieldUser2,
            yieldData.expectedYieldInIBTUser2 + yieldData.oldYieldUser2,
            10000,
            "After rate change, yield for user2 is not equal to expected value 5"
        );
        assertApproxEqAbs(
            yieldData.actualYieldUser3,
            yieldData.expectedYieldInIBTUser3 + yieldData.oldYieldUser3,
            1000,
            "After rate change, yield for user3 is not equal to expected value 6"
        );

        // claim everything with all users
        yieldData.fee1 = (yieldData.actualYieldUser1 * registry.getYieldFee()) / 1e18;
        yieldData.fee2 = (yieldData.actualYieldUser2 * registry.getYieldFee()) / 1e18;
        yieldData.fee3 = (yieldData.actualYieldUser3 * registry.getYieldFee()) / 1e18;
        yieldData.fee4 = (yieldData.actualYieldUser4 * registry.getYieldFee()) / 1e18;
        assertEq(
            yieldData.fee4,
            0,
            "After claiming all his yield and having 0 YieldToken, user 4 should have 0 yield (so 0 fees)"
        );

        yieldData.underlyingBalanceBefore = underlying.balanceOf(MOCK_ADDR_1);
        vm.prank(MOCK_ADDR_1);
        principalToken.claimYield(MOCK_ADDR_1, 0);
        assertApproxEqAbs(
            underlying.balanceOf(MOCK_ADDR_1),
            yieldData.underlyingBalanceBefore +
                ibt.convertToAssets(yieldData.actualYieldUser1 - yieldData.fee1),
            1000,
            "After Claiming yield, balance of user1 is not equal to expected value"
        );
        yieldData.actualYieldUser1 = _updateYield(MOCK_ADDR_1);
        assertApproxEqAbs(
            yieldData.actualYieldUser1,
            0,
            1000,
            "After claiming yield, stored yield of user1 is not equal to expected value"
        );

        yieldData.underlyingBalanceBefore = underlying.balanceOf(MOCK_ADDR_2);
        vm.startPrank(MOCK_ADDR_2);
        principalToken.claimYield(MOCK_ADDR_2, 0);
        vm.stopPrank();
        assertApproxEqAbs(
            underlying.balanceOf(MOCK_ADDR_2),
            yieldData.underlyingBalanceBefore +
                ibt.convertToAssets(yieldData.actualYieldUser2 - yieldData.fee2),
            1000,
            "After Claiming yield, balance of user2 is not equal to expected value"
        );
        yieldData.actualYieldUser2 = _updateYield(MOCK_ADDR_2);
        assertApproxEqAbs(
            yieldData.actualYieldUser2,
            0,
            1000,
            "After claiming yield, stored yield of user2 is not equal to expected value 6"
        );

        yieldData.underlyingBalanceBefore = underlying.balanceOf(MOCK_ADDR_3);
        vm.startPrank(MOCK_ADDR_3);
        principalToken.claimYield(MOCK_ADDR_3, 0);
        vm.stopPrank();
        assertApproxEqAbs(
            underlying.balanceOf(MOCK_ADDR_3),
            yieldData.underlyingBalanceBefore +
                ibt.convertToAssets(yieldData.actualYieldUser3 - yieldData.fee3),
            1000,
            "After Claiming yield, balance of user3 is not equal to expected value"
        );
        yieldData.actualYieldUser3 = _updateYield(MOCK_ADDR_3);
        assertApproxEqAbs(
            yieldData.actualYieldUser3,
            0,
            10000,
            "After claiming yield, stored yield of user3 is not equal to expected value"
        );

        yieldData.underlyingBalanceBefore = underlying.balanceOf(MOCK_ADDR_4);
        vm.startPrank(MOCK_ADDR_4);
        principalToken.claimYield(MOCK_ADDR_4, 0);
        vm.stopPrank();
        assertApproxEqAbs(
            underlying.balanceOf(MOCK_ADDR_4),
            yieldData.underlyingBalanceBefore +
                ibt.convertToAssets(yieldData.actualYieldUser4 - yieldData.fee4),
            1000,
            "After Claiming yield, balance of user4 is not equal to expected value"
        );
        yieldData.actualYieldUser4 = _updateYield(MOCK_ADDR_4);
        assertApproxEqAbs(
            yieldData.actualYieldUser4,
            0,
            10000,
            "After claiming yield, stored yield of user4 is not equal to expected value"
        );
        assertApproxEqAbs(
            underlying.balanceOf(MOCK_ADDR_4),
            yieldData.underlyingBalanceBefore,
            1000,
            "After Claiming yield, balance of user4 is not equal to expected value"
        );
    }

    /**
     * @dev Fuzz tests redeem max + claimYield in different positive and negative yield context before and after expiry.
     */
    function testRedeemMaxAndClaimYieldFuzz(
        uint128 rate,
        uint256 assetsToDeposit,
        uint256 transferProportion
    ) public {
        assetsToDeposit = bound(assetsToDeposit, 0, 1000e18);
        rate = uint128(bound(rate, 0, 199));
        transferProportion = bound(transferProportion, 0, IBT_UNIT);

        DepositData memory data;
        UserDataBeforeAfter memory userData;

        // deposit assetsToDeposit underlying for user1
        data.amountToDeposit = assetsToDeposit;
        data.expected = principalToken.previewDeposit(data.amountToDeposit);
        data.actual = _testDeposit(data.amountToDeposit, MOCK_ADDR_1);
        assertEq(
            data.expected,
            data.actual,
            "After deposit for user1 balance is not equal to expected value"
        );

        // deposit assetsToDeposit underlying for user2
        data.actual = _testDeposit(data.amountToDeposit, MOCK_ADDR_2);
        assertEq(
            data.expected,
            data.actual,
            "After deposit for user2 balance is not equal to expected value"
        );

        // increase (or decrease) rate and time
        _increaseRate(100 - int128(rate));
        vm.warp(block.timestamp + 100);

        // deposit 2 * assetsToDeposit underlying for user3
        data.amountToDeposit = assetsToDeposit * 2;
        data.actual = _testDeposit(data.amountToDeposit, MOCK_ADDR_3);
        data.expected = principalToken.previewDeposit(data.amountToDeposit);
        assertEq(
            data.expected,
            data.actual,
            "After deposit for user3 balance is not equal to expected value"
        );

        // deposit 2x underlying for user4
        data.actual = _testDeposit(data.amountToDeposit, MOCK_ADDR_4);
        data.expected = principalToken.convertToPrincipal(data.amountToDeposit);
        assertApproxEqAbs(
            data.expected,
            data.actual,
            10,
            "After deposit for user4 balance is not equal to expected value"
        );

        // increase rate and time
        _increaseRate(200 - int128(rate));
        vm.warp(block.timestamp + 100);

        // transfer some YieldToken to user5
        vm.startPrank(MOCK_ADDR_3);
        yt.transfer(MOCK_ADDR_5, (yt.actualBalanceOf(MOCK_ADDR_3) * transferProportion) / IBT_UNIT);
        vm.stopPrank();

        // increase (or decrease) rate and time
        _increaseRate(100 - int128(rate));
        _increaseTimeToExpiry();

        vm.startPrank(MOCK_ADDR_1);

        userData.userPTBalanceBefore = principalToken.balanceOf(MOCK_ADDR_1);
        userData.userUnderlyingBalanceBefore = underlying.balanceOf(MOCK_ADDR_1);

        assertEq(
            yt.balanceOf(MOCK_ADDR_1),
            0,
            "YieldToken.balanceOf should always return 0 after expiry"
        );

        // Redeem for user 1
        userData.underlyingRedeemed1 = principalToken.redeem(
            userData.userPTBalanceBefore,
            MOCK_ADDR_1,
            MOCK_ADDR_1
        );
        userData.userPTBalanceAfter = principalToken.balanceOf(MOCK_ADDR_1);
        assertEq(userData.userPTBalanceAfter, 0, "User 1 should have 0 PT left after redeem");

        // Claim yield for user 1
        userData.claimedYield1 = principalToken.claimYield(MOCK_ADDR_1, 0);

        userData.userUnderlyingBalanceAfter = underlying.balanceOf(MOCK_ADDR_1);
        userData.totalUnderlyingEarned1 = userData.underlyingRedeemed1 + userData.claimedYield1;
        assertEq(
            userData.userUnderlyingBalanceAfter,
            userData.userUnderlyingBalanceBefore + userData.totalUnderlyingEarned1,
            "Underlying balance after redeem and claimYield for user 1 is wrong"
        );

        vm.stopPrank();

        vm.startPrank(MOCK_ADDR_2);

        userData.userPTBalanceBefore = principalToken.balanceOf(MOCK_ADDR_2);
        userData.userUnderlyingBalanceBefore = underlying.balanceOf(MOCK_ADDR_2);

        // Redeem for user 2
        userData.underlyingRedeemed2 = principalToken.redeem(
            userData.userPTBalanceBefore,
            MOCK_ADDR_2,
            MOCK_ADDR_2
        );
        userData.userPTBalanceAfter = principalToken.balanceOf(MOCK_ADDR_2);
        assertEq(userData.userPTBalanceAfter, 0, "User 2 should have 0 PT left after redeem");

        // Claim yield for user 2
        userData.claimedYield2 = principalToken.claimYield(MOCK_ADDR_2, 0);

        userData.userUnderlyingBalanceAfter = underlying.balanceOf(MOCK_ADDR_2);
        userData.totalUnderlyingEarned2 = userData.underlyingRedeemed2 + userData.claimedYield2;
        assertEq(
            userData.userUnderlyingBalanceAfter,
            userData.userUnderlyingBalanceBefore + userData.totalUnderlyingEarned2,
            "Underlying balance after redeem and claimYield for user 2 is wrong"
        );

        vm.stopPrank();

        assertEq(
            userData.totalUnderlyingEarned1,
            userData.totalUnderlyingEarned2,
            "Underlying earned by user1 and user2 shouldn't differ"
        );

        vm.startPrank(MOCK_ADDR_3);

        userData.userPTBalanceBefore = principalToken.balanceOf(MOCK_ADDR_3);
        userData.userUnderlyingBalanceBefore = underlying.balanceOf(MOCK_ADDR_3);

        // transfer half PT to user 4
        principalToken.transfer(MOCK_ADDR_4, userData.userPTBalanceBefore / 2);
        userData.userPTBalanceAfter = principalToken.balanceOf(MOCK_ADDR_3);
        assertEq(
            userData.userPTBalanceAfter,
            userData.userPTBalanceBefore - userData.userPTBalanceBefore / 2,
            "PT balance of user 3 after transfer is wrong"
        );

        // user3 redeems to user4
        userData.underlyingRedeemed1 = principalToken.redeem(
            userData.userPTBalanceAfter,
            MOCK_ADDR_4,
            MOCK_ADDR_3
        );
        userData.userPTBalanceAfter = principalToken.balanceOf(MOCK_ADDR_3);
        assertEq(userData.userPTBalanceAfter, 0, "PT balance of user 3 after redeem is wrong");

        // Claim yield for user 3
        userData.claimedYield1 = principalToken.claimYield(MOCK_ADDR_3, 0);
        userData.userUnderlyingBalanceAfter = underlying.balanceOf(MOCK_ADDR_3);
        assertEq(
            userData.userUnderlyingBalanceAfter,
            userData.claimedYield1,
            "Underlying balance after redeem and claimYield for user 3 is wrong"
        );

        vm.stopPrank();

        vm.startPrank(MOCK_ADDR_4);

        userData.userPTBalanceBefore = principalToken.balanceOf(MOCK_ADDR_4);
        userData.userUnderlyingBalanceBefore = underlying.balanceOf(MOCK_ADDR_4);

        // redeem for user 4
        userData.underlyingRedeemed2 = principalToken.redeem(
            userData.userPTBalanceBefore,
            MOCK_ADDR_4,
            MOCK_ADDR_4
        );
        userData.userPTBalanceAfter = principalToken.balanceOf(MOCK_ADDR_4);
        assertEq(userData.userPTBalanceAfter, 0, "PT balance of user 4 after redeem is wrong");

        // Claim yield for user 4
        userData.claimedYield2 = principalToken.claimYield(MOCK_ADDR_4, 0);
        userData.userUnderlyingBalanceAfter = underlying.balanceOf(MOCK_ADDR_4);
        assertEq(
            userData.userUnderlyingBalanceAfter,
            userData.underlyingRedeemed1 + userData.underlyingRedeemed2 + userData.claimedYield2,
            "Underlying balance after redeem and claimYield for user 4 is wrong"
        );

        vm.stopPrank();

        assertApproxEqAbs(
            userData.underlyingRedeemed1,
            userData.underlyingRedeemed2 / 3,
            10,
            "Underlying earned by redeem of user3 and user4 should differ due to transfer of PT"
        );
        if (assetsToDeposit > 10000 && transferProportion > IBT_UNIT / 100 && rate < 100) {
            // the yield generated at the last generation was positive
            assertLt(
                userData.claimedYield1,
                userData.claimedYield2,
                "User 3 should have generated yield less than user 4 because of YT transfer before PT expiration"
            );
        } else if (userData.claimedYield1 > 100 && rate >= 100) {
            // the yield generated at the last generation was null or negative
            assertEq(
                userData.claimedYield1,
                userData.claimedYield2,
                "User 3 should have generated approx as much yield as user 4, as yield generated was null or negative since YT transfer"
            );
        }

        // redeem / claimYield again doesn't change anything
        vm.startPrank(MOCK_ADDR_1);

        userData.userPTBalanceBefore = principalToken.balanceOf(MOCK_ADDR_1);
        userData.underlyingRedeemed1 = principalToken.redeem(
            userData.userPTBalanceBefore,
            MOCK_ADDR_1,
            MOCK_ADDR_1
        );
        userData.claimedYield1 = principalToken.claimYield(MOCK_ADDR_1, 0);
        assertEq(userData.underlyingRedeemed1, 0, "Second redeem of user1 should return 0");
        assertEq(userData.claimedYield1, 0, "Second claimYield of user1 should return 0");
    }

    function testGetCurrentYieldInIBTOfUserFuzz(uint256 amountToDeposit, uint128 rate) public {
        amountToDeposit = bound(amountToDeposit, 1e4, 1000e18);
        uint256 expected = principalToken.previewDeposit(amountToDeposit);
        uint256 actual = _testDeposit(amountToDeposit, MOCK_ADDR_1);
        assertEq(expected, actual, "Deposit return value is not equal to expected value");
        // increase or decrease rate
        rate = uint128(bound(rate, 0, 300));
        _increaseRate(200 - int128(rate));
        if (rate == 300) {
            vm.expectRevert();
        }
        uint256 yieldInIBTOfUser = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_1);
        if (rate >= 200) {
            // null or negative yield
            assertEq(yieldInIBTOfUser, 0, "Deposit return value is not equal to expected value");
        } else {
            // positive yield
            uint256 yieldInUnderlyingOfUser = ibt.convertToAssets(yieldInIBTOfUser);
            uint256 expectedYieldInUnderlyingOfUser = (amountToDeposit * (200 - rate)) / 100;
            expectedYieldInUnderlyingOfUser -= _calcFees(
                expectedYieldInUnderlyingOfUser,
                registry.getYieldFee()
            );
            assertApproxEqAbs(
                yieldInUnderlyingOfUser,
                expectedYieldInUnderlyingOfUser,
                10,
                "Getter for yield of user is wrong"
            );
            // claiming yield
            vm.startPrank(MOCK_ADDR_1);
            uint256 claimedYieldInUnderlying = principalToken.claimYield(MOCK_ADDR_1, 0);
            uint256 claimedYieldInIBT = ibt.convertToShares(claimedYieldInUnderlying);
            assertApproxEqAbs(
                yieldInUnderlyingOfUser,
                claimedYieldInUnderlying,
                10,
                "Claimed yield is wrong 1"
            );
            assertApproxEqAbs(yieldInIBTOfUser, claimedYieldInIBT, 10, "Claimed yield is wrong 2");
        }
    }

    function _increaseTimeToExpiry() internal {
        uint256 time = block.timestamp + principalToken.maturity();
        vm.warp(time);
    }

    /**
     * @dev Internal function for  deposit and balance checks for ibt, underlying, pt and yt
     * @param amount Amount of underlying to deposit
     * @param receiver Receiver of the shares
     */
    function _testDeposit(uint256 amount, address receiver) internal returns (uint256 shares) {
        underlying.approve(address(principalToken), amount);
        uint256 expectedIBT = ibt.previewDeposit(amount);
        uint256 totalAssetsBefore = principalToken.totalAssets();
        uint256 underlyingBalanceBefore = underlying.balanceOf(address(this));
        uint256 ibtBalanceOfPTContractBefore = ibt.balanceOf(address(principalToken));
        uint256 ptBalanceBefore = principalToken.balanceOf(receiver);
        uint256 ytBalanceBefore = yt.actualBalanceOf(receiver);
        uint256 expectedShares = principalToken.previewDeposit(amount);
        if (expectedShares == 0) {
            vm.expectRevert();
        }
        shares = principalToken.deposit(amount, receiver);

        assertEq(expectedShares, shares, "PreviewDeposit and deposit do not return the same value");
        assertApproxEqAbs(
            principalToken.totalAssets(),
            totalAssetsBefore + amount,
            10,
            "After deposit, totalAssets is wrong"
        );
        assertEq(
            underlyingBalanceBefore,
            underlying.balanceOf(address(this)) + amount,
            "After deposit, underlying balance is wrong"
        );
        assertEq(
            ibt.balanceOf(address(principalToken)),
            ibtBalanceOfPTContractBefore + expectedIBT,
            "After deposit, IBT balance of principalToken contract is wrong"
        );
        assertApproxEqAbs(
            principalToken.balanceOf(receiver),
            ptBalanceBefore + shares,
            1000,
            "After deposit, PT balance of receiver is wrong"
        );
        assertApproxEqAbs(
            yt.actualBalanceOf(receiver),
            ytBalanceBefore + shares,
            1000,
            "After deposit, YT balance of receiver is wrong"
        );
    }

    /**
     * @dev Internal function for changing ibt rate with a determined rate as passed
     */
    function _increaseRate(int128 rate) internal {
        int128 currentRate = int128(uint128(ibt.convertToAssets(10 ** ibt.decimals())));
        int128 newRate = (currentRate * (rate + 100)) / 100;
        ibt.setPricePerFullShare(uint256(uint128(newRate)));
    }

    function _convertToSharesWithRate(
        uint256 assets,
        uint256 rate,
        Math.Rounding rounding
    ) internal view returns (uint256 shares) {
        shares = assets.mulDiv(IBT_UNIT, rate, rounding);
    }

    function _convertToAssetsWithRate(
        uint256 shares,
        uint256 rate,
        Math.Rounding rounding
    ) internal view returns (uint256 assets) {
        assets = shares.mulDiv(rate, IBT_UNIT, rounding);
    }

    function _updateYield(address user) internal returns (uint256) {
        return principalToken.updateYield(user);
    }

    function _calcFees(uint256 amount, uint256 feeRate) internal pure returns (uint256) {
        return amount.mulDiv(feeRate, 1e18);
    }
}
