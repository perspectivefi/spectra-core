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
import "src/mocks/MockIBT2.sol";
import "src/libraries/Roles.sol";
import "src/libraries/RayMath.sol";
import "openzeppelin-contracts/proxy/beacon/UpgradeableBeacon.sol";

contract ContractPrincipalToken3 is Test {
    using Math for uint256;
    using RayMath for uint256;
    /* STRUCTS */
    struct DepositWithdrawRedeemData {
        // before
        uint256 underlyingBalanceSenderBefore;
        uint256 ibtBalanceSenderBefore;
        uint256 ptBalanceSenderBefore;
        uint256 ytBalanceSenderBefore;
        uint256 underlyingBalanceReceiverBefore;
        uint256 ibtBalanceReceiverBefore;
        uint256 ptBalanceReceiverBefore;
        uint256 ytBalanceReceiverBefore;
        uint256 underlyingBalancePTReceiverBefore;
        uint256 ptBalancePTReceiverBefore;
        uint256 ytBalancePTReceiverBefore;
        uint256 underlyingBalanceYTReceiverBefore;
        uint256 ptBalanceYTReceiverBefore;
        uint256 ytBalanceYTReceiverBefore;
        uint256 ibtBalancePTContractBefore;
        // after
        uint256 underlyingBalanceSenderAfter;
        uint256 ibtBalanceSenderAfter;
        uint256 ptBalanceSenderAfter;
        uint256 ytBalanceSenderAfter;
        uint256 underlyingBalanceReceiverAfter;
        uint256 ibtBalanceReceiverAfter;
        uint256 ptBalanceReceiverAfter;
        uint256 ytBalanceReceiverAfter;
        uint256 underlyingBalancePTReceiverAfter;
        uint256 ptBalancePTReceiverAfter;
        uint256 ytBalancePTReceiverAfter;
        uint256 underlyingBalanceYTReceiverAfter;
        uint256 ptBalanceYTReceiverAfter;
        uint256 ytBalanceYTReceiverAfter;
        uint256 ibtBalancePTContractAfter;
        // global
        uint256 maxRedeem;
        uint256 receivedShares;
        uint256 usedAssets;
        uint256 receivedAssets;
        uint256 usedShares;
        uint256 expectedShares1;
        uint256 expectedShares2;
        uint256 expectedAssets1;
        uint256 expectedAssets2;
        uint256 assetsInIBT;
    }

    struct TestUsersData {
        // t0
        uint256 underlyingBalanceTestUser1_0;
        uint256 underlyingBalanceTestUser2_0;
        uint256 underlyingBalanceTestUser3_0;
        uint256 underlyingBalanceTestUser4_0;
        uint256 ibtBalanceTestUser1_0;
        uint256 ibtBalanceTestUser2_0;
        uint256 ibtBalanceTestUser3_0;
        uint256 ibtBalanceTestUser4_0;
        uint256 ibtBalancePTContract_0;
        uint256 ptBalanceTestUser1_0;
        uint256 ptBalanceTestUser2_0;
        uint256 ptBalanceTestUser3_0;
        uint256 ptBalanceTestUser4_0;
        uint256 ytBalanceTestUser1_0;
        uint256 ytBalanceTestUser2_0;
        uint256 ytBalanceTestUser3_0;
        uint256 ytBalanceTestUser4_0;
        uint256 previewDeposit0;
        uint256 ibtAmount0;
        uint256 underlyingAmount0;
        uint256 amountInAsset0;
        uint256 depositResult0;
        // t1
        uint256 underlyingBalanceTestUser1_1;
        uint256 underlyingBalanceTestUser2_1;
        uint256 underlyingBalanceTestUser3_1;
        uint256 underlyingBalanceTestUser4_1;
        uint256 ibtBalanceTestUser1_1;
        uint256 ibtBalanceTestUser2_1;
        uint256 ibtBalanceTestUser3_1;
        uint256 ibtBalanceTestUser4_1;
        uint256 ibtBalancePTContract_1;
        uint256 ptBalanceTestUser1_1;
        uint256 ptBalanceTestUser2_1;
        uint256 ptBalanceTestUser3_1;
        uint256 ptBalanceTestUser4_1;
        uint256 ytBalanceTestUser1_1;
        uint256 ytBalanceTestUser2_1;
        uint256 ytBalanceTestUser3_1;
        uint256 ytBalanceTestUser4_1;
        uint256 previewDeposit1;
        uint256 ibtAmount1;
        uint256 underlyingAmount1;
        uint256 amountInAsset1;
        uint256 depositResult1;
        uint256 redeemedAssets1;
        // t2
        uint256 underlyingBalanceTestUser1_2;
        uint256 underlyingBalanceTestUser2_2;
        uint256 underlyingBalanceTestUser3_2;
        uint256 underlyingBalanceTestUser4_2;
        uint256 ibtBalanceTestUser1_2;
        uint256 ibtBalanceTestUser2_2;
        uint256 ibtBalanceTestUser3_2;
        uint256 ibtBalanceTestUser4_2;
        uint256 ibtBalancePTContract_2;
        uint256 ptBalanceTestUser1_2;
        uint256 ptBalanceTestUser2_2;
        uint256 ptBalanceTestUser3_2;
        uint256 ptBalanceTestUser4_2;
        uint256 ytBalanceTestUser1_2;
        uint256 ytBalanceTestUser2_2;
        uint256 ytBalanceTestUser3_2;
        uint256 ytBalanceTestUser4_2;
        uint256 previewDeposit2_1;
        uint256 previewDeposit2_2;
        uint256 previewDeposit2_3;
        uint256 ibtAmount2_1;
        uint256 ibtAmount2_2;
        uint256 ibtAmount2_3;
        uint256 underlyingAmount2;
        uint256 amountInAsset2;
        uint256 depositResult2_1;
        uint256 depositResult2_2;
        uint256 depositResult2_3;
        uint256 redeemedAssets2;
        // t3
        uint256 amountInAsset3_1;
        uint256 amountInAsset3_2;
        uint256 amountInAsset3_3;
        uint256 redeemedAssets3;
        // other
        uint256 assetsToWithdraw1;
        uint256 ibtToWithdraw1;
        uint256 maxWithdrawableAssets1;
        uint256 maxWithdrawableIbts1;
        uint256 withdrawnShares1;
        uint256 withdrawnUnderlying1;
        uint256 withdrawnIBT1;
        uint256 assetsToWithdraw2;
        uint256 ibtToWithdraw2;
        uint256 maxWithdrawableAssets2;
        uint256 maxWithdrawableIbts2;
        uint256 withdrawnShares2;
        uint256 withdrawnUnderlying2;
        uint256 withdrawnIBT2;
        uint256 assetsToWithdraw3;
        uint256 ibtToWithdraw3;
        uint256 maxWithdrawableAssets3;
        uint256 maxWithdrawableIbts3;
        uint256 withdrawnShares3;
        uint256 withdrawnUnderlying3;
        uint256 withdrawnIBT3;
    }

    /* VARIABLES */
    PrincipalToken public principalToken;
    Factory public factory;
    AccessManager public accessManager;
    PrincipalTokenScript principalTokenScript;
    MockERC20 public underlying;
    MockIBT2 public ibt;
    UpgradeableBeacon public principalTokenBeacon;
    UpgradeableBeacon public ytBeacon;
    YieldToken public yt;
    Registry public registry;
    address adminAddr;
    address public curveFactoryAddress = address(0xfac);
    address feeCollector = 0x0000000000000000000000000000000000000FEE;
    uint256 DEFAULT_DECIMALS = 18;
    address TEST_USER_1 = 0x0000000000000000000000000000000000000001;
    address TEST_USER_2 = 0x0000000000000000000000000000000000000002;
    address TEST_USER_3 = 0x0000000000000000000000000000000000000003;
    address TEST_USER_4 = 0x0000000000000000000000000000000000000004;
    uint256 public TOKENIZATION_FEE = 1e15;
    uint256 public YIELD_FEE = 0;
    uint256 public PT_FLASH_LOAN_FEE = 0;
    uint256 public EXPIRY = block.timestamp + 100000;
    uint256 public IBT_UNIT;
    uint256 public ASSET_UNIT;
    address public scriptAdmin;
    uint256 totalFeesTill;
    uint256 public ptRate;

    /* EVENTS */
    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );
    event YieldUpdated(address indexed user, uint256 indexed yieldInIBT);
    event Redeem(address indexed from, address indexed to, uint256 shares);
    event PTDeployed(address indexed principalToken, address indexed poolCreator);

    /* FUNCTIONS */

    /**
     * @dev This is the function to deploy principalToken and other mock contracts
     * for testing. It is called before each test.
     */
    function setUp() public {
        adminAddr = address(this); // to reduce number of lines and repeated vm pranks
        // default account for deploying scripts contracts. refer to line 35 of
        // https://github.com/foundry-rs/foundry/blob/master/evm/src/lib.rs for more details
        scriptAdmin = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;
        // Access Manager
        AccessManagerDeploymentScript accessManagerScript = new AccessManagerDeploymentScript();
        accessManager = AccessManager(accessManagerScript.deployForTest(scriptAdmin));
        vm.prank(scriptAdmin);
        accessManager.grantRole(Roles.PAUSER_ROLE, scriptAdmin, 0);
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
        ibt = new MockIBT2();
        ibt.initialize("MOCK IBT", "MIBT", IERC20Metadata(address(underlying))); // deploys ibt which principalToken holds
        IBT_UNIT = 10 ** ibt.decimals();
        ASSET_UNIT = 10 ** IERC20Metadata(address(underlying)).decimals();

        // bootstrap IBT vault
        underlying.mint(address(this), 1);
        underlying.approve(address(ibt), 1);
        ibt.deposit(1, address(7));

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
        principalTokenScript = new PrincipalTokenScript();
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

    /* UNIT TESTS */

    function testPTDeploymentWithZeroAddress1() public {
        bytes memory revertData = abi.encodeWithSignature("AddressError()");
        vm.expectRevert(revertData);
        // following principalToken deployment should revert
        principalTokenScript.deployForTest(address(factory), address(0), EXPIRY);
    }

    function testChangeRateFuzz(uint256 amount, uint16 rate) public {
        amount = bound(amount, 1, 1000000e18);
        rate = uint16(bound(rate, 0, 10000));
        bool isIncrease = true;

        uint256 ibtRate1 = ibt.getPricePerFullShare();
        uint256 ptRate1 = principalToken.convertToUnderlying(IBT_UNIT);
        assertEq(ibtRate1, ptRate1, "Initial rates are wrong");
        assertEq(ibtRate1, 1e18, "Initial rates are wrong");

        // depositing in IBT vault and PT vault shouldn't change anything
        underlying.mint(adminAddr, 2 * amount);
        underlying.approve(address(ibt), amount);
        underlying.approve(address(principalToken), amount);
        ibt.deposit(amount, adminAddr);
        principalToken.deposit(amount, adminAddr);
        ibtRate1 = ibt.getPricePerFullShare();
        ptRate1 = principalToken.getPTRate().fromRay(DEFAULT_DECIMALS);
        assertEq(ibtRate1, ptRate1, "Rates after deposits are wrong");
        assertEq(ibtRate1, 1e18, "Rates after deposits are wrong");
        // 1 wei is deposited in the setUp to be able to instantiate the PT
        // The PT doesn't allow to initilize a PT on an empty IBT
        assertEq(
            underlying.balanceOf(address(ibt)) - 1,
            amount * 2,
            "Underlying balance of IBT contract after deposit is wrong"
        );
        assertEq(ibt.balanceOf(adminAddr), amount, "IBT balance of admin after deposit is wrong");
        assertEq(
            principalToken.balanceOf(adminAddr),
            amount,
            "PT balance of admin after deposit is wrong"
        );
        assertEq(
            yt.balanceOf(adminAddr),
            amount,
            "YieldToken balance of admin after deposit is wrong"
        );

        // increasing rates
        uint256 underlyingBalanceBefore = underlying.balanceOf(address(ibt));
        uint256 ibtRate2 = _changeRate(rate, isIncrease);
        // updating yield so that the rates are updated in the contract
        principalToken.updateYield(adminAddr);
        uint256 underlyingBalanceAfter = underlying.balanceOf(address(ibt));
        uint256 ptRate2 = principalToken.getPTRate().fromRay(DEFAULT_DECIMALS);
        // assertions
        assertApproxEqAbs(
            underlyingBalanceAfter,
            underlyingBalanceBefore + (underlyingBalanceBefore * rate) / 100,
            0,
            "Balances after increase are wrong"
        );
        if (underlyingBalanceAfter > underlyingBalanceBefore) {
            assertGt(ibtRate2, ibtRate1, "Rates after increase are wrong");
        } else {
            assertEq(ibtRate2, ibtRate1, "Rates after increase are wrong");
        }
        // positive yield should not have impacted PT rate
        assertEq(ptRate1, ptRate2, "PT rate after IBT rate increase is wrong");

        // decreasing rates
        isIncrease = false;
        underlyingBalanceBefore = underlying.balanceOf(address(ibt));
        uint256 ibtRate3 = _changeRate(rate, isIncrease);
        // updating yield so that the rates are updated in the contract
        underlyingBalanceAfter = underlying.balanceOf(address(ibt));
        // assertions
        if (rate > 99) {
            assertEq(underlyingBalanceAfter, 0, "Balances after decrease are wrong");
            vm.expectRevert();
            principalToken.updateYield(adminAddr);
        } else {
            assertApproxEqAbs(
                underlyingBalanceBefore,
                underlyingBalanceAfter + (underlyingBalanceBefore * rate) / 100,
                0,
                "Balances after decrease are wrong"
            );
        }
        if (underlyingBalanceAfter < underlyingBalanceBefore) {
            assertGt(ibtRate2, ibtRate3, "Rates after decrease are wrong");
        } else {
            assertEq(ibtRate2, ibtRate3, "Rates after decrease are wrong");
        }
        uint256 ptRate3;
        if (rate > 99) {
            assertEq(ibtRate3, 0, "IBT rate after IBT rate decrease is wrong");
            assertEq(
                underlyingBalanceAfter,
                0,
                "Underlying Balance after IBT rate decrease is wrong"
            );
        } else {
            principalToken.updateYield(adminAddr);
            ptRate3 = principalToken.getPTRate().fromRay(DEFAULT_DECIMALS);
            assertApproxEqAbs(
                (ptRate3 * ASSET_UNIT) / ptRate2,
                (ibtRate3 * ASSET_UNIT) / ibtRate2,
                1, // offset of 1 due to arithmetical imprecisions
                "PT rate after IBT rate decrease is wrong"
            );
        }

        // further decreasing rates
        underlyingBalanceBefore = underlying.balanceOf(address(ibt));
        uint256 ibtRate4 = _changeRate(rate, isIncrease);
        // updating yield so that the rates are updated in the contract
        underlyingBalanceAfter = underlying.balanceOf(address(ibt));
        // assertions
        if (rate > 99) {
            assertEq(underlyingBalanceAfter, 0, "Balances after decrease are wrong");
        } else {
            assertApproxEqAbs(
                underlyingBalanceBefore,
                underlyingBalanceAfter + (underlyingBalanceBefore * rate) / 100,
                0,
                "Balances after decrease are wrong"
            );
        }
        if (underlyingBalanceAfter < underlyingBalanceBefore) {
            assertGt(ibtRate3, ibtRate4, "Rates after 2nd decrease are wrong");
        } else {
            assertEq(ibtRate3, ibtRate4, "Rates after 2nd decrease are wrong");
        }
        if (rate > 99) {
            assertEq(ibtRate4, 0, "IBT rate after IBT rate 2nd decrease is wrong");
            assertEq(
                underlyingBalanceAfter,
                0,
                "Underlying Balance after IBT rate decrease is wrong"
            );
            vm.expectRevert();
            principalToken.updateYield(adminAddr);
        } else {
            principalToken.updateYield(adminAddr);
            uint256 ptRate4 = principalToken.convertToUnderlying(IBT_UNIT);
            assertApproxEqAbs(
                (ptRate4 * ASSET_UNIT) / ptRate3,
                (ibtRate4 * ASSET_UNIT) / ibtRate3,
                100,
                "PT rate after IBT rate 2nd decrease is wrong"
            );
        }
    }

    /**
     * @dev Tests deposit methods of the PT contract
     */
    function testSimpleDepositFuzz(uint256 amount) public {
        amount = bound(amount, 0, 10000000e18);
        TestUsersData memory usersData;

        // data before
        usersData.underlyingBalanceTestUser1_0 = underlying.balanceOf(TEST_USER_1);
        usersData.underlyingBalanceTestUser2_0 = underlying.balanceOf(TEST_USER_2);
        usersData.underlyingBalanceTestUser3_0 = underlying.balanceOf(TEST_USER_3);
        usersData.ibtBalanceTestUser1_0 = ibt.balanceOf(TEST_USER_1);
        usersData.ibtBalanceTestUser2_0 = ibt.balanceOf(TEST_USER_2);
        usersData.ibtBalanceTestUser3_0 = ibt.balanceOf(TEST_USER_3);
        usersData.ibtBalancePTContract_0 = ibt.balanceOf(address(principalToken));
        usersData.ptBalanceTestUser1_0 = principalToken.balanceOf(TEST_USER_1);
        usersData.ptBalanceTestUser2_0 = principalToken.balanceOf(TEST_USER_2);
        usersData.ptBalanceTestUser3_0 = principalToken.balanceOf(TEST_USER_3);
        usersData.ytBalanceTestUser1_0 = yt.balanceOf(TEST_USER_1);
        usersData.ytBalanceTestUser2_0 = yt.balanceOf(TEST_USER_2);
        usersData.ytBalanceTestUser3_0 = yt.balanceOf(TEST_USER_3);

        // start pranking user 1
        vm.startPrank(TEST_USER_1);

        /* DEPOSITING WITH UNDERLYING ASSETS */
        underlying.mint(TEST_USER_1, amount * 9);
        underlying.approve(address(principalToken), amount * 9);
        // basic deposit
        _testDeposit1(amount, TEST_USER_1, TEST_USER_1);
        _testDeposit1(amount, TEST_USER_1, TEST_USER_2);
        // deposit with pt/yt receivers
        _testDeposit2(amount, TEST_USER_1, TEST_USER_1, TEST_USER_1, false);
        _testDeposit2(amount, TEST_USER_1, TEST_USER_1, TEST_USER_2, false);
        _testDeposit2(amount, TEST_USER_1, TEST_USER_2, TEST_USER_1, false);
        _testDeposit2(amount, TEST_USER_1, TEST_USER_2, TEST_USER_2, false);
        _testDeposit2(amount, TEST_USER_1, TEST_USER_2, TEST_USER_3, false);
        // deposit with pt/yt receivers and min shares (minShares is calculated in the fct itself)
        _testDeposit2(amount, TEST_USER_1, TEST_USER_1, TEST_USER_1, true);
        _testDeposit2(amount, TEST_USER_1, TEST_USER_2, TEST_USER_3, true);
        // data inter
        usersData.underlyingBalanceTestUser1_1 = underlying.balanceOf(TEST_USER_1);
        usersData.underlyingBalanceTestUser2_1 = underlying.balanceOf(TEST_USER_2);
        usersData.underlyingBalanceTestUser3_1 = underlying.balanceOf(TEST_USER_3);
        usersData.ibtBalanceTestUser1_1 = ibt.balanceOf(TEST_USER_1);
        usersData.ibtBalanceTestUser2_1 = ibt.balanceOf(TEST_USER_2);
        usersData.ibtBalanceTestUser3_1 = ibt.balanceOf(TEST_USER_3);
        usersData.ibtBalancePTContract_1 = ibt.balanceOf(address(principalToken));
        usersData.ptBalanceTestUser1_1 = principalToken.balanceOf(TEST_USER_1);
        usersData.ptBalanceTestUser2_1 = principalToken.balanceOf(TEST_USER_2);
        usersData.ptBalanceTestUser3_1 = principalToken.balanceOf(TEST_USER_3);
        usersData.ytBalanceTestUser1_1 = yt.balanceOf(TEST_USER_1);
        usersData.ytBalanceTestUser2_1 = yt.balanceOf(TEST_USER_2);
        usersData.ytBalanceTestUser3_1 = yt.balanceOf(TEST_USER_3);
        // assertions based on the deposits sender / pt&yt receivers
        assertEq(
            usersData.underlyingBalanceTestUser1_1,
            usersData.underlyingBalanceTestUser1_0,
            "Underlying Balance of Test User 1 after deposit is wrong"
        );
        assertEq(
            usersData.underlyingBalanceTestUser2_1,
            usersData.underlyingBalanceTestUser2_0,
            "Underlying Balance of Test User 2 after deposit is wrong"
        );
        assertEq(
            usersData.underlyingBalanceTestUser3_1,
            usersData.underlyingBalanceTestUser3_0,
            "Underlying Balance of Test User 3 after deposit is wrong"
        );
        assertEq(
            usersData.ibtBalanceTestUser1_1,
            usersData.ibtBalanceTestUser1_0,
            "IBT Balance of Test User 1 after deposit is wrong"
        );
        assertEq(
            usersData.ibtBalanceTestUser2_1,
            usersData.ibtBalanceTestUser2_0,
            "IBT Balance of Test User 2 after deposit is wrong"
        );
        assertEq(
            usersData.ibtBalanceTestUser3_1,
            usersData.ibtBalanceTestUser3_0,
            "IBT Balance of Test User 3 after deposit is wrong"
        );
        assertEq(
            usersData.ibtBalancePTContract_1,
            usersData.ibtBalancePTContract_0 + amount * 9,
            "IBT Balance of PT Contract after deposit is wrong"
        );
        assertEq(
            usersData.ptBalanceTestUser1_1,
            usersData.ptBalanceTestUser1_0 + amount * 4,
            "PT Balance of Test User 1 after deposit is wrong"
        );
        assertEq(
            usersData.ptBalanceTestUser2_1,
            usersData.ptBalanceTestUser2_0 + amount * 5,
            "PT Balance of Test User 2 after deposit is wrong"
        );
        assertEq(
            usersData.ptBalanceTestUser3_1,
            usersData.ptBalanceTestUser3_0,
            "PT Balance of Test User 3 after deposit is wrong"
        );
        assertEq(
            usersData.ytBalanceTestUser1_1,
            usersData.ytBalanceTestUser1_0 + amount * 4,
            "YieldToken Balance of Test User 1 after deposit is wrong"
        );
        assertEq(
            usersData.ytBalanceTestUser2_1,
            usersData.ytBalanceTestUser2_0 + amount * 3,
            "YieldToken Balance of Test User 2 after deposit is wrong"
        );
        assertEq(
            usersData.ytBalanceTestUser3_1,
            usersData.ytBalanceTestUser3_0 + amount * 2,
            "YieldToken Balance of Test User 3 after deposit is wrong"
        );

        /* DEPOSITING WITH IBTs */
        underlying.mint(TEST_USER_1, amount * 9);
        underlying.approve(address(ibt), amount * 9);
        ibt.deposit(amount * 9, TEST_USER_1);
        ibt.approve(address(principalToken), amount * 9);
        // basic deposit
        _testDeposit3(amount, TEST_USER_1, TEST_USER_1);
        _testDeposit3(amount, TEST_USER_1, TEST_USER_2);
        // deposit with pt/yt receivers
        _testDeposit4(amount, TEST_USER_1, TEST_USER_1, TEST_USER_1, false);
        _testDeposit4(amount, TEST_USER_1, TEST_USER_1, TEST_USER_2, false);
        _testDeposit4(amount, TEST_USER_1, TEST_USER_2, TEST_USER_1, false);
        _testDeposit4(amount, TEST_USER_1, TEST_USER_2, TEST_USER_2, false);
        _testDeposit4(amount, TEST_USER_1, TEST_USER_2, TEST_USER_3, false);
        // deposit with pt/yt receivers and min shares (minShares is calculated in the fct itself)
        _testDeposit4(amount, TEST_USER_1, TEST_USER_1, TEST_USER_1, true);
        _testDeposit4(amount, TEST_USER_1, TEST_USER_3, TEST_USER_2, true);
        // data final
        usersData.underlyingBalanceTestUser1_2 = underlying.balanceOf(TEST_USER_1);
        usersData.underlyingBalanceTestUser2_2 = underlying.balanceOf(TEST_USER_2);
        usersData.underlyingBalanceTestUser3_2 = underlying.balanceOf(TEST_USER_3);
        usersData.ibtBalanceTestUser1_2 = ibt.balanceOf(TEST_USER_1);
        usersData.ibtBalanceTestUser2_2 = ibt.balanceOf(TEST_USER_2);
        usersData.ibtBalanceTestUser3_2 = ibt.balanceOf(TEST_USER_3);
        usersData.ibtBalancePTContract_2 = ibt.balanceOf(address(principalToken));
        usersData.ptBalanceTestUser1_2 = principalToken.balanceOf(TEST_USER_1);
        usersData.ptBalanceTestUser2_2 = principalToken.balanceOf(TEST_USER_2);
        usersData.ptBalanceTestUser3_2 = principalToken.balanceOf(TEST_USER_3);
        usersData.ytBalanceTestUser1_2 = yt.balanceOf(TEST_USER_1);
        usersData.ytBalanceTestUser2_2 = yt.balanceOf(TEST_USER_2);
        usersData.ytBalanceTestUser3_2 = yt.balanceOf(TEST_USER_3);
        // assertions based on the deposits sender / pt&yt receivers
        assertEq(
            usersData.underlyingBalanceTestUser1_2,
            usersData.underlyingBalanceTestUser1_1,
            "Underlying Balance 2 of Test User 1 after deposit is wrong"
        );
        assertEq(
            usersData.underlyingBalanceTestUser2_2,
            usersData.underlyingBalanceTestUser2_1,
            "Underlying Balance 2 of Test User 2 after deposit is wrong"
        );
        assertEq(
            usersData.underlyingBalanceTestUser3_2,
            usersData.underlyingBalanceTestUser3_1,
            "Underlying Balance 2 of Test User 3 after deposit is wrong"
        );
        assertEq(
            usersData.ibtBalanceTestUser1_2,
            usersData.ibtBalanceTestUser1_1,
            "IBT Balance 2 of Test User 1 after deposit is wrong"
        );
        assertEq(
            usersData.ibtBalanceTestUser2_2,
            usersData.ibtBalanceTestUser2_1,
            "IBT Balance 2 of Test User 2 after deposit is wrong"
        );
        assertEq(
            usersData.ibtBalanceTestUser3_2,
            usersData.ibtBalanceTestUser3_1,
            "IBT Balance 2 of Test User 3 after deposit is wrong"
        );
        assertEq(
            usersData.ibtBalancePTContract_2,
            usersData.ibtBalancePTContract_1 + amount * 9,
            "IBT Balance 2 of PT Contract after deposit is wrong"
        );
        assertEq(
            usersData.ptBalanceTestUser1_2,
            usersData.ptBalanceTestUser1_1 + amount * 4,
            "PT Balance 2 of Test User 1 after deposit is wrong"
        );
        assertEq(
            usersData.ptBalanceTestUser2_2,
            usersData.ptBalanceTestUser2_1 + amount * 4,
            "PT Balance 2 of Test User 2 after deposit is wrong"
        );
        assertEq(
            usersData.ptBalanceTestUser3_2,
            usersData.ptBalanceTestUser3_1 + amount,
            "PT Balance 2 of Test User 3 after deposit is wrong"
        );
        assertEq(
            usersData.ytBalanceTestUser1_2,
            usersData.ytBalanceTestUser1_1 + amount * 4,
            "YieldToken Balance 2 of Test User 1 after deposit is wrong"
        );
        assertEq(
            usersData.ytBalanceTestUser2_2,
            usersData.ytBalanceTestUser2_1 + amount * 4,
            "YieldToken Balance 2 of Test User 2 after deposit is wrong"
        );
        assertEq(
            usersData.ytBalanceTestUser3_2,
            usersData.ytBalanceTestUser3_1 + amount,
            "YieldToken Balance 2 of Test User 3 after deposit is wrong"
        );

        // stop pranking user 1
        vm.stopPrank();
    }

    /**
     * @dev Tests redeem methods of the PT contract
     */
    function testSimpleRedeemFuzz(uint256 amount) public {
        amount = bound(amount, 0, 10000000e18);
        TestUsersData memory usersData;

        // data before
        usersData.underlyingBalanceTestUser1_0 = underlying.balanceOf(TEST_USER_1);
        usersData.underlyingBalanceTestUser2_0 = underlying.balanceOf(TEST_USER_2);
        usersData.underlyingBalanceTestUser3_0 = underlying.balanceOf(TEST_USER_3);
        usersData.ibtBalanceTestUser1_0 = ibt.balanceOf(TEST_USER_1);
        usersData.ibtBalanceTestUser2_0 = ibt.balanceOf(TEST_USER_2);
        usersData.ibtBalanceTestUser3_0 = ibt.balanceOf(TEST_USER_3);
        usersData.ibtBalancePTContract_0 = ibt.balanceOf(address(principalToken));
        usersData.ptBalanceTestUser1_0 = principalToken.balanceOf(TEST_USER_1);
        usersData.ptBalanceTestUser2_0 = principalToken.balanceOf(TEST_USER_2);
        usersData.ptBalanceTestUser3_0 = principalToken.balanceOf(TEST_USER_3);
        usersData.ytBalanceTestUser1_0 = yt.balanceOf(TEST_USER_1);
        usersData.ytBalanceTestUser2_0 = yt.balanceOf(TEST_USER_2);
        usersData.ytBalanceTestUser3_0 = yt.balanceOf(TEST_USER_3);

        // start pranking user 1
        vm.startPrank(TEST_USER_1);

        /* MINTING SHARES */
        underlying.mint(TEST_USER_1, amount * 9);
        underlying.approve(address(principalToken), amount * 9);
        // basic mint
        _testDeposit1(amount, TEST_USER_1, TEST_USER_1);
        _testDeposit1(amount, TEST_USER_1, TEST_USER_2);
        // mint with pt/yt receivers
        _testDeposit2(amount, TEST_USER_1, TEST_USER_1, TEST_USER_1, false);
        _testDeposit2(amount, TEST_USER_1, TEST_USER_1, TEST_USER_2, false);
        _testDeposit2(amount, TEST_USER_1, TEST_USER_2, TEST_USER_1, false);
        _testDeposit2(amount, TEST_USER_1, TEST_USER_2, TEST_USER_2, false);
        _testDeposit2(amount, TEST_USER_1, TEST_USER_2, TEST_USER_3, false);
        // mint with pt/yt receivers and min shares (minShares is calculated in the fct itself)
        _testDeposit2(amount, TEST_USER_1, TEST_USER_1, TEST_USER_1, true);
        _testDeposit2(amount, TEST_USER_1, TEST_USER_2, TEST_USER_3, true);
        // data inter
        usersData.underlyingBalanceTestUser1_1 = underlying.balanceOf(TEST_USER_1);
        usersData.underlyingBalanceTestUser2_1 = underlying.balanceOf(TEST_USER_2);
        usersData.underlyingBalanceTestUser3_1 = underlying.balanceOf(TEST_USER_3);
        usersData.ibtBalanceTestUser1_1 = ibt.balanceOf(TEST_USER_1);
        usersData.ibtBalanceTestUser2_1 = ibt.balanceOf(TEST_USER_2);
        usersData.ibtBalanceTestUser3_1 = ibt.balanceOf(TEST_USER_3);
        usersData.ibtBalancePTContract_1 = ibt.balanceOf(address(principalToken));
        usersData.ptBalanceTestUser1_1 = principalToken.balanceOf(TEST_USER_1);
        usersData.ptBalanceTestUser2_1 = principalToken.balanceOf(TEST_USER_2);
        usersData.ptBalanceTestUser3_1 = principalToken.balanceOf(TEST_USER_3);
        usersData.ytBalanceTestUser1_1 = yt.balanceOf(TEST_USER_1);
        usersData.ytBalanceTestUser2_1 = yt.balanceOf(TEST_USER_2);
        usersData.ytBalanceTestUser3_1 = yt.balanceOf(TEST_USER_3);

        // assertions based on the deposits sender / pt&yt receivers
        assertApproxEqAbs(
            usersData.underlyingBalanceTestUser1_1,
            usersData.underlyingBalanceTestUser1_0,
            100,
            "Underlying Balance of Test User 1 after mint is wrong"
        );
        assertEq(
            usersData.underlyingBalanceTestUser2_1,
            usersData.underlyingBalanceTestUser2_0,
            "Underlying Balance of Test User 2 after mint is wrong"
        );
        assertEq(
            usersData.underlyingBalanceTestUser3_1,
            usersData.underlyingBalanceTestUser3_0,
            "Underlying Balance of Test User 3 after mint is wrong"
        );
        assertEq(
            usersData.ibtBalanceTestUser1_1,
            usersData.ibtBalanceTestUser1_0,
            "IBT Balance of Test User 1 after mint is wrong"
        );
        assertEq(
            usersData.ibtBalanceTestUser2_1,
            usersData.ibtBalanceTestUser2_0,
            "IBT Balance of Test User 2 after mint is wrong"
        );
        assertEq(
            usersData.ibtBalanceTestUser3_1,
            usersData.ibtBalanceTestUser3_0,
            "IBT Balance of Test User 3 after mint is wrong"
        );
        assertApproxEqAbs(
            usersData.ibtBalancePTContract_1,
            usersData.ibtBalancePTContract_0 + ibt.previewDeposit(amount) * 9,
            100,
            "IBT Balance of PT Contract after mint is wrong"
        );
        assertApproxEqAbs(
            usersData.ptBalanceTestUser1_1,
            usersData.ptBalanceTestUser1_0 + principalToken.previewDeposit(amount * 4),
            100,
            "PT Balance of Test User 1 after mint is wrong"
        );
        assertApproxEqAbs(
            usersData.ptBalanceTestUser2_1,
            usersData.ptBalanceTestUser2_0 + principalToken.previewDeposit(amount * 5),
            100,
            "PT Balance of Test User 2 after mint is wrong"
        );
        assertEq(
            usersData.ptBalanceTestUser3_1,
            usersData.ptBalanceTestUser3_0,
            "PT Balance of Test User 3 after mint is wrong"
        );
        assertApproxEqAbs(
            usersData.ytBalanceTestUser1_1,
            usersData.ytBalanceTestUser1_0 + principalToken.previewDeposit(amount * 4),
            100,
            "YieldToken Balance of Test User 1 after mint is wrong"
        );
        assertApproxEqAbs(
            usersData.ytBalanceTestUser2_1,
            usersData.ytBalanceTestUser2_0 + principalToken.previewDeposit(amount * 3),
            100,
            "YieldToken Balance of Test User 2 after mint is wrong"
        );
        assertApproxEqAbs(
            usersData.ytBalanceTestUser3_1,
            usersData.ytBalanceTestUser3_0 + principalToken.previewDeposit(amount * 2),
            100,
            "YieldToken Balance of Test User 3 after mint is wrong"
        );

        // increase time to expiry
        _increaseTimeToExpiry();

        principalToken.storeRatesAtExpiry();

        // basic redeem
        _testRedeem1(usersData.ptBalanceTestUser1_1 / 4, TEST_USER_1, TEST_USER_1, false);
        _testRedeem1(usersData.ptBalanceTestUser1_1 / 4, TEST_USER_1, TEST_USER_2, false);
        // redeem with min assets
        _testRedeem1(usersData.ptBalanceTestUser1_1 / 4, TEST_USER_1, TEST_USER_1, true);
        _testRedeem1(usersData.ptBalanceTestUser1_1 / 4, TEST_USER_1, TEST_USER_3, true);
        // data final
        usersData.underlyingBalanceTestUser1_2 = underlying.balanceOf(TEST_USER_1);
        usersData.underlyingBalanceTestUser2_2 = underlying.balanceOf(TEST_USER_2);
        usersData.underlyingBalanceTestUser3_2 = underlying.balanceOf(TEST_USER_3);
        usersData.ibtBalanceTestUser1_2 = ibt.balanceOf(TEST_USER_1);
        usersData.ibtBalanceTestUser2_2 = ibt.balanceOf(TEST_USER_2);
        usersData.ibtBalanceTestUser3_2 = ibt.balanceOf(TEST_USER_3);
        usersData.ibtBalancePTContract_2 = ibt.balanceOf(address(principalToken));
        usersData.ptBalanceTestUser1_2 = principalToken.balanceOf(TEST_USER_1);
        usersData.ptBalanceTestUser2_2 = principalToken.balanceOf(TEST_USER_2);
        usersData.ptBalanceTestUser3_2 = principalToken.balanceOf(TEST_USER_3);
        usersData.ytBalanceTestUser1_2 = yt.actualBalanceOf(TEST_USER_1);
        usersData.ytBalanceTestUser2_2 = yt.actualBalanceOf(TEST_USER_2);
        usersData.ytBalanceTestUser3_2 = yt.actualBalanceOf(TEST_USER_3);
        usersData.underlyingAmount0 = principalToken.previewRedeem(
            usersData.ptBalanceTestUser1_1 / 4
        );

        // assertions based on the deposits sender / pt&yt receivers
        assertApproxEqAbs(
            usersData.underlyingBalanceTestUser1_2,
            usersData.underlyingBalanceTestUser1_1 + 2 * usersData.underlyingAmount0,
            100,
            "Underlying Balance of Test User 1 after redeem is wrong"
        );
        assertApproxEqAbs(
            usersData.underlyingBalanceTestUser2_2,
            usersData.underlyingBalanceTestUser2_1 + usersData.underlyingAmount0,
            100,
            "Underlying Balance of Test User 2 after redeem is wrong"
        );
        assertApproxEqAbs(
            usersData.underlyingBalanceTestUser3_2,
            usersData.underlyingBalanceTestUser3_1 + usersData.underlyingAmount0,
            100,
            "Underlying Balance of Test User 3 after redeem is wrong"
        );
        assertEq(
            usersData.ibtBalanceTestUser1_2,
            usersData.ibtBalanceTestUser1_1,
            "IBT Balance of Test User 1 after redeem is wrong"
        );
        assertEq(
            usersData.ibtBalanceTestUser2_2,
            usersData.ibtBalanceTestUser2_1,
            "IBT Balance of Test User 2 after redeem is wrong"
        );
        assertEq(
            usersData.ibtBalanceTestUser3_2,
            usersData.ibtBalanceTestUser3_1,
            "IBT Balance of Test User 3 after redeem is wrong"
        );
        assertApproxEqAbs(
            usersData.ibtBalancePTContract_1,
            usersData.ibtBalancePTContract_2 + ibt.previewDeposit(usersData.underlyingAmount0) * 4,
            100,
            "IBT Balance of PT Contract after redeem is wrong"
        );
        assertApproxEqAbs(
            usersData.ptBalanceTestUser1_1,
            usersData.ptBalanceTestUser1_2 +
                principalToken.convertToPrincipal(usersData.underlyingAmount0 * 4),
            100,
            "PT Balance of Test User 1 after redeem is wrong"
        );
        assertEq(
            usersData.ptBalanceTestUser2_1,
            usersData.ptBalanceTestUser2_2,
            "PT Balance of Test User 2 after redeem is wrong"
        );
        assertEq(
            usersData.ptBalanceTestUser3_1,
            usersData.ptBalanceTestUser3_2,
            "PT Balance of Test User 3 after redeem is wrong"
        );
        assertEq(
            usersData.ytBalanceTestUser1_1,
            usersData.ytBalanceTestUser1_2,
            "YieldToken Balance of Test User 1 after redeem is wrong"
        );
        assertEq(
            usersData.ytBalanceTestUser2_1,
            usersData.ytBalanceTestUser2_2,
            "YieldToken Balance of Test User 2 after redeem is wrong"
        );
        assertEq(
            usersData.ytBalanceTestUser3_1,
            usersData.ytBalanceTestUser3_2,
            "YieldToken Balance of Test User 3 after redeem is wrong"
        );

        // stop pranking user 1
        vm.stopPrank();
    }

    /**
     * @dev Tests withdraw method of the PT contract
     */
    function testSimpleWithdrawFuzz(uint256 amount) public {
        amount = bound(amount, 0, 10000000e18);
        TestUsersData memory usersData;

        // data before
        usersData.underlyingBalanceTestUser1_0 = underlying.balanceOf(TEST_USER_1);
        usersData.underlyingBalanceTestUser2_0 = underlying.balanceOf(TEST_USER_2);
        usersData.underlyingBalanceTestUser3_0 = underlying.balanceOf(TEST_USER_3);
        usersData.ibtBalanceTestUser1_0 = ibt.balanceOf(TEST_USER_1);
        usersData.ibtBalanceTestUser2_0 = ibt.balanceOf(TEST_USER_2);
        usersData.ibtBalanceTestUser3_0 = ibt.balanceOf(TEST_USER_3);
        usersData.ibtBalancePTContract_0 = ibt.balanceOf(address(principalToken));
        usersData.ptBalanceTestUser1_0 = principalToken.balanceOf(TEST_USER_1);
        usersData.ptBalanceTestUser2_0 = principalToken.balanceOf(TEST_USER_2);
        usersData.ptBalanceTestUser3_0 = principalToken.balanceOf(TEST_USER_3);
        usersData.ytBalanceTestUser1_0 = yt.balanceOf(TEST_USER_1);
        usersData.ytBalanceTestUser2_0 = yt.balanceOf(TEST_USER_2);
        usersData.ytBalanceTestUser3_0 = yt.balanceOf(TEST_USER_3);

        // start pranking user 1
        vm.startPrank(TEST_USER_1);

        /* MINTING WITH UNDERLYING ASSETS */
        underlying.mint(TEST_USER_1, amount * 9);
        underlying.approve(address(principalToken), amount * 9);
        // basic mint
        _testDeposit1(amount, TEST_USER_1, TEST_USER_1);
        _testDeposit1(amount, TEST_USER_1, TEST_USER_2);
        // mint with pt/yt receivers
        _testDeposit2(amount, TEST_USER_1, TEST_USER_1, TEST_USER_1, false);
        _testDeposit2(amount, TEST_USER_1, TEST_USER_1, TEST_USER_2, false);
        _testDeposit2(amount, TEST_USER_1, TEST_USER_2, TEST_USER_1, false);
        _testDeposit2(amount, TEST_USER_1, TEST_USER_2, TEST_USER_2, false);
        _testDeposit2(amount, TEST_USER_1, TEST_USER_2, TEST_USER_3, false);
        // mint with pt/yt receivers and min shares (minShares is calculated in the fct itself)
        _testDeposit2(amount, TEST_USER_1, TEST_USER_1, TEST_USER_1, true);
        _testDeposit2(amount, TEST_USER_1, TEST_USER_2, TEST_USER_3, true);

        // data inter
        usersData.underlyingBalanceTestUser1_1 = underlying.balanceOf(TEST_USER_1);
        usersData.underlyingBalanceTestUser2_1 = underlying.balanceOf(TEST_USER_2);
        usersData.underlyingBalanceTestUser3_1 = underlying.balanceOf(TEST_USER_3);
        usersData.ibtBalanceTestUser1_1 = ibt.balanceOf(TEST_USER_1);
        usersData.ibtBalanceTestUser2_1 = ibt.balanceOf(TEST_USER_2);
        usersData.ibtBalanceTestUser3_1 = ibt.balanceOf(TEST_USER_3);
        usersData.ibtBalancePTContract_1 = ibt.balanceOf(address(principalToken));
        usersData.ptBalanceTestUser1_1 = principalToken.balanceOf(TEST_USER_1);
        usersData.ptBalanceTestUser2_1 = principalToken.balanceOf(TEST_USER_2);
        usersData.ptBalanceTestUser3_1 = principalToken.balanceOf(TEST_USER_3);
        usersData.ytBalanceTestUser1_1 = yt.balanceOf(TEST_USER_1);
        usersData.ytBalanceTestUser2_1 = yt.balanceOf(TEST_USER_2);
        usersData.ytBalanceTestUser3_1 = yt.balanceOf(TEST_USER_3);

        // assertions based on the deposits sender / pt&yt receivers
        assertApproxEqAbs(
            usersData.underlyingBalanceTestUser1_1,
            usersData.underlyingBalanceTestUser1_0,
            100,
            "Underlying Balance of Test User 1 after mint is wrong"
        );
        assertEq(
            usersData.underlyingBalanceTestUser2_1,
            usersData.underlyingBalanceTestUser2_0,
            "Underlying Balance of Test User 2 after mint is wrong"
        );
        assertEq(
            usersData.underlyingBalanceTestUser3_1,
            usersData.underlyingBalanceTestUser3_0,
            "Underlying Balance of Test User 3 after mint is wrong"
        );
        assertEq(
            usersData.ibtBalanceTestUser1_1,
            usersData.ibtBalanceTestUser1_0,
            "IBT Balance of Test User 1 after mint is wrong"
        );
        assertEq(
            usersData.ibtBalanceTestUser2_1,
            usersData.ibtBalanceTestUser2_0,
            "IBT Balance of Test User 2 after mint is wrong"
        );
        assertEq(
            usersData.ibtBalanceTestUser3_1,
            usersData.ibtBalanceTestUser3_0,
            "IBT Balance of Test User 3 after mint is wrong"
        );
        assertApproxEqAbs(
            usersData.ibtBalancePTContract_1,
            usersData.ibtBalancePTContract_0 + ibt.previewDeposit(amount * 9),
            100,
            "IBT Balance of PT Contract after mint is wrong"
        );
        assertApproxEqAbs(
            usersData.ptBalanceTestUser1_1,
            usersData.ptBalanceTestUser1_0 + principalToken.previewDeposit(amount * 4),
            100,
            "PT Balance of Test User 1 after mint is wrong"
        );
        assertApproxEqAbs(
            usersData.ptBalanceTestUser2_1,
            usersData.ptBalanceTestUser2_0 + principalToken.previewDeposit(amount * 5),
            100,
            "PT Balance of Test User 2 after mint is wrong"
        );
        assertEq(
            usersData.ptBalanceTestUser3_1,
            usersData.ptBalanceTestUser3_0,
            "PT Balance of Test User 3 after mint is wrong"
        );
        assertApproxEqAbs(
            usersData.ytBalanceTestUser1_1,
            usersData.ytBalanceTestUser1_0 + principalToken.previewDeposit(amount * 4),
            100,
            "YieldToken Balance of Test User 1 after mint is wrong"
        );
        assertApproxEqAbs(
            usersData.ytBalanceTestUser2_1,
            usersData.ytBalanceTestUser2_0 + principalToken.previewDeposit(amount * 3),
            100,
            "YieldToken Balance of Test User 2 after mint is wrong"
        );
        assertApproxEqAbs(
            usersData.ytBalanceTestUser3_1,
            usersData.ytBalanceTestUser3_0 + principalToken.previewDeposit(amount * 2),
            100,
            "YieldToken Balance of Test User 3 after mint is wrong"
        );

        // every user withdraws with user 1 as receiver
        // user 1
        uint256 maxWithdraw = principalToken.maxWithdraw(TEST_USER_1);
        uint256 previewWithdraw = principalToken.previewWithdraw(maxWithdraw);
        uint256 actualWithdraw = _testWithdraw1(maxWithdraw, TEST_USER_1, TEST_USER_1, false);
        assertEq(maxWithdraw, amount * 4, "Max Withdraw for user 1 is wrong");
        assertEq(
            previewWithdraw,
            principalToken.previewDeposit(amount * 4),
            "Preview withdraw for user 1 is wrong"
        );
        // user 2
        maxWithdraw = principalToken.maxWithdraw(TEST_USER_2);
        previewWithdraw = principalToken.previewWithdraw(maxWithdraw);
        vm.stopPrank();
        vm.startPrank(TEST_USER_2);
        actualWithdraw = _testWithdraw1(maxWithdraw, TEST_USER_2, TEST_USER_1, true);
        assertEq(maxWithdraw, amount * 3, "Max Withdraw for user 2 is wrong");
        assertEq(
            previewWithdraw,
            principalToken.previewDeposit(amount * 3),
            "Preview withdraw for user 2 is wrong"
        );
        // user 3
        maxWithdraw = principalToken.maxWithdraw(TEST_USER_3);
        previewWithdraw = principalToken.previewWithdraw(maxWithdraw);
        vm.stopPrank();
        vm.startPrank(TEST_USER_3);
        actualWithdraw = _testWithdraw1(maxWithdraw, TEST_USER_3, TEST_USER_1, true);
        assertEq(maxWithdraw, 0, "Max Withdraw for user 3 is wrong");
        assertEq(previewWithdraw, 0, "Preview withdraw for user 3 is wrong");

        // data final
        usersData.underlyingBalanceTestUser1_2 = underlying.balanceOf(TEST_USER_1);
        usersData.underlyingBalanceTestUser2_2 = underlying.balanceOf(TEST_USER_2);
        usersData.underlyingBalanceTestUser3_2 = underlying.balanceOf(TEST_USER_3);
        usersData.ibtBalanceTestUser1_2 = ibt.balanceOf(TEST_USER_1);
        usersData.ibtBalanceTestUser2_2 = ibt.balanceOf(TEST_USER_2);
        usersData.ibtBalanceTestUser3_2 = ibt.balanceOf(TEST_USER_3);
        usersData.ibtBalancePTContract_2 = ibt.balanceOf(address(principalToken));
        usersData.ptBalanceTestUser1_2 = principalToken.balanceOf(TEST_USER_1);
        usersData.ptBalanceTestUser2_2 = principalToken.balanceOf(TEST_USER_2);
        usersData.ptBalanceTestUser3_2 = principalToken.balanceOf(TEST_USER_3);
        usersData.ytBalanceTestUser1_2 = yt.balanceOf(TEST_USER_1);
        usersData.ytBalanceTestUser2_2 = yt.balanceOf(TEST_USER_2);
        usersData.ytBalanceTestUser3_2 = yt.balanceOf(TEST_USER_3);

        // assertions based on the withdraws
        assertApproxEqAbs(
            usersData.underlyingBalanceTestUser1_2,
            usersData.underlyingBalanceTestUser1_1 + amount * 7,
            100,
            "Underlying Balance of Test User 1 after withdraw is wrong"
        );
        assertEq(
            usersData.underlyingBalanceTestUser2_2,
            usersData.underlyingBalanceTestUser2_1,
            "Underlying Balance of Test User 2 after withdraw is wrong"
        );
        assertEq(
            usersData.underlyingBalanceTestUser3_2,
            usersData.underlyingBalanceTestUser3_1,
            "Underlying Balance of Test User 3 after withdraw is wrong"
        );
        assertEq(
            usersData.ibtBalanceTestUser1_2,
            usersData.ibtBalanceTestUser1_1,
            "IBT Balance of Test User 1 after withdraw is wrong"
        );
        assertEq(
            usersData.ibtBalanceTestUser2_2,
            usersData.ibtBalanceTestUser2_1,
            "IBT Balance of Test User 2 after withdraw is wrong"
        );
        assertEq(
            usersData.ibtBalanceTestUser3_2,
            usersData.ibtBalanceTestUser3_1,
            "IBT Balance of Test User 3 after withdraw is wrong"
        );
        assertApproxEqAbs(
            usersData.ibtBalancePTContract_2 + ibt.previewDeposit(amount * 7),
            usersData.ibtBalancePTContract_1,
            100,
            "IBT Balance of PT Contract after withdraw is wrong"
        );
        assertApproxEqAbs(
            usersData.ptBalanceTestUser1_2 + principalToken.previewDeposit(amount * 4),
            usersData.ptBalanceTestUser1_1,
            100,
            "PT Balance of Test User 1 after withdraw is wrong"
        );
        assertApproxEqAbs(
            usersData.ptBalanceTestUser2_2 + principalToken.previewDeposit(amount * 3),
            usersData.ptBalanceTestUser2_1,
            100,
            "PT Balance of Test User 2 after withdraw is wrong"
        );
        assertEq(
            usersData.ptBalanceTestUser3_2,
            usersData.ptBalanceTestUser3_1,
            "PT Balance of Test User 3 after withdraw is wrong"
        );
        assertApproxEqAbs(
            usersData.ytBalanceTestUser1_2 + principalToken.previewDeposit(amount * 4),
            usersData.ytBalanceTestUser1_1,
            100,
            "YieldToken Balance of Test User 1 after withdraw is wrong"
        );
        assertApproxEqAbs(
            usersData.ytBalanceTestUser2_2 + principalToken.previewDeposit(amount * 3),
            usersData.ytBalanceTestUser2_1,
            100,
            "YieldToken Balance of Test User 2 after withdraw is wrong"
        );
        assertApproxEqAbs(
            usersData.ytBalanceTestUser3_2,
            usersData.ytBalanceTestUser3_1,
            100,
            "YieldToken Balance of Test User 3 after withdraw is wrong"
        );

        // stop pranking user 1
        vm.stopPrank();
    }

    /**
     * @dev Tests redeem max + claimYield in simple conditions
     */
    function testRedeemMaxAndClaimYieldSimple() public {
        TestUsersData memory usersData;

        usersData.underlyingAmount0 = 100e18;

        // deposit 100 assets for user 1
        vm.startPrank(TEST_USER_1);
        underlying.mint(TEST_USER_1, usersData.underlyingAmount0);
        underlying.approve(address(principalToken), usersData.underlyingAmount0);
        _testDeposit2(usersData.underlyingAmount0, TEST_USER_1, TEST_USER_1, TEST_USER_1, false);
        vm.stopPrank();

        // deposit 100 assets for user 2
        vm.startPrank(TEST_USER_2);
        underlying.mint(TEST_USER_2, usersData.underlyingAmount0);
        underlying.approve(address(principalToken), usersData.underlyingAmount0);
        _testDeposit2(usersData.underlyingAmount0, TEST_USER_2, TEST_USER_2, TEST_USER_2, false);
        vm.stopPrank();

        uint256 sharesDepositedInIBT = ibt.previewDeposit(usersData.underlyingAmount0);

        // change rate: +100%
        uint16 rate = uint16(100);
        _changeRate(rate, true);

        usersData.underlyingBalanceTestUser1_1 = underlying.balanceOf(TEST_USER_1);
        usersData.underlyingBalanceTestUser2_1 = underlying.balanceOf(TEST_USER_2);
        usersData.ibtBalancePTContract_1 = ibt.balanceOf(address(principalToken));
        usersData.ptBalanceTestUser2_1 = principalToken.balanceOf(TEST_USER_2);
        usersData.ytBalanceTestUser2_1 = yt.balanceOf(TEST_USER_2);

        // user 1 redeems max and claims yield
        vm.startPrank(TEST_USER_1);
        _testRedeemMaxAndClaimYield(TEST_USER_1, TEST_USER_1);
        vm.stopPrank();

        // user 2 calls claimYield
        vm.startPrank(TEST_USER_2);
        principalToken.claimYield(TEST_USER_2, 0);
        vm.stopPrank();

        usersData.underlyingBalanceTestUser1_2 = underlying.balanceOf(TEST_USER_1);
        usersData.underlyingBalanceTestUser2_2 = underlying.balanceOf(TEST_USER_2);
        usersData.ibtBalancePTContract_2 = ibt.balanceOf(address(principalToken));
        usersData.ptBalanceTestUser2_2 = principalToken.balanceOf(TEST_USER_2);
        usersData.ytBalanceTestUser2_2 = yt.balanceOf(TEST_USER_2);

        assertApproxEqAbs(
            usersData.underlyingBalanceTestUser1_2,
            usersData.underlyingBalanceTestUser1_1 + usersData.underlyingAmount0 * 2,
            10,
            "Underlying Balance of user 1 after redeem max + claimYield is wrong"
        );
        assertEq(
            usersData.underlyingBalanceTestUser2_2,
            usersData.underlyingBalanceTestUser2_1 + usersData.underlyingAmount0,
            "Underlying Balance of user 2 after claimYield is wrong"
        );
        assertApproxEqAbs(
            usersData.ibtBalancePTContract_2 + sharesDepositedInIBT + sharesDepositedInIBT / 2,
            usersData.ibtBalancePTContract_1,
            10,
            "IBT Balance of PT Contract after redeem and both claimYield is wrong"
        );
        assertEq(
            usersData.ptBalanceTestUser2_2,
            usersData.ptBalanceTestUser2_1,
            "PT Balance of user 2 after claimYield is wrong"
        );
        assertEq(
            usersData.ytBalanceTestUser2_2,
            usersData.ytBalanceTestUser2_1,
            "YT Balance of user 2 after claimYield is wrong"
        );
    }

    /**
     * @dev Tests redeem max + claimYield methods with fuzzed deposit amounts
     */
    function testRedeemMaxAndClaimYieldNoYieldFuzz(uint256 amount) public {
        TestUsersData memory usersData;

        usersData.underlyingAmount0 = bound(amount, 0, 10000000e18);

        vm.startPrank(TEST_USER_1);
        underlying.mint(TEST_USER_1, usersData.underlyingAmount0 * 9);
        underlying.approve(address(principalToken), usersData.underlyingAmount0 * 9);
        // basic mint
        _testDeposit2(
            usersData.underlyingAmount0 * 2,
            TEST_USER_1,
            TEST_USER_1,
            TEST_USER_1,
            false
        );
        _testDeposit2(
            usersData.underlyingAmount0 * 2,
            TEST_USER_1,
            TEST_USER_2,
            TEST_USER_2,
            false
        );
        // deposit with different pt/yt receivers
        _testDeposit2(usersData.underlyingAmount0, TEST_USER_1, TEST_USER_1, TEST_USER_2, false);
        _testDeposit2(usersData.underlyingAmount0, TEST_USER_1, TEST_USER_2, TEST_USER_1, false);
        _testDeposit2(usersData.underlyingAmount0, TEST_USER_1, TEST_USER_2, TEST_USER_3, false);
        // deposit with min shares
        _testDeposit2(usersData.underlyingAmount0, TEST_USER_1, TEST_USER_1, TEST_USER_1, true);
        _testDeposit2(usersData.underlyingAmount0, TEST_USER_1, TEST_USER_2, TEST_USER_3, true);

        usersData.underlyingBalanceTestUser1_1 = underlying.balanceOf(TEST_USER_1);
        usersData.underlyingBalanceTestUser2_1 = underlying.balanceOf(TEST_USER_2);
        usersData.underlyingBalanceTestUser3_1 = underlying.balanceOf(TEST_USER_3);
        usersData.ytBalanceTestUser3_1 = yt.balanceOf(TEST_USER_3);
        usersData.ibtBalancePTContract_1 = ibt.balanceOf(address(principalToken));

        // every user redeems with user 1 as receiver
        // user 1
        uint256 yieldIBT = principalToken.getCurrentYieldOfUserInIBT(TEST_USER_1);
        uint256 receivedAssets = _testRedeemMaxAndClaimYield(TEST_USER_1, TEST_USER_1);
        assertEq(yieldIBT, 0, "No yield should have been generated");
        // assuming 0 tokenization fee
        assertEq(receivedAssets, usersData.underlyingAmount0 * 4, "redeem max for user 1 is wrong");
        vm.stopPrank();

        // user 2
        vm.startPrank(TEST_USER_2);
        yieldIBT = principalToken.getCurrentYieldOfUserInIBT(TEST_USER_2);
        receivedAssets = _testRedeemMaxAndClaimYield(TEST_USER_2, TEST_USER_1);
        assertEq(yieldIBT, 0, "No yield should have been generated");
        // assuming 0 tokenization fee
        assertEq(receivedAssets, usersData.underlyingAmount0 * 3, "redeem max for user 2 is wrong");
        vm.stopPrank();

        // user 3
        vm.startPrank(TEST_USER_3);
        yieldIBT = principalToken.getCurrentYieldOfUserInIBT(TEST_USER_2);
        receivedAssets = _testRedeemMaxAndClaimYield(TEST_USER_2, TEST_USER_1);
        assertEq(yieldIBT, 0, "No yield should have been generated");
        assertEq(receivedAssets, 0, "redeem max for user 3 is wrong");
        vm.stopPrank();

        usersData.underlyingBalanceTestUser1_2 = underlying.balanceOf(TEST_USER_1);
        usersData.underlyingBalanceTestUser2_2 = underlying.balanceOf(TEST_USER_2);
        usersData.underlyingBalanceTestUser3_2 = underlying.balanceOf(TEST_USER_3);
        usersData.ytBalanceTestUser3_2 = yt.balanceOf(TEST_USER_3);
        usersData.ibtBalancePTContract_2 = ibt.balanceOf(address(principalToken));

        // assertions based on the withdraws
        assertEq(
            usersData.underlyingBalanceTestUser1_2,
            usersData.underlyingBalanceTestUser1_1 + usersData.underlyingAmount0 * 7,
            "Underlying Balance of user 1 after redeems is wrong"
        );
        assertEq(
            usersData.underlyingBalanceTestUser2_2,
            usersData.underlyingBalanceTestUser2_1,
            "Underlying Balance of user 2 after redeem is wrong"
        );
        assertEq(
            usersData.underlyingBalanceTestUser3_2,
            usersData.underlyingBalanceTestUser3_1,
            "Underlying Balance of user 3 after redeem is wrong"
        );
        assertEq(
            usersData.ytBalanceTestUser3_2,
            usersData.ytBalanceTestUser3_1,
            "YT Balance of user 3 after redeem is wrong"
        );
        assertApproxEqAbs(
            usersData.ibtBalancePTContract_2 + ibt.previewDeposit(usersData.underlyingAmount0 * 7),
            usersData.ibtBalancePTContract_1,
            10,
            "IBT Balance of PT Contract after redeem is wrong"
        );
    }

    /**
     * @dev Tests redeem max + claimYield method of the PT contract with generated yield
     */
    function testRedeemMaxAndClaimYieldPYieldFuzz(uint256 amount, uint16 rate) public {
        amount = bound(amount, 1e10, 10000000e18);
        TestUsersData memory usersData;

        usersData.underlyingAmount0 = amount;

        // data before
        usersData.ptBalanceTestUser3_0 = principalToken.balanceOf(TEST_USER_3);

        // start pranking user 1
        vm.startPrank(TEST_USER_1);

        underlying.mint(TEST_USER_1, usersData.underlyingAmount0 * 9);
        underlying.approve(address(principalToken), usersData.underlyingAmount0 * 9);

        _testDeposit2(
            usersData.underlyingAmount0 * 2,
            TEST_USER_1,
            TEST_USER_1,
            TEST_USER_1,
            false
        );
        _testDeposit2(
            usersData.underlyingAmount0 * 2,
            TEST_USER_1,
            TEST_USER_2,
            TEST_USER_2,
            false
        );
        // deposit with different pt/yt receivers
        _testDeposit2(usersData.underlyingAmount0, TEST_USER_1, TEST_USER_1, TEST_USER_2, false);
        _testDeposit2(usersData.underlyingAmount0, TEST_USER_1, TEST_USER_2, TEST_USER_1, false);
        _testDeposit2(usersData.underlyingAmount0, TEST_USER_1, TEST_USER_2, TEST_USER_3, false);
        // deposit with min shares
        _testDeposit2(usersData.underlyingAmount0, TEST_USER_1, TEST_USER_1, TEST_USER_1, true);
        _testDeposit2(usersData.underlyingAmount0, TEST_USER_1, TEST_USER_2, TEST_USER_3, true);

        // data inter
        usersData.underlyingBalanceTestUser1_1 = underlying.balanceOf(TEST_USER_1);
        usersData.underlyingBalanceTestUser2_1 = underlying.balanceOf(TEST_USER_2);
        usersData.underlyingBalanceTestUser3_1 = underlying.balanceOf(TEST_USER_3);
        usersData.ibtBalancePTContract_1 = ibt.balanceOf(address(principalToken));

        assertEq(
            usersData.ptBalanceTestUser3_1,
            usersData.ptBalanceTestUser3_0,
            "PT Balance of Test User 3 after mint is wrong"
        );

        // change rate
        rate = uint16(bound(rate, 0, 1000));
        _changeRate(rate, true);

        // yield = amount + (amount * (rate * 1e16)) / 1e18
        uint128 rateCalc = uint128(rate);

        // every user redeems with user 1 as receiver
        // user 1
        uint256 receivedAssets = _testRedeemMaxAndClaimYield(TEST_USER_1, TEST_USER_1);
        assertApproxEqRel(
            receivedAssets,
            _calculateYieldGain(usersData.underlyingAmount0 * 4, rateCalc),
            1e10,
            "After redeem max + claimYield for user 1, received asset amount is wrong"
        );
        vm.stopPrank();

        // user 2
        vm.startPrank(TEST_USER_2);
        receivedAssets = _testRedeemMaxAndClaimYield(TEST_USER_2, TEST_USER_1);
        assertApproxEqRel(
            receivedAssets,
            _calculateYieldGain(usersData.underlyingAmount0 * 3, rateCalc),
            1e10,
            "After redeem max + claimYield for user 2, received asset amount is wrong"
        );
        vm.stopPrank();

        // user 3
        vm.startPrank(TEST_USER_3);
        receivedAssets = _testRedeemMaxAndClaimYield(TEST_USER_3, TEST_USER_1);
        assertApproxEqRel(
            receivedAssets,
            _calculateYieldGain(usersData.underlyingAmount0 * 2, rateCalc) -
                (usersData.underlyingAmount0 * 2), // user3 only has YTs
            1e10,
            "After redeem max + claimYield for user 3, received asset amount is wrong"
        );
        vm.stopPrank();

        // data final
        usersData.underlyingBalanceTestUser1_2 = underlying.balanceOf(TEST_USER_1);
        usersData.underlyingBalanceTestUser2_2 = underlying.balanceOf(TEST_USER_2);
        usersData.underlyingBalanceTestUser3_2 = underlying.balanceOf(TEST_USER_3);
        usersData.ibtBalancePTContract_2 = ibt.balanceOf(address(principalToken));

        // assertions based on the withdraws
        assertApproxEqRel(
            usersData.underlyingBalanceTestUser1_2,
            usersData.underlyingBalanceTestUser1_1 +
                _calculateYieldGain(usersData.underlyingAmount0 * 9, rateCalc) -
                (usersData.underlyingAmount0 * 2),
            1e8,
            "Underlying Balance of Test User 1 after redeem + claimYield calls is wrong"
        );

        assertEq(
            usersData.underlyingBalanceTestUser2_2,
            usersData.underlyingBalanceTestUser2_1,
            "Underlying Balance of Test User 2 after redeem + claimYield is wrong"
        );
        assertEq(
            usersData.underlyingBalanceTestUser3_2,
            usersData.underlyingBalanceTestUser3_1,
            "Underlying Balance of Test User 3 after redeem + claimYield is wrong"
        );

        assertApproxEqRel(
            usersData.ibtBalancePTContract_2 +
                ibt.previewDeposit(
                    _calculateYieldGain(usersData.underlyingAmount0 * 9, rateCalc) -
                        (usersData.underlyingAmount0 * 2)
                ),
            usersData.ibtBalancePTContract_1,
            1e8,
            "IBT Balance of PT Contract after redeem is wrong"
        );
    }

    function testGetTotalFeesInIBTFuzz(uint256 amount) public {
        amount = bound(amount, 1e10, 10000000e18);
        TestUsersData memory usersData;

        vm.prank(scriptAdmin);
        registry.setTokenizationFee(TOKENIZATION_FEE);

        // data before
        usersData.underlyingBalanceTestUser1_0 = underlying.balanceOf(TEST_USER_1);
        usersData.ibtBalanceTestUser1_0 = ibt.balanceOf(TEST_USER_1);
        usersData.ptBalanceTestUser1_0 = principalToken.balanceOf(TEST_USER_1);
        usersData.ytBalanceTestUser1_0 = yt.balanceOf(TEST_USER_1);

        // start pranking user 1
        vm.startPrank(TEST_USER_1);

        /* MINTING WITH UNDERLYING ASSETS */
        underlying.mint(TEST_USER_1, amount * 2);
        underlying.approve(address(principalToken), amount * 2);
        // basic mint
        principalToken.deposit(2 * amount, TEST_USER_1);

        // data inter
        usersData.underlyingBalanceTestUser1_1 = underlying.balanceOf(TEST_USER_1);
        usersData.ibtBalanceTestUser1_1 = ibt.balanceOf(TEST_USER_1);
        usersData.ptBalanceTestUser1_1 = principalToken.balanceOf(TEST_USER_1);
        usersData.ytBalanceTestUser1_1 = yt.balanceOf(TEST_USER_1);
        usersData.ibtBalancePTContract_1 = ibt.balanceOf(address(principalToken));

        // assertions based on the deposits sender / pt&yt receivers
        assertApproxEqAbs(
            usersData.underlyingBalanceTestUser1_1,
            usersData.underlyingBalanceTestUser1_0,
            100,
            "Underlying Balance of Test User 1 after mint is wrong"
        );
        assertEq(
            usersData.ibtBalanceTestUser1_1,
            usersData.ibtBalanceTestUser1_0,
            "IBT Balance of Test User 1 after mint is wrong"
        );
        assertApproxEqAbs(
            usersData.ibtBalancePTContract_1,
            usersData.ibtBalancePTContract_0 + ibt.previewDeposit(amount * 2),
            100,
            "IBT Balance of PT Contract after mint is wrong"
        );
        assertApproxEqAbs(
            usersData.ptBalanceTestUser1_1,
            usersData.ptBalanceTestUser1_0 + principalToken.previewDeposit(amount * 2),
            100,
            "PT Balance of Test User 1 after mint is wrong"
        );
        assertApproxEqAbs(
            usersData.ytBalanceTestUser1_1,
            usersData.ytBalanceTestUser1_0 + principalToken.previewDeposit(amount * 2),
            100,
            "YieldToken Balance of Test User 1 after mint is wrong"
        );
        vm.stopPrank();

        uint256 totFees = principalToken.getTotalFeesInIBT();
        assertApproxEqAbs(
            totFees,
            ibt.previewDeposit((amount * 2 * TOKENIZATION_FEE) / 1e18),
            100,
            "the fees accumulated should be the ones taken on deposit"
        );
        uint256 unclaimedFees = principalToken.getUnclaimedFeesInIBT();
        assertEq(totFees, unclaimedFees, "nothing was claimed yet");
        vm.prank(registry.getFeeCollector());
        principalToken.claimFees(0);
        assertApproxEqAbs(
            totFees,
            ibt.previewDeposit((amount * 2 * TOKENIZATION_FEE) / 1e18),
            100,
            "total fees stays the same"
        );
        assertEq(principalToken.getUnclaimedFeesInIBT(), 0, "everything was claimed");
    }

    /**
     * @dev Tests withdrawIBT method of the PT contract
     */
    function testSimpleWithdrawIBTFuzz(uint256 amount) public {
        amount = bound(amount, 0, 10000000e18);
        TestUsersData memory usersData;

        // data before
        usersData.underlyingBalanceTestUser1_0 = underlying.balanceOf(TEST_USER_1);
        usersData.underlyingBalanceTestUser2_0 = underlying.balanceOf(TEST_USER_2);
        usersData.underlyingBalanceTestUser3_0 = underlying.balanceOf(TEST_USER_3);
        usersData.ibtBalanceTestUser1_0 = ibt.balanceOf(TEST_USER_1);
        usersData.ibtBalanceTestUser2_0 = ibt.balanceOf(TEST_USER_2);
        usersData.ibtBalanceTestUser3_0 = ibt.balanceOf(TEST_USER_3);
        usersData.ibtBalancePTContract_0 = ibt.balanceOf(address(principalToken));
        usersData.ptBalanceTestUser1_0 = principalToken.balanceOf(TEST_USER_1);
        usersData.ptBalanceTestUser2_0 = principalToken.balanceOf(TEST_USER_2);
        usersData.ptBalanceTestUser3_0 = principalToken.balanceOf(TEST_USER_3);
        usersData.ytBalanceTestUser1_0 = yt.balanceOf(TEST_USER_1);
        usersData.ytBalanceTestUser2_0 = yt.balanceOf(TEST_USER_2);
        usersData.ytBalanceTestUser3_0 = yt.balanceOf(TEST_USER_3);

        // start pranking user 1
        vm.startPrank(TEST_USER_1);

        /* MINTING WITH UNDERLYING ASSETS */
        underlying.mint(TEST_USER_1, amount * 9);
        underlying.approve(address(principalToken), amount * 9);
        // basic mint
        _testDeposit1(amount, TEST_USER_1, TEST_USER_1);
        _testDeposit1(amount, TEST_USER_1, TEST_USER_2);
        // mint with pt/yt receivers
        _testDeposit2(amount, TEST_USER_1, TEST_USER_1, TEST_USER_1, false);
        _testDeposit2(amount, TEST_USER_1, TEST_USER_1, TEST_USER_2, false);
        _testDeposit2(amount, TEST_USER_1, TEST_USER_2, TEST_USER_1, false);
        _testDeposit2(amount, TEST_USER_1, TEST_USER_2, TEST_USER_2, false);
        _testDeposit2(amount, TEST_USER_1, TEST_USER_2, TEST_USER_3, false);
        // mint with pt/yt receivers and min shares (minShares is calculated in the fct itself)
        _testDeposit2(amount, TEST_USER_1, TEST_USER_1, TEST_USER_1, true);
        _testDeposit2(amount, TEST_USER_1, TEST_USER_2, TEST_USER_3, true);

        // data inter
        usersData.underlyingBalanceTestUser1_1 = underlying.balanceOf(TEST_USER_1);
        usersData.underlyingBalanceTestUser2_1 = underlying.balanceOf(TEST_USER_2);
        usersData.underlyingBalanceTestUser3_1 = underlying.balanceOf(TEST_USER_3);
        usersData.ibtBalanceTestUser1_1 = ibt.balanceOf(TEST_USER_1);
        usersData.ibtBalanceTestUser2_1 = ibt.balanceOf(TEST_USER_2);
        usersData.ibtBalanceTestUser3_1 = ibt.balanceOf(TEST_USER_3);
        usersData.ibtBalancePTContract_1 = ibt.balanceOf(address(principalToken));
        usersData.ptBalanceTestUser1_1 = principalToken.balanceOf(TEST_USER_1);
        usersData.ptBalanceTestUser2_1 = principalToken.balanceOf(TEST_USER_2);
        usersData.ptBalanceTestUser3_1 = principalToken.balanceOf(TEST_USER_3);
        usersData.ytBalanceTestUser1_1 = yt.balanceOf(TEST_USER_1);
        usersData.ytBalanceTestUser2_1 = yt.balanceOf(TEST_USER_2);
        usersData.ytBalanceTestUser3_1 = yt.balanceOf(TEST_USER_3);

        // assertions based on the deposits sender / pt&yt receivers
        assertApproxEqAbs(
            usersData.underlyingBalanceTestUser1_1,
            usersData.underlyingBalanceTestUser1_0,
            100,
            "Underlying Balance of Test User 1 after mint is wrong"
        );
        assertEq(
            usersData.underlyingBalanceTestUser2_1,
            usersData.underlyingBalanceTestUser2_0,
            "Underlying Balance of Test User 2 after mint is wrong"
        );
        assertEq(
            usersData.underlyingBalanceTestUser3_1,
            usersData.underlyingBalanceTestUser3_0,
            "Underlying Balance of Test User 3 after mint is wrong"
        );
        assertEq(
            usersData.ibtBalanceTestUser1_1,
            usersData.ibtBalanceTestUser1_0,
            "IBT Balance of Test User 1 after mint is wrong"
        );
        assertEq(
            usersData.ibtBalanceTestUser2_1,
            usersData.ibtBalanceTestUser2_0,
            "IBT Balance of Test User 2 after mint is wrong"
        );
        assertEq(
            usersData.ibtBalanceTestUser3_1,
            usersData.ibtBalanceTestUser3_0,
            "IBT Balance of Test User 3 after mint is wrong"
        );
        assertApproxEqAbs(
            usersData.ibtBalancePTContract_1,
            usersData.ibtBalancePTContract_0 + ibt.previewDeposit(amount * 9),
            100,
            "IBT Balance of PT Contract after mint is wrong"
        );
        assertApproxEqAbs(
            usersData.ptBalanceTestUser1_1,
            usersData.ptBalanceTestUser1_0 + principalToken.previewDeposit(amount * 4),
            100,
            "PT Balance of Test User 1 after mint is wrong"
        );
        assertApproxEqAbs(
            usersData.ptBalanceTestUser2_1,
            usersData.ptBalanceTestUser2_0 + principalToken.previewDeposit(amount * 5),
            100,
            "PT Balance of Test User 2 after mint is wrong"
        );
        assertEq(
            usersData.ptBalanceTestUser3_1,
            usersData.ptBalanceTestUser3_0,
            "PT Balance of Test User 3 after mint is wrong"
        );
        assertApproxEqAbs(
            usersData.ytBalanceTestUser1_1,
            usersData.ytBalanceTestUser1_0 + principalToken.previewDeposit(amount * 4),
            100,
            "YieldToken Balance of Test User 1 after mint is wrong"
        );
        assertApproxEqAbs(
            usersData.ytBalanceTestUser2_1,
            usersData.ytBalanceTestUser2_0 + principalToken.previewDeposit(amount * 3),
            100,
            "YieldToken Balance of Test User 2 after mint is wrong"
        );
        assertApproxEqAbs(
            usersData.ytBalanceTestUser3_1,
            usersData.ytBalanceTestUser3_0 + principalToken.previewDeposit(amount * 2),
            100,
            "YieldToken Balance of Test User 3 after mint is wrong"
        );

        uint256 ibtAmount = ibt.previewDeposit(amount);
        // every user withdraws with user 1 as receiver
        // user 1
        uint256 maxWithdraw = ibt.previewDeposit(principalToken.maxWithdraw(TEST_USER_1));
        uint256 previewWithdraw = principalToken.previewWithdrawIBT(maxWithdraw);
        uint256 actualWithdraw = _testWithdrawIBT1(maxWithdraw, TEST_USER_1, TEST_USER_1, false);
        assertEq(maxWithdraw, ibtAmount * 4, "Max Withdraw for user 1 is wrong");
        assertEq(
            previewWithdraw,
            principalToken.previewDeposit(amount * 4),
            "Preview withdraw for user 1 is wrong"
        );
        // user 2
        maxWithdraw = ibt.previewDeposit(principalToken.maxWithdraw(TEST_USER_2));
        previewWithdraw = principalToken.previewWithdrawIBT(maxWithdraw);
        vm.stopPrank();
        vm.startPrank(TEST_USER_2);
        actualWithdraw = _testWithdrawIBT1(maxWithdraw, TEST_USER_2, TEST_USER_1, true);
        assertEq(maxWithdraw, ibtAmount * 3, "Max Withdraw for user 2 is wrong");
        assertEq(
            previewWithdraw,
            principalToken.previewDeposit(amount * 3),
            "Preview withdraw for user 2 is wrong"
        );
        // user 3
        maxWithdraw = ibt.previewDeposit(principalToken.maxWithdraw(TEST_USER_3));
        previewWithdraw = principalToken.previewWithdrawIBT(maxWithdraw);
        vm.stopPrank();
        vm.startPrank(TEST_USER_3);
        actualWithdraw = _testWithdrawIBT1(maxWithdraw, TEST_USER_3, TEST_USER_1, true);
        assertEq(maxWithdraw, 0, "Max Withdraw for user 3 is wrong");
        assertEq(previewWithdraw, 0, "Preview withdraw for user 3 is wrong");

        // data final
        usersData.underlyingBalanceTestUser1_2 = underlying.balanceOf(TEST_USER_1);
        usersData.underlyingBalanceTestUser2_2 = underlying.balanceOf(TEST_USER_2);
        usersData.underlyingBalanceTestUser3_2 = underlying.balanceOf(TEST_USER_3);
        usersData.ibtBalanceTestUser1_2 = ibt.balanceOf(TEST_USER_1);
        usersData.ibtBalanceTestUser2_2 = ibt.balanceOf(TEST_USER_2);
        usersData.ibtBalanceTestUser3_2 = ibt.balanceOf(TEST_USER_3);
        usersData.ibtBalancePTContract_2 = ibt.balanceOf(address(principalToken));
        usersData.ptBalanceTestUser1_2 = principalToken.balanceOf(TEST_USER_1);
        usersData.ptBalanceTestUser2_2 = principalToken.balanceOf(TEST_USER_2);
        usersData.ptBalanceTestUser3_2 = principalToken.balanceOf(TEST_USER_3);
        usersData.ytBalanceTestUser1_2 = yt.balanceOf(TEST_USER_1);
        usersData.ytBalanceTestUser2_2 = yt.balanceOf(TEST_USER_2);
        usersData.ytBalanceTestUser3_2 = yt.balanceOf(TEST_USER_3);

        // assertions based on the withdraws
        assertEq(
            usersData.underlyingBalanceTestUser1_2,
            usersData.underlyingBalanceTestUser1_1,
            "Underlying Balance of Test User 1 after withdrawIBT is wrong"
        );
        assertEq(
            usersData.underlyingBalanceTestUser2_2,
            usersData.underlyingBalanceTestUser2_1,
            "Underlying Balance of Test User 2 after withdrawIBT is wrong"
        );
        assertEq(
            usersData.underlyingBalanceTestUser3_2,
            usersData.underlyingBalanceTestUser3_1,
            "Underlying Balance of Test User 3 after withdrawIBT is wrong"
        );
        assertEq(
            usersData.ibtBalanceTestUser1_2,
            usersData.ibtBalanceTestUser1_1 + ibtAmount * 7,
            "IBT Balance of Test User 1 after withdrawIBT is wrong"
        );
        assertEq(
            usersData.ibtBalanceTestUser2_2,
            usersData.ibtBalanceTestUser2_1,
            "IBT Balance of Test User 2 after withdrawIBT is wrong"
        );
        assertEq(
            usersData.ibtBalanceTestUser3_2,
            usersData.ibtBalanceTestUser3_1,
            "IBT Balance of Test User 3 after withdrawIBT is wrong"
        );
        assertApproxEqAbs(
            usersData.ibtBalancePTContract_2 + ibtAmount * 7,
            usersData.ibtBalancePTContract_1,
            100,
            "IBT Balance of PT Contract after withdrawIBT is wrong"
        );
        assertApproxEqAbs(
            usersData.ptBalanceTestUser1_2 + principalToken.previewDeposit(amount * 4),
            usersData.ptBalanceTestUser1_1,
            100,
            "PT Balance of Test User 1 after withdrawIBT is wrong"
        );
        assertApproxEqAbs(
            usersData.ptBalanceTestUser2_2 + principalToken.previewDeposit(amount * 3),
            usersData.ptBalanceTestUser2_1,
            100,
            "PT Balance of Test User 2 after withdrawIBT is wrong"
        );
        assertEq(
            usersData.ptBalanceTestUser3_2,
            usersData.ptBalanceTestUser3_1,
            "PT Balance of Test User 3 after withdrawIBT is wrong"
        );
        assertApproxEqAbs(
            usersData.ytBalanceTestUser1_2 + principalToken.previewDeposit(amount * 4),
            usersData.ytBalanceTestUser1_1,
            100,
            "YieldToken Balance of Test User 1 after withdrawIBT is wrong"
        );
        assertApproxEqAbs(
            usersData.ytBalanceTestUser2_2 + principalToken.previewDeposit(amount * 3),
            usersData.ytBalanceTestUser2_1,
            100,
            "YieldToken Balance of Test User 2 after withdrawIBT is wrong"
        );
        assertApproxEqAbs(
            usersData.ytBalanceTestUser3_2,
            usersData.ytBalanceTestUser3_1,
            100,
            "YieldToken Balance of Test User 3 after withdrawIBT is wrong"
        );

        // stop pranking user 1
        vm.stopPrank();
    }

    /* INTERNAL */

    /**
     * @dev Internal function for testing basic PT deposit functionality
     * @param assets Amount of assets to deposit
     * @param sender Address of the sender
     * @param receiver Address of the receiver
     * @return Amount of shares received
     */
    function _testDeposit1(
        uint256 assets,
        address sender,
        address receiver
    ) internal returns (uint256) {
        DepositWithdrawRedeemData memory depositData;
        // data before
        depositData.underlyingBalanceSenderBefore = underlying.balanceOf(sender);
        depositData.ptBalanceSenderBefore = principalToken.balanceOf(sender);
        depositData.ytBalanceSenderBefore = yt.balanceOf(sender);
        depositData.underlyingBalanceReceiverBefore = underlying.balanceOf(receiver);
        depositData.ptBalanceReceiverBefore = principalToken.balanceOf(receiver);
        depositData.ytBalanceReceiverBefore = yt.balanceOf(receiver);
        depositData.ibtBalancePTContractBefore = ibt.balanceOf(address(principalToken));
        // data global
        depositData.expectedShares1 = principalToken.convertToPrincipal(assets);
        depositData.expectedShares2 = principalToken.previewDeposit(assets);
        depositData.assetsInIBT = ibt.convertToShares(assets);
        // deposit
        if (depositData.expectedShares2 == 0) {
            vm.expectRevert();
        }
        depositData.receivedShares = principalToken.deposit(assets, receiver);
        // data after
        depositData.underlyingBalanceSenderAfter = underlying.balanceOf(sender);
        depositData.ptBalanceSenderAfter = principalToken.balanceOf(sender);
        depositData.ytBalanceSenderAfter = yt.balanceOf(sender);
        depositData.underlyingBalanceReceiverAfter = underlying.balanceOf(receiver);
        depositData.ptBalanceReceiverAfter = principalToken.balanceOf(receiver);
        depositData.ytBalanceReceiverAfter = yt.balanceOf(receiver);
        depositData.ibtBalancePTContractAfter = ibt.balanceOf(address(principalToken));
        // assertions
        if (depositData.expectedShares2 == 0) {
            assertApproxEqAbs(
                depositData.receivedShares,
                0,
                0,
                "Received shares from deposit are not as expected (_testDeposit1: convertToShares - expected shares == 0)"
            );
            assertApproxEqAbs(
                depositData.receivedShares,
                0,
                0,
                "Received shares from deposit are not as expected (_testDeposit1: previewDeposit - expected shares == 0)"
            );
            assertEq(
                depositData.underlyingBalanceSenderBefore,
                depositData.underlyingBalanceSenderAfter,
                "Underlying balance of sender after deposit is wrong"
            );
            assertEq(
                depositData.underlyingBalanceReceiverBefore,
                depositData.underlyingBalanceReceiverAfter,
                "Underlying balance of receiver after deposit is wrong"
            );
            assertEq(
                depositData.ptBalanceSenderAfter,
                depositData.ptBalanceSenderBefore,
                "PT balance of sender after deposit is wrong"
            );
            assertApproxEqAbs(
                depositData.ptBalanceReceiverAfter,
                depositData.ptBalanceReceiverBefore,
                0,
                "PT balance of receiver after deposit is wrong"
            );
            assertEq(
                depositData.ytBalanceSenderAfter,
                depositData.ytBalanceSenderBefore,
                "YieldToken balance of sender after deposit is wrong"
            );
            assertApproxEqAbs(
                depositData.ytBalanceReceiverAfter,
                depositData.ytBalanceReceiverBefore,
                0,
                "YieldToken balance of receiver after deposit is wrong"
            );
            assertApproxEqAbs(
                depositData.ibtBalancePTContractAfter,
                depositData.ibtBalancePTContractBefore,
                0,
                "IBT balance of PT contract after deposit is wrong"
            );
        } else {
            assertApproxEqAbs(
                depositData.receivedShares,
                depositData.expectedShares1,
                100,
                "_testDeposit1: Received shares from deposit are not as expected (convertToShares)"
            );
            assertApproxEqAbs(
                depositData.receivedShares,
                depositData.expectedShares2,
                10,
                "_testDeposit1: Received shares from deposit are not as expected (previewDeposit)"
            );
            if (sender == receiver) {
                assertEq(
                    depositData.underlyingBalanceSenderBefore,
                    depositData.underlyingBalanceSenderAfter + assets,
                    "Underlying balance of sender/receiver after deposit is wrong"
                );
                assertApproxEqAbs(
                    depositData.ptBalanceSenderAfter,
                    depositData.ptBalanceSenderBefore + depositData.receivedShares,
                    0,
                    "PT balance of sender/receiver after deposit is wrong"
                );
                assertApproxEqAbs(
                    depositData.ytBalanceSenderAfter,
                    depositData.ytBalanceSenderBefore + depositData.receivedShares,
                    0,
                    "YieldToken balance of sender/receiver after deposit is wrong"
                );
            } else {
                assertEq(
                    depositData.underlyingBalanceSenderBefore,
                    depositData.underlyingBalanceSenderAfter + assets,
                    "Underlying balance of sender after deposit is wrong"
                );
                assertEq(
                    depositData.underlyingBalanceReceiverBefore,
                    depositData.underlyingBalanceReceiverAfter,
                    "Underlying balance of receiver after deposit is wrong"
                );
                assertEq(
                    depositData.ptBalanceSenderAfter,
                    depositData.ptBalanceSenderBefore,
                    "PT balance of sender after deposit is wrong"
                );
                assertApproxEqAbs(
                    depositData.ptBalanceReceiverAfter,
                    depositData.ptBalanceReceiverBefore + depositData.receivedShares,
                    0,
                    "PT balance of receiver after deposit is wrong"
                );
                assertEq(
                    depositData.ytBalanceSenderAfter,
                    depositData.ytBalanceSenderBefore,
                    "YieldToken balance of sender after deposit is wrong"
                );
                assertApproxEqAbs(
                    depositData.ytBalanceReceiverAfter,
                    depositData.ytBalanceReceiverBefore + depositData.receivedShares,
                    0,
                    "YieldToken balance of receiver after deposit is wrong"
                );
            }
            assertApproxEqAbs(
                depositData.ibtBalancePTContractAfter,
                depositData.ibtBalancePTContractBefore + depositData.assetsInIBT,
                0,
                "IBT balance of PT contract after deposit is wrong"
            );
        }
        return depositData.receivedShares;
    }

    /**
     * @dev Internal function for testing PT deposit functionality with PT and YieldToken receivers
     * @param assets Amount of assets to deposit
     * @param sender Address of the depositer
     * @param ptReceiver Address of the PT receiver
     * @param ytReceiver Address of the YieldToken receiver
     * @param minShares If false calls deposit function without min shares, with otherwise
     * @return Amount of shares received
     */
    function _testDeposit2(
        uint256 assets,
        address sender,
        address ptReceiver,
        address ytReceiver,
        bool minShares
    ) internal returns (uint256) {
        DepositWithdrawRedeemData memory depositData;
        // data before
        depositData.underlyingBalanceSenderBefore = underlying.balanceOf(sender);
        depositData.ptBalanceSenderBefore = principalToken.balanceOf(sender);
        depositData.ytBalanceSenderBefore = yt.balanceOf(sender);
        depositData.underlyingBalancePTReceiverBefore = underlying.balanceOf(ptReceiver);
        depositData.ptBalancePTReceiverBefore = principalToken.balanceOf(ptReceiver);
        depositData.ytBalancePTReceiverBefore = yt.balanceOf(ptReceiver);
        depositData.underlyingBalanceYTReceiverBefore = underlying.balanceOf(ytReceiver);
        depositData.ptBalanceYTReceiverBefore = principalToken.balanceOf(ytReceiver);
        depositData.ytBalanceYTReceiverBefore = yt.balanceOf(ytReceiver);
        depositData.ibtBalancePTContractBefore = ibt.balanceOf(address(principalToken));
        // data global
        depositData.expectedShares1 = principalToken.convertToPrincipal(assets);
        depositData.expectedShares2 = principalToken.previewDeposit(assets);
        depositData.assetsInIBT = ibt.convertToShares(assets);
        // deposit
        bytes memory revertData;
        if (minShares) {
            if (depositData.expectedShares2 == 0) {
                revertData = abi.encodeWithSignature("RateError()");
                vm.expectRevert(revertData);
                principalToken.deposit(
                    assets,
                    ptReceiver,
                    ytReceiver,
                    depositData.expectedShares2 + 10
                );
            } else {
                revertData = abi.encodeWithSignature("ERC5143SlippageProtectionFailed()");
                vm.expectRevert(revertData);
                principalToken.deposit(
                    assets,
                    ptReceiver,
                    ytReceiver,
                    depositData.expectedShares2 + 10
                );
                if (depositData.expectedShares2 > 100) {
                    depositData.receivedShares = principalToken.deposit(
                        assets,
                        ptReceiver,
                        ytReceiver,
                        depositData.expectedShares2 - 100
                    );
                } else {
                    depositData.receivedShares = principalToken.deposit(
                        assets,
                        ptReceiver,
                        ytReceiver,
                        depositData.expectedShares2 - 1
                    );
                }
            }
        } else {
            if (depositData.expectedShares2 == 0) {
                revertData = abi.encodeWithSignature("RateError()");
                vm.expectRevert(revertData);
                principalToken.deposit(assets, ptReceiver, ytReceiver);
            } else {
                depositData.receivedShares = principalToken.deposit(assets, ptReceiver, ytReceiver);
            }
        }
        // data after
        depositData.underlyingBalanceSenderAfter = underlying.balanceOf(sender);
        depositData.ptBalanceSenderAfter = principalToken.balanceOf(sender);
        depositData.ytBalanceSenderAfter = yt.balanceOf(sender);
        depositData.underlyingBalancePTReceiverAfter = underlying.balanceOf(ptReceiver);
        depositData.ptBalancePTReceiverAfter = principalToken.balanceOf(ptReceiver);
        depositData.ytBalancePTReceiverAfter = yt.balanceOf(ptReceiver);
        depositData.underlyingBalanceYTReceiverAfter = underlying.balanceOf(ytReceiver);
        depositData.ptBalanceYTReceiverAfter = principalToken.balanceOf(ytReceiver);
        depositData.ytBalanceYTReceiverAfter = yt.balanceOf(ytReceiver);
        depositData.ibtBalancePTContractAfter = ibt.balanceOf(address(principalToken));
        // assertions
        if (depositData.expectedShares2 == 0) {
            assertApproxEqAbs(
                depositData.receivedShares,
                0,
                0,
                "Received shares from deposit are not as expected (_testDeposit2: convertToShares - expected shares == 0)"
            );
            assertApproxEqAbs(
                depositData.receivedShares,
                0,
                0,
                "Received shares from deposit are not as expected (_testDeposit2: previewDeposit - expected shares == 0)"
            );
            assertEq(
                depositData.underlyingBalanceSenderBefore,
                depositData.underlyingBalanceSenderAfter,
                "Underlying balance of sender after deposit is wrong"
            );
            assertEq(
                depositData.underlyingBalancePTReceiverBefore,
                depositData.underlyingBalancePTReceiverAfter,
                "Underlying balance of PT receiver after deposit is wrong"
            );
            assertEq(
                depositData.underlyingBalanceYTReceiverBefore,
                depositData.underlyingBalanceYTReceiverAfter,
                "Underlying balance of YieldToken receiver after deposit is wrong"
            );
            assertEq(
                depositData.ptBalanceSenderAfter,
                depositData.ptBalanceSenderBefore,
                "PT balance of sender after deposit is wrong"
            );
            assertApproxEqAbs(
                depositData.ptBalancePTReceiverAfter,
                depositData.ptBalancePTReceiverBefore,
                0,
                "PT balance of PT receiver after deposit is wrong"
            );
            assertEq(
                depositData.ptBalanceYTReceiverAfter,
                depositData.ptBalanceYTReceiverBefore,
                "PT balance of YieldToken receiver after deposit is wrong"
            );
            assertEq(
                depositData.ytBalanceSenderAfter,
                depositData.ytBalanceSenderBefore,
                "YieldToken balance of sender after deposit is wrong"
            );
            assertEq(
                depositData.ytBalancePTReceiverAfter,
                depositData.ytBalancePTReceiverBefore,
                "YieldToken balance of PT receiver after deposit is wrong"
            );
            assertApproxEqAbs(
                depositData.ytBalanceYTReceiverAfter,
                depositData.ytBalanceYTReceiverBefore,
                0,
                "YieldToken balance of YieldToken receiver after deposit is wrong"
            );
            assertApproxEqAbs(
                depositData.ibtBalancePTContractAfter,
                depositData.ibtBalancePTContractBefore,
                0,
                "IBT balance of PT contract after deposit is wrong"
            );
        } else {
            assertApproxEqAbs(
                depositData.receivedShares,
                depositData.expectedShares1,
                100,
                "_testDeposit2: Received shares from deposit are not as expected (convertToShares)"
            );
            assertApproxEqAbs(
                depositData.receivedShares,
                depositData.expectedShares2,
                10,
                "_testDeposit2: Received shares from deposit are not as expected (previewDeposit)"
            );
            if (sender == ptReceiver && sender == ytReceiver) {
                assertEq(
                    depositData.underlyingBalanceSenderBefore,
                    depositData.underlyingBalanceSenderAfter + assets,
                    "Underlying balance of sender/receiver after deposit is wrong"
                );
                assertApproxEqAbs(
                    depositData.ptBalanceSenderAfter,
                    depositData.ptBalanceSenderBefore + depositData.receivedShares,
                    0,
                    "PT balance of sender/receiver after deposit is wrong"
                );
                assertApproxEqAbs(
                    depositData.ytBalanceSenderAfter,
                    depositData.ytBalanceSenderBefore + depositData.receivedShares,
                    0,
                    "YieldToken balance of sender/receiver after deposit is wrong"
                );
            } else if (sender == ptReceiver) {
                assertEq(
                    depositData.underlyingBalanceSenderBefore,
                    depositData.underlyingBalanceSenderAfter + assets,
                    "Underlying balance of sender after deposit is wrong"
                );
                assertEq(
                    depositData.underlyingBalancePTReceiverBefore,
                    depositData.underlyingBalancePTReceiverAfter + assets,
                    "Underlying balance of PT receiver after deposit is wrong"
                );
                assertEq(
                    depositData.underlyingBalanceYTReceiverBefore,
                    depositData.underlyingBalanceYTReceiverAfter,
                    "Underlying balance of YieldToken receiver after deposit is wrong"
                );
                assertApproxEqAbs(
                    depositData.ptBalanceSenderAfter,
                    depositData.ptBalanceSenderBefore + depositData.receivedShares,
                    0,
                    "PT balance of sender after deposit is wrong"
                );
                assertApproxEqAbs(
                    depositData.ptBalancePTReceiverAfter,
                    depositData.ptBalancePTReceiverBefore + depositData.receivedShares,
                    0,
                    "PT balance of PT receiver after deposit is wrong"
                );
                assertEq(
                    depositData.ptBalanceYTReceiverAfter,
                    depositData.ptBalanceYTReceiverBefore,
                    "PT balance of YieldToken receiver after deposit is wrong"
                );
                assertEq(
                    depositData.ytBalanceSenderAfter,
                    depositData.ytBalanceSenderBefore,
                    "YieldToken balance of sender after deposit is wrong"
                );
                assertEq(
                    depositData.ytBalancePTReceiverAfter,
                    depositData.ytBalancePTReceiverBefore,
                    "YieldToken balance of PT receiver after deposit is wrong"
                );
                assertApproxEqAbs(
                    depositData.ytBalanceYTReceiverAfter,
                    depositData.ytBalanceYTReceiverBefore + depositData.receivedShares,
                    0,
                    "YieldToken balance of YieldToken receiver after deposit is wrong"
                );
            } else if (sender == ytReceiver) {
                assertEq(
                    depositData.underlyingBalanceSenderBefore,
                    depositData.underlyingBalanceSenderAfter + assets,
                    "Underlying balance of sender after deposit is wrong"
                );
                assertEq(
                    depositData.underlyingBalancePTReceiverBefore,
                    depositData.underlyingBalancePTReceiverAfter,
                    "Underlying balance of PT receiver after deposit is wrong"
                );
                assertEq(
                    depositData.underlyingBalanceYTReceiverBefore,
                    depositData.underlyingBalanceYTReceiverAfter + assets,
                    "Underlying balance of YieldToken receiver after deposit is wrong"
                );
                assertEq(
                    depositData.ptBalanceSenderAfter,
                    depositData.ptBalanceSenderBefore,
                    "PT balance of sender after deposit is wrong"
                );
                assertApproxEqAbs(
                    depositData.ptBalancePTReceiverAfter,
                    depositData.ptBalancePTReceiverBefore + depositData.receivedShares,
                    0,
                    "PT balance of PT receiver after deposit is wrong"
                );
                assertEq(
                    depositData.ptBalanceYTReceiverAfter,
                    depositData.ptBalanceYTReceiverBefore,
                    "PT balance of YieldToken receiver after deposit is wrong"
                );
                assertApproxEqAbs(
                    depositData.ytBalanceSenderAfter,
                    depositData.ytBalanceSenderBefore + depositData.receivedShares,
                    0,
                    "YieldToken balance of sender after deposit is wrong"
                );
                assertEq(
                    depositData.ytBalancePTReceiverAfter,
                    depositData.ytBalancePTReceiverBefore,
                    "YieldToken balance of PT receiver after deposit is wrong"
                );
                assertApproxEqAbs(
                    depositData.ytBalanceYTReceiverAfter,
                    depositData.ytBalanceYTReceiverBefore + depositData.receivedShares,
                    0,
                    "YieldToken balance of YieldToken receiver after deposit is wrong"
                );
            } else if (ptReceiver == ytReceiver) {
                assertEq(
                    depositData.underlyingBalanceSenderBefore,
                    depositData.underlyingBalanceSenderAfter + assets,
                    "Underlying balance of sender after deposit is wrong"
                );
                assertEq(
                    depositData.underlyingBalancePTReceiverBefore,
                    depositData.underlyingBalancePTReceiverAfter,
                    "Underlying balance of PT/YieldToken receiver after deposit is wrong"
                );
                assertEq(
                    depositData.ptBalanceSenderAfter,
                    depositData.ptBalanceSenderBefore,
                    "PT balance of sender after deposit is wrong"
                );
                assertApproxEqAbs(
                    depositData.ptBalancePTReceiverAfter,
                    depositData.ptBalancePTReceiverBefore + depositData.receivedShares,
                    0,
                    "PT balance of PT/YieldToken receiver after deposit is wrong"
                );
                assertEq(
                    depositData.ytBalanceSenderAfter,
                    depositData.ytBalanceSenderBefore,
                    "YieldToken balance of sender after deposit is wrong"
                );
                assertApproxEqAbs(
                    depositData.ytBalanceYTReceiverAfter,
                    depositData.ytBalanceYTReceiverBefore + depositData.receivedShares,
                    0,
                    "YieldToken balance of PT/YieldToken receiver after deposit is wrong"
                );
            } else {
                assertEq(
                    depositData.underlyingBalanceSenderBefore,
                    depositData.underlyingBalanceSenderAfter + assets,
                    "Underlying balance of sender after deposit is wrong"
                );
                assertEq(
                    depositData.underlyingBalancePTReceiverBefore,
                    depositData.underlyingBalancePTReceiverAfter,
                    "Underlying balance of PT receiver after deposit is wrong"
                );
                assertEq(
                    depositData.underlyingBalanceYTReceiverBefore,
                    depositData.underlyingBalanceYTReceiverAfter,
                    "Underlying balance of YieldToken receiver after deposit is wrong"
                );
                assertEq(
                    depositData.ptBalanceSenderAfter,
                    depositData.ptBalanceSenderBefore,
                    "PT balance of sender after deposit is wrong"
                );
                assertApproxEqAbs(
                    depositData.ptBalancePTReceiverAfter,
                    depositData.ptBalancePTReceiverBefore + depositData.receivedShares,
                    0,
                    "PT balance of PT receiver after deposit is wrong"
                );
                assertEq(
                    depositData.ptBalanceYTReceiverAfter,
                    depositData.ptBalanceYTReceiverBefore,
                    "PT balance of YieldToken receiver after deposit is wrong"
                );
                assertEq(
                    depositData.ytBalanceSenderAfter,
                    depositData.ytBalanceSenderBefore,
                    "YieldToken balance of sender after deposit is wrong"
                );
                assertEq(
                    depositData.ytBalancePTReceiverAfter,
                    depositData.ytBalancePTReceiverBefore,
                    "YieldToken balance of PT receiver after deposit is wrong"
                );
                assertApproxEqAbs(
                    depositData.ytBalanceYTReceiverAfter,
                    depositData.ytBalanceYTReceiverBefore + depositData.receivedShares,
                    0,
                    "YieldToken balance of YieldToken receiver after deposit is wrong"
                );
            }
            assertApproxEqAbs(
                depositData.ibtBalancePTContractAfter,
                depositData.ibtBalancePTContractBefore + depositData.assetsInIBT,
                0,
                "IBT balance of PT contract after deposit is wrong"
            );
        }
        return depositData.receivedShares;
    }

    /**
     * @dev Internal function for testing basic PT deposit with IBT functionality
     * @param ibts Amount of IBT to deposit
     * @param sender Address of the sender
     * @param receiver Address of the receiver
     * @return Amount of shares received
     */
    function _testDeposit3(
        uint256 ibts,
        address sender,
        address receiver
    ) internal returns (uint256) {
        DepositWithdrawRedeemData memory depositData;
        // data before
        depositData.underlyingBalanceSenderBefore = underlying.balanceOf(sender);
        depositData.ibtBalanceSenderBefore = ibt.balanceOf(sender);
        depositData.ptBalanceSenderBefore = principalToken.balanceOf(sender);
        depositData.ytBalanceSenderBefore = yt.balanceOf(sender);
        depositData.underlyingBalanceReceiverBefore = underlying.balanceOf(receiver);
        depositData.ptBalanceReceiverBefore = principalToken.balanceOf(receiver);
        depositData.ytBalanceReceiverBefore = yt.balanceOf(receiver);
        depositData.ibtBalancePTContractBefore = ibt.balanceOf(address(principalToken));
        // data global
        depositData.expectedShares1 = principalToken.convertToPrincipal(ibt.convertToAssets(ibts));
        depositData.expectedShares2 = principalToken.previewDepositIBT(ibts);
        // deposit
        if (depositData.expectedShares2 == 0) {
            vm.expectRevert();
        }
        depositData.receivedShares = principalToken.depositIBT(ibts, receiver);
        // data after
        depositData.underlyingBalanceSenderAfter = underlying.balanceOf(sender);
        depositData.ibtBalanceSenderAfter = ibt.balanceOf(sender);
        depositData.ptBalanceSenderAfter = principalToken.balanceOf(sender);
        depositData.ytBalanceSenderAfter = yt.balanceOf(sender);
        depositData.underlyingBalanceReceiverAfter = underlying.balanceOf(receiver);
        depositData.ptBalanceReceiverAfter = principalToken.balanceOf(receiver);
        depositData.ytBalanceReceiverAfter = yt.balanceOf(receiver);
        depositData.ibtBalancePTContractAfter = ibt.balanceOf(address(principalToken));
        // assertions
        if (depositData.expectedShares2 == 0) {
            assertApproxEqAbs(
                depositData.receivedShares,
                0,
                0,
                "Received shares from depositWithIBT are not as expected (convertToShares)"
            );
            assertApproxEqAbs(
                depositData.receivedShares,
                0,
                0,
                "Received shares from depositWithIBT are not as expected (previewDeposit)"
            );
            assertEq(
                depositData.underlyingBalanceSenderBefore,
                depositData.underlyingBalanceSenderAfter,
                "Underlying balance of sender after depositWithIBT is wrong"
            );
            assertEq(
                depositData.ibtBalanceSenderBefore,
                depositData.ibtBalanceSenderAfter,
                "IBT balance of sender after depositWithIBT is wrong"
            );
            assertEq(
                depositData.underlyingBalanceReceiverBefore,
                depositData.underlyingBalanceReceiverAfter,
                "Underlying balance of receiver after depositWithIBT is wrong"
            );
            assertEq(
                depositData.ptBalanceSenderAfter,
                depositData.ptBalanceSenderBefore,
                "PT balance of sender after depositWithIBT is wrong"
            );
            assertApproxEqAbs(
                depositData.ptBalanceReceiverAfter,
                depositData.ptBalanceReceiverBefore,
                0,
                "PT balance of receiver after depositWithIBT is wrong"
            );
            assertEq(
                depositData.ytBalanceSenderAfter,
                depositData.ytBalanceSenderBefore,
                "YieldToken balance of sender after depositWithIBT is wrong"
            );
            assertApproxEqAbs(
                depositData.ytBalanceReceiverAfter,
                depositData.ytBalanceReceiverBefore,
                0,
                "YieldToken balance of receiver after depositWithIBT is wrong"
            );
            assertApproxEqAbs(
                depositData.ibtBalancePTContractAfter,
                depositData.ibtBalancePTContractBefore,
                0,
                "IBT balance of PT contract after depositWithIBT is wrong"
            );
        } else {
            assertApproxEqAbs(
                depositData.receivedShares,
                depositData.expectedShares1,
                0,
                "Received shares from depositWithIBT are not as expected (convertToShares)"
            );
            assertApproxEqAbs(
                depositData.receivedShares,
                depositData.expectedShares2,
                0,
                "Received shares from depositWithIBT are not as expected (previewDeposit)"
            );
            if (sender == receiver) {
                assertEq(
                    depositData.underlyingBalanceSenderBefore,
                    depositData.underlyingBalanceSenderAfter,
                    "Underlying balance of sender/receiver after depositWithIBT is wrong"
                );
                assertEq(
                    depositData.ibtBalanceSenderBefore,
                    depositData.ibtBalanceSenderAfter + ibts,
                    "IBT balance of sender/receiver after depositWithIBT is wrong"
                );
                assertApproxEqAbs(
                    depositData.ptBalanceSenderAfter,
                    depositData.ptBalanceSenderBefore + depositData.receivedShares,
                    0,
                    "PT balance of sender/receiver after depositWithIBT is wrong"
                );
                assertApproxEqAbs(
                    depositData.ytBalanceSenderAfter,
                    depositData.ytBalanceSenderBefore + depositData.receivedShares,
                    0,
                    "YieldToken balance of sender/receiver after depositWithIBT is wrong"
                );
            } else {
                assertEq(
                    depositData.underlyingBalanceSenderBefore,
                    depositData.underlyingBalanceSenderAfter,
                    "Underlying balance of sender after depositWithIBT is wrong"
                );
                assertEq(
                    depositData.ibtBalanceSenderBefore,
                    depositData.ibtBalanceSenderAfter + ibts,
                    "IBT balance of sender after depositWithIBT is wrong"
                );
                assertEq(
                    depositData.underlyingBalanceReceiverBefore,
                    depositData.underlyingBalanceReceiverAfter,
                    "Underlying balance of receiver after depositWithIBT is wrong"
                );
                assertEq(
                    depositData.ptBalanceSenderAfter,
                    depositData.ptBalanceSenderBefore,
                    "PT balance of sender after depositWithIBT is wrong"
                );
                assertApproxEqAbs(
                    depositData.ptBalanceReceiverAfter,
                    depositData.ptBalanceReceiverBefore + depositData.receivedShares,
                    0,
                    "PT balance of receiver after depositWithIBT is wrong"
                );
                assertEq(
                    depositData.ytBalanceSenderAfter,
                    depositData.ytBalanceSenderBefore,
                    "YieldToken balance of sender after depositWithIBT is wrong"
                );
                assertApproxEqAbs(
                    depositData.ytBalanceReceiverAfter,
                    depositData.ytBalanceReceiverBefore + depositData.receivedShares,
                    0,
                    "YieldToken balance of receiver after depositWithIBT is wrong"
                );
            }
            assertApproxEqAbs(
                depositData.ibtBalancePTContractAfter,
                depositData.ibtBalancePTContractBefore + ibts,
                0,
                "IBT balance of PT contract after depositWithIBT is wrong"
            );
        }
        return depositData.receivedShares;
    }

    /**
     * @dev Internal function for testing PT deposit with IBT functionality with PT and YieldToken receivers
     * @param ibts Amount of IBT to deposit
     * @param sender Address of the depositer
     * @param ptReceiver Address of the PT receiver
     * @param ytReceiver Address of the YieldToken receiver
     * @param minShares If false calls deposit function without min shares, with otherwise
     * @return Amount of shares received
     */
    function _testDeposit4(
        uint256 ibts,
        address sender,
        address ptReceiver,
        address ytReceiver,
        bool minShares
    ) internal returns (uint256) {
        DepositWithdrawRedeemData memory depositData;
        // data before
        depositData.underlyingBalanceSenderBefore = underlying.balanceOf(sender);
        depositData.ibtBalanceSenderBefore = ibt.balanceOf(sender);
        depositData.ptBalanceSenderBefore = principalToken.balanceOf(sender);
        depositData.ytBalanceSenderBefore = yt.balanceOf(sender);
        depositData.underlyingBalancePTReceiverBefore = underlying.balanceOf(ptReceiver);
        depositData.ptBalancePTReceiverBefore = principalToken.balanceOf(ptReceiver);
        depositData.ytBalancePTReceiverBefore = yt.balanceOf(ptReceiver);
        depositData.underlyingBalanceYTReceiverBefore = underlying.balanceOf(ytReceiver);
        depositData.ptBalanceYTReceiverBefore = principalToken.balanceOf(ytReceiver);
        depositData.ytBalanceYTReceiverBefore = yt.balanceOf(ytReceiver);
        depositData.ibtBalancePTContractBefore = ibt.balanceOf(address(principalToken));
        // data global
        depositData.expectedShares1 = principalToken.convertToPrincipal(ibt.convertToAssets(ibts));
        depositData.expectedShares2 = principalToken.previewDepositIBT(ibts);
        // deposit
        bytes memory revertData;
        if (minShares) {
            if (depositData.expectedShares2 == 0) {
                revertData = abi.encodeWithSignature("RateError()");
                vm.expectRevert(revertData);
                principalToken.depositIBT(
                    ibts,
                    ptReceiver,
                    ytReceiver,
                    depositData.expectedShares1 + 1
                );
            } else {
                revertData = abi.encodeWithSignature("ERC5143SlippageProtectionFailed()");
                vm.expectRevert(revertData);
                principalToken.depositIBT(
                    ibts,
                    ptReceiver,
                    ytReceiver,
                    depositData.expectedShares1 + 1
                );
                depositData.receivedShares = principalToken.depositIBT(
                    ibts,
                    ptReceiver,
                    ytReceiver,
                    depositData.expectedShares1
                );
            }
        } else {
            if (depositData.expectedShares2 == 0) {
                revertData = abi.encodeWithSignature("RateError()");
                vm.expectRevert(revertData);
                principalToken.depositIBT(ibts, ptReceiver, ytReceiver);
            } else {
                depositData.receivedShares = principalToken.depositIBT(
                    ibts,
                    ptReceiver,
                    ytReceiver
                );
            }
        }
        // data after
        depositData.underlyingBalanceSenderAfter = underlying.balanceOf(sender);
        depositData.ibtBalanceSenderAfter = ibt.balanceOf(sender);
        depositData.ptBalanceSenderAfter = principalToken.balanceOf(sender);
        depositData.ytBalanceSenderAfter = yt.balanceOf(sender);
        depositData.underlyingBalancePTReceiverAfter = underlying.balanceOf(ptReceiver);
        depositData.ptBalancePTReceiverAfter = principalToken.balanceOf(ptReceiver);
        depositData.ytBalancePTReceiverAfter = yt.balanceOf(ptReceiver);
        depositData.underlyingBalanceYTReceiverAfter = underlying.balanceOf(ytReceiver);
        depositData.ptBalanceYTReceiverAfter = principalToken.balanceOf(ytReceiver);
        depositData.ytBalanceYTReceiverAfter = yt.balanceOf(ytReceiver);
        depositData.ibtBalancePTContractAfter = ibt.balanceOf(address(principalToken));
        // assertions
        if (depositData.expectedShares2 == 0) {
            assertApproxEqAbs(
                depositData.receivedShares,
                0,
                0,
                "Received shares from depositWithIBT are not as expected (convertToShares)"
            );
            assertApproxEqAbs(
                depositData.receivedShares,
                0,
                0,
                "Received shares from depositWithIBT are not as expected (previewDeposit)"
            );
            assertEq(
                depositData.underlyingBalanceSenderBefore,
                depositData.underlyingBalanceSenderAfter,
                "Underlying balance of sender after depositWithIBT is wrong"
            );
            assertEq(
                depositData.ibtBalanceSenderBefore,
                depositData.ibtBalanceSenderAfter,
                "IBT balance of sender after depositWithIBT is wrong"
            );
            assertEq(
                depositData.underlyingBalancePTReceiverBefore,
                depositData.underlyingBalancePTReceiverAfter,
                "Underlying balance of PT receiver after depositWithIBT is wrong"
            );
            assertEq(
                depositData.underlyingBalanceYTReceiverBefore,
                depositData.underlyingBalanceYTReceiverAfter,
                "Underlying balance of YieldToken receiver after depositWithIBT is wrong"
            );
            assertEq(
                depositData.ptBalanceSenderAfter,
                depositData.ptBalanceSenderBefore,
                "PT balance of sender after depositWithIBT is wrong"
            );
            assertApproxEqAbs(
                depositData.ptBalancePTReceiverAfter,
                depositData.ptBalancePTReceiverBefore,
                0,
                "PT balance of PT receiver after depositWithIBT is wrong"
            );
            assertEq(
                depositData.ptBalanceYTReceiverAfter,
                depositData.ptBalanceYTReceiverBefore,
                "PT balance of YieldToken receiver after depositWithIBT is wrong"
            );
            assertEq(
                depositData.ytBalanceSenderAfter,
                depositData.ytBalanceSenderBefore,
                "YieldToken balance of sender after depositWithIBT is wrong"
            );
            assertEq(
                depositData.ytBalancePTReceiverAfter,
                depositData.ytBalancePTReceiverBefore,
                "YieldToken balance of PT receiver after depositWithIBT is wrong"
            );
            assertApproxEqAbs(
                depositData.ytBalanceYTReceiverAfter,
                depositData.ytBalanceYTReceiverBefore,
                0,
                "YieldToken balance of YieldToken receiver after depositWithIBT is wrong"
            );
            assertApproxEqAbs(
                depositData.ibtBalancePTContractAfter,
                depositData.ibtBalancePTContractBefore,
                0,
                "IBT balance of PT contract after depositWithIBT is wrong"
            );
        } else {
            assertApproxEqAbs(
                depositData.receivedShares,
                depositData.expectedShares1,
                0,
                "Received shares from depositWithIBT are not as expected (convertToShares)"
            );
            assertApproxEqAbs(
                depositData.receivedShares,
                depositData.expectedShares2,
                0,
                "Received shares from depositWithIBT are not as expected (previewDeposit)"
            );
            if (sender == ptReceiver && sender == ytReceiver) {
                assertEq(
                    depositData.underlyingBalanceSenderBefore,
                    depositData.underlyingBalanceSenderAfter,
                    "Underlying balance of sender/receiver after depositWithIBT is wrong"
                );
                assertEq(
                    depositData.ibtBalanceSenderBefore,
                    depositData.ibtBalanceSenderAfter + ibts,
                    "IBT balance of sender/receiver after depositWithIBT is wrong"
                );
                assertApproxEqAbs(
                    depositData.ptBalanceSenderAfter,
                    depositData.ptBalanceSenderBefore + depositData.receivedShares,
                    0,
                    "PT balance of sender/receiver after depositWithIBT is wrong"
                );
                assertApproxEqAbs(
                    depositData.ytBalanceSenderAfter,
                    depositData.ytBalanceSenderBefore + depositData.receivedShares,
                    0,
                    "YieldToken balance of sender/receiver after depositWithIBT is wrong"
                );
            } else if (sender == ptReceiver) {
                assertEq(
                    depositData.underlyingBalanceSenderBefore,
                    depositData.underlyingBalanceSenderAfter,
                    "Underlying balance of sender after depositWithIBT is wrong"
                );
                assertEq(
                    depositData.ibtBalanceSenderBefore,
                    depositData.ibtBalanceSenderAfter + ibts,
                    "IBT balance of sender after depositWithIBT is wrong"
                );
                assertEq(
                    depositData.underlyingBalanceYTReceiverBefore,
                    depositData.underlyingBalanceYTReceiverAfter,
                    "Underlying balance of YieldToken receiver after depositWithIBT is wrong"
                );
                assertApproxEqAbs(
                    depositData.ptBalanceSenderAfter,
                    depositData.ptBalanceSenderBefore + depositData.receivedShares,
                    0,
                    "PT balance of sender after depositWithIBT is wrong"
                );
                assertApproxEqAbs(
                    depositData.ptBalancePTReceiverAfter,
                    depositData.ptBalancePTReceiverBefore + depositData.receivedShares,
                    0,
                    "PT balance of PT receiver after depositWithIBT is wrong"
                );
                assertEq(
                    depositData.ptBalanceYTReceiverAfter,
                    depositData.ptBalanceYTReceiverBefore,
                    "PT balance of YieldToken receiver after depositWithIBT is wrong"
                );
                assertEq(
                    depositData.ytBalanceSenderAfter,
                    depositData.ytBalanceSenderBefore,
                    "YieldToken balance of sender after depositWithIBT is wrong"
                );
                assertEq(
                    depositData.ytBalancePTReceiverAfter,
                    depositData.ytBalancePTReceiverBefore,
                    "YieldToken balance of PT receiver after depositWithIBT is wrong"
                );
                assertApproxEqAbs(
                    depositData.ytBalanceYTReceiverAfter,
                    depositData.ytBalanceYTReceiverBefore + depositData.receivedShares,
                    0,
                    "YieldToken balance of YieldToken receiver after depositWithIBT is wrong"
                );
            } else if (sender == ytReceiver) {
                assertEq(
                    depositData.underlyingBalanceSenderBefore,
                    depositData.underlyingBalanceSenderAfter,
                    "Underlying balance of sender after depositWithIBT is wrong"
                );
                assertEq(
                    depositData.ibtBalanceSenderBefore,
                    depositData.ibtBalanceSenderAfter + ibts,
                    "IBT balance of sender after depositWithIBT is wrong"
                );
                assertEq(
                    depositData.underlyingBalancePTReceiverBefore,
                    depositData.underlyingBalancePTReceiverAfter,
                    "Underlying balance of PT receiver after depositWithIBT is wrong"
                );
                assertEq(
                    depositData.ptBalanceSenderAfter,
                    depositData.ptBalanceSenderBefore,
                    "PT balance of sender after depositWithIBT is wrong"
                );
                assertApproxEqAbs(
                    depositData.ptBalancePTReceiverAfter,
                    depositData.ptBalancePTReceiverBefore + depositData.receivedShares,
                    0,
                    "PT balance of PT receiver after depositWithIBT is wrong"
                );
                assertEq(
                    depositData.ptBalanceYTReceiverAfter,
                    depositData.ptBalanceYTReceiverBefore,
                    "PT balance of YieldToken receiver after depositWithIBT is wrong"
                );
                assertApproxEqAbs(
                    depositData.ytBalanceSenderAfter,
                    depositData.ytBalanceSenderBefore + depositData.receivedShares,
                    0,
                    "YieldToken balance of sender after depositWithIBT is wrong"
                );
                assertEq(
                    depositData.ytBalancePTReceiverAfter,
                    depositData.ytBalancePTReceiverBefore,
                    "YieldToken balance of PT receiver after depositWithIBT is wrong"
                );
                assertApproxEqAbs(
                    depositData.ytBalanceYTReceiverAfter,
                    depositData.ytBalanceYTReceiverBefore + depositData.receivedShares,
                    0,
                    "YieldToken balance of YieldToken receiver after depositWithIBT is wrong"
                );
            } else if (ptReceiver == ytReceiver) {
                assertEq(
                    depositData.underlyingBalanceSenderBefore,
                    depositData.underlyingBalanceSenderAfter,
                    "Underlying balance of sender after depositWithIBT is wrong"
                );
                assertEq(
                    depositData.ibtBalanceSenderBefore,
                    depositData.ibtBalanceSenderAfter + ibts,
                    "IBT balance of sender after depositWithIBT is wrong"
                );
                assertEq(
                    depositData.underlyingBalancePTReceiverBefore,
                    depositData.underlyingBalancePTReceiverAfter,
                    "Underlying balance of PT/YieldToken receiver after depositWithIBT is wrong"
                );
                assertEq(
                    depositData.ptBalanceSenderAfter,
                    depositData.ptBalanceSenderBefore,
                    "PT balance of sender after depositWithIBT is wrong"
                );
                assertApproxEqAbs(
                    depositData.ptBalancePTReceiverAfter,
                    depositData.ptBalancePTReceiverBefore + depositData.receivedShares,
                    0,
                    "PT balance of PT/YieldToken receiver after depositWithIBT is wrong"
                );
                assertEq(
                    depositData.ytBalanceSenderAfter,
                    depositData.ytBalanceSenderBefore,
                    "YieldToken balance of sender after deposit is wrong"
                );
                assertApproxEqAbs(
                    depositData.ytBalanceYTReceiverAfter,
                    depositData.ytBalanceYTReceiverBefore + depositData.receivedShares,
                    0,
                    "YieldToken balance of PT/YieldToken receiver after depositWithIBT is wrong"
                );
            } else {
                assertEq(
                    depositData.underlyingBalanceSenderBefore,
                    depositData.underlyingBalanceSenderAfter,
                    "Underlying balance of sender after depositWithIBT is wrong"
                );
                assertEq(
                    depositData.ibtBalanceSenderBefore,
                    depositData.ibtBalanceSenderAfter + ibts,
                    "IBT balance of sender after depositWithIBT is wrong"
                );
                assertEq(
                    depositData.underlyingBalancePTReceiverBefore,
                    depositData.underlyingBalancePTReceiverAfter,
                    "Underlying balance of PT receiver after depositWithIBT is wrong"
                );
                assertEq(
                    depositData.underlyingBalanceYTReceiverBefore,
                    depositData.underlyingBalanceYTReceiverAfter,
                    "Underlying balance of YieldToken receiver after depositWithIBT is wrong"
                );
                assertEq(
                    depositData.ptBalanceSenderAfter,
                    depositData.ptBalanceSenderBefore,
                    "PT balance of sender after depositWithIBT is wrong"
                );
                assertApproxEqAbs(
                    depositData.ptBalancePTReceiverAfter,
                    depositData.ptBalancePTReceiverBefore + depositData.receivedShares,
                    0,
                    "PT balance of PT receiver after depositWithIBT is wrong"
                );
                assertEq(
                    depositData.ptBalanceYTReceiverAfter,
                    depositData.ptBalanceYTReceiverBefore,
                    "PT balance of YieldToken receiver after depositWithIBT is wrong"
                );
                assertEq(
                    depositData.ytBalanceSenderAfter,
                    depositData.ytBalanceSenderBefore,
                    "YieldToken balance of sender after depositWithIBT is wrong"
                );
                assertEq(
                    depositData.ytBalancePTReceiverAfter,
                    depositData.ytBalancePTReceiverBefore,
                    "YieldToken balance of PT receiver after depositWithIBT is wrong"
                );
                assertApproxEqAbs(
                    depositData.ytBalanceYTReceiverAfter,
                    depositData.ytBalanceYTReceiverBefore + depositData.receivedShares,
                    0,
                    "YieldToken balance of YieldToken receiver after depositWithIBT is wrong"
                );
            }
            assertApproxEqAbs(
                depositData.ibtBalancePTContractAfter,
                depositData.ibtBalancePTContractBefore + ibts,
                0,
                "IBT balance of PT contract after depositWithIBT is wrong"
            );
        }
        return depositData.receivedShares;
    }

    /**
     * @dev Internal function for testing basic PT redeem and min assets
     * @param shares Amount of PTs to burn (after expiry no need to burn YTs)
     * @param sender Address of the user that redeems shares
     * @param receiver Address of the assets receiver
     * @param minAssets If false calls redeem function without min assets, with otherwise
     * @return assets Amount of assets received for redeeming shares
     */
    function _testRedeem1(
        uint256 shares,
        address sender,
        address receiver,
        bool minAssets
    ) internal returns (uint256 assets) {
        DepositWithdrawRedeemData memory redeemData;
        // data before
        redeemData.underlyingBalanceSenderBefore = underlying.balanceOf(sender);
        redeemData.ibtBalanceSenderBefore = ibt.balanceOf(sender);
        redeemData.ptBalanceSenderBefore = principalToken.balanceOf(sender);
        redeemData.ytBalanceSenderBefore = yt.actualBalanceOf(sender);
        redeemData.underlyingBalanceReceiverBefore = underlying.balanceOf(receiver);
        redeemData.ibtBalanceReceiverBefore = ibt.balanceOf(receiver);
        redeemData.ptBalanceReceiverBefore = principalToken.balanceOf(receiver);
        redeemData.ytBalanceReceiverBefore = yt.actualBalanceOf(receiver);
        redeemData.ibtBalancePTContractBefore = ibt.balanceOf(address(principalToken));
        // data global
        redeemData.expectedAssets1 = _convertToAssetsWithRate(
            shares,
            principalToken.getPTRate(), // After expiry this will return the PTRate stored
            Math.Rounding.Floor
        );
        redeemData.expectedAssets1 = ibt.previewRedeem(
            _convertToSharesWithRate(
                redeemData.expectedAssets1,
                principalToken.getIBTRate(), // After expiry this will return the IBTRate stored
                Math.Rounding.Floor
            )
        );
        redeemData.expectedAssets2 = principalToken.previewRedeem(shares);
        uint256 ibtRateBeforeRedeem = ibt.convertToAssets(IBT_UNIT);
        // redeem
        if (minAssets) {
            bytes memory revertData = abi.encodeWithSignature("ERC5143SlippageProtectionFailed()");
            vm.expectRevert(revertData);
            principalToken.redeem(shares, receiver, sender, redeemData.expectedAssets2 + 1);
            redeemData.receivedAssets = principalToken.redeem(
                shares,
                receiver,
                sender,
                redeemData.expectedAssets2
            );
        } else {
            redeemData.receivedAssets = principalToken.redeem(shares, receiver, sender);
        }
        redeemData.assetsInIBT = _convertToSharesWithRate(
            redeemData.receivedAssets,
            ibtRateBeforeRedeem,
            Math.Rounding.Floor
        );
        // data after
        redeemData.underlyingBalanceSenderAfter = underlying.balanceOf(sender);
        redeemData.ibtBalanceSenderAfter = ibt.balanceOf(sender);
        redeemData.ptBalanceSenderAfter = principalToken.balanceOf(sender);
        redeemData.ytBalanceSenderAfter = yt.actualBalanceOf(sender);
        redeemData.underlyingBalanceReceiverAfter = underlying.balanceOf(receiver);
        redeemData.ibtBalanceReceiverAfter = ibt.balanceOf(receiver);
        redeemData.ptBalanceReceiverAfter = principalToken.balanceOf(receiver);
        redeemData.ytBalanceReceiverAfter = yt.actualBalanceOf(receiver);
        redeemData.ibtBalancePTContractAfter = ibt.balanceOf(address(principalToken));
        // assertions
        assertApproxEqAbs(
            redeemData.receivedAssets,
            redeemData.expectedAssets1,
            100,
            "Received assets from redeem are not as expected (convertToAssets)"
        );
        assertApproxEqAbs(
            redeemData.receivedAssets,
            redeemData.expectedAssets2,
            100,
            "Received assets from redeem are not as expected (previewMint)"
        );
        if (sender == receiver) {
            assertEq(
                redeemData.underlyingBalanceSenderAfter,
                redeemData.underlyingBalanceSenderBefore + redeemData.receivedAssets,
                "Underlying balance of sender/receiver after redeem is wrong"
            );
            assertEq(
                redeemData.ibtBalanceSenderBefore,
                redeemData.ibtBalanceSenderAfter,
                "IBT balance of sender/receiver after redeem is wrong"
            );
            assertEq(
                redeemData.ptBalanceSenderBefore,
                redeemData.ptBalanceSenderAfter + shares,
                "PT balance of sender/receiver after redeem is wrong"
            );
            assertEq(
                redeemData.ytBalanceSenderBefore,
                redeemData.ytBalanceSenderAfter,
                "YieldToken balance of sender/receiver after redeem is wrong"
            );
        } else {
            assertEq(
                redeemData.underlyingBalanceSenderAfter,
                redeemData.underlyingBalanceSenderBefore,
                "Underlying balance of sender after redeem is wrong"
            );
            assertEq(
                redeemData.underlyingBalanceReceiverAfter,
                redeemData.underlyingBalanceReceiverBefore + redeemData.receivedAssets,
                "Underlying balance of receiver after redeem is wrong"
            );
            assertEq(
                redeemData.ibtBalanceSenderBefore,
                redeemData.ibtBalanceSenderAfter,
                "IBT balance of sender after redeem is wrong"
            );
            assertEq(
                redeemData.ibtBalanceReceiverBefore,
                redeemData.ibtBalanceReceiverAfter,
                "IBT balance of receiver after redeem is wrong"
            );
            assertEq(
                redeemData.ptBalanceSenderBefore,
                redeemData.ptBalanceSenderAfter + shares,
                "PT balance of sender after redeem is wrong"
            );
            assertEq(
                redeemData.ptBalanceReceiverAfter,
                redeemData.ptBalanceReceiverBefore,
                "PT balance of receiver after redeem is wrong"
            );
            assertEq(
                redeemData.ytBalanceSenderBefore,
                redeemData.ytBalanceSenderAfter,
                "YieldToken balance of sender after redeem is wrong"
            );
            assertEq(
                redeemData.ytBalanceReceiverAfter,
                redeemData.ytBalanceReceiverBefore,
                "YieldToken balance of receiver after redeem is wrong"
            );
        }
        assertApproxEqAbs(
            redeemData.ibtBalancePTContractBefore,
            redeemData.ibtBalancePTContractAfter + redeemData.assetsInIBT,
            100,
            "IBT balance of PT contract after redeem is wrong"
        );
        return redeemData.receivedAssets;
    }

    /**
     * @dev Internal function for testing basic PT withdraw and max shares
     * @param assets Amount of assets to receive
     * @param sender Address of the user that withdraws assets
     * @param receiver Address of the assets receiver
     * @param maxShares If false calls withdraw function without max shares, with otherwise
     * @return shares Amount of shares burned for withdrawing assets
     */
    function _testWithdraw1(
        uint256 assets,
        address sender,
        address receiver,
        bool maxShares
    ) internal returns (uint256 shares) {
        DepositWithdrawRedeemData memory withdrawData;
        // data before
        withdrawData.underlyingBalanceSenderBefore = underlying.balanceOf(sender);
        withdrawData.ibtBalanceSenderBefore = ibt.balanceOf(sender);
        withdrawData.ptBalanceSenderBefore = principalToken.balanceOf(sender);
        withdrawData.ytBalanceSenderBefore = yt.actualBalanceOf(sender);
        withdrawData.underlyingBalanceReceiverBefore = underlying.balanceOf(receiver);
        withdrawData.ibtBalanceReceiverBefore = ibt.balanceOf(receiver);
        withdrawData.ptBalanceReceiverBefore = principalToken.balanceOf(receiver);
        withdrawData.ytBalanceReceiverBefore = yt.actualBalanceOf(receiver);
        withdrawData.ibtBalancePTContractBefore = ibt.balanceOf(address(principalToken));
        // data global
        withdrawData.expectedShares1 = principalToken.convertToPrincipal(assets);
        withdrawData.expectedShares2 = principalToken.previewWithdraw(assets);
        withdrawData.assetsInIBT = ibt.convertToShares(assets);
        // pt's convertToAssets uses up to date pt rate
        uint256 expectedAssetsWithdrawn = principalToken.convertToUnderlying(
            withdrawData.expectedShares2
        );
        assertApproxEqAbs(expectedAssetsWithdrawn, assets, 5, "Assets withdrawn is wrong");
        // ibt's convertToShares uses up to date ibt rate
        uint256 expectedIBTWithdrawn = ibt.convertToShares(expectedAssetsWithdrawn);
        // withdraw
        if (maxShares) {
            if (withdrawData.expectedShares1 > 0) {
                bytes memory revertData = abi.encodeWithSignature(
                    "ERC5143SlippageProtectionFailed()"
                );
                vm.expectRevert(revertData);
                principalToken.withdraw(assets, receiver, sender, withdrawData.expectedShares1 - 1);
            }
            withdrawData.usedShares = principalToken.withdraw(
                assets,
                receiver,
                sender,
                withdrawData.expectedShares1
            );
        } else {
            withdrawData.usedShares = principalToken.withdraw(assets, receiver, sender);
        }

        // data after
        withdrawData.underlyingBalanceSenderAfter = underlying.balanceOf(sender);
        withdrawData.ibtBalanceSenderAfter = ibt.balanceOf(sender);
        withdrawData.ptBalanceSenderAfter = principalToken.balanceOf(sender);
        withdrawData.ytBalanceSenderAfter = yt.actualBalanceOf(sender);
        withdrawData.underlyingBalanceReceiverAfter = underlying.balanceOf(receiver);
        withdrawData.ibtBalanceReceiverAfter = ibt.balanceOf(receiver);
        withdrawData.ptBalanceReceiverAfter = principalToken.balanceOf(receiver);
        withdrawData.ytBalanceReceiverAfter = yt.actualBalanceOf(receiver);
        withdrawData.ibtBalancePTContractAfter = ibt.balanceOf(address(principalToken));
        // assertions
        assertApproxEqAbs(
            withdrawData.usedShares,
            withdrawData.expectedShares1,
            100,
            "Received assets from withdraw are not as expected (convertToShares)"
        );
        assertLe(
            withdrawData.usedShares,
            withdrawData.expectedShares1,
            "more shares were used than expected"
        );
        assertApproxEqAbs(
            withdrawData.usedShares,
            withdrawData.expectedShares2,
            100,
            "Received assets from withdraw are not as expected (previewWithdraw)"
        );
        assertLe(
            withdrawData.usedShares,
            withdrawData.expectedShares2,
            "more shares were used than expected"
        );
        if (sender == receiver) {
            assertEq(
                withdrawData.underlyingBalanceSenderAfter,
                withdrawData.underlyingBalanceSenderBefore + assets,
                "Underlying balance of sender/receiver after withdraw is wrong"
            );
            assertEq(
                withdrawData.ibtBalanceSenderBefore,
                withdrawData.ibtBalanceSenderAfter,
                "IBT balance of sender/receiver after withdraw is wrong"
            );
            assertEq(
                withdrawData.ptBalanceSenderBefore,
                withdrawData.ptBalanceSenderAfter + withdrawData.usedShares,
                "PT balance of sender/receiver after withdraw is wrong"
            );
            assertEq(
                withdrawData.ytBalanceSenderBefore,
                withdrawData.ytBalanceSenderAfter + withdrawData.usedShares,
                "YieldToken balance of sender/receiver after withdraw is wrong"
            );
        } else {
            assertEq(
                withdrawData.underlyingBalanceSenderAfter,
                withdrawData.underlyingBalanceSenderBefore,
                "Underlying balance of sender after withdraw is wrong"
            );
            assertEq(
                withdrawData.underlyingBalanceReceiverAfter,
                withdrawData.underlyingBalanceReceiverBefore + assets,
                "Underlying balance of receiver after withdraw is wrong"
            );
            assertEq(
                withdrawData.ibtBalanceSenderBefore,
                withdrawData.ibtBalanceSenderAfter,
                "IBT balance of sender after withdraw is wrong"
            );
            assertEq(
                withdrawData.ibtBalanceReceiverBefore,
                withdrawData.ibtBalanceReceiverAfter,
                "IBT balance of receiver after withdraw is wrong"
            );
            assertEq(
                withdrawData.ptBalanceSenderBefore,
                withdrawData.ptBalanceSenderAfter + withdrawData.usedShares,
                "PT balance of sender after withdraw is wrong"
            );
            assertEq(
                withdrawData.ptBalanceReceiverAfter,
                withdrawData.ptBalanceReceiverBefore,
                "PT balance of receiver after withdraw is wrong"
            );
            assertEq(
                withdrawData.ytBalanceSenderBefore,
                withdrawData.ytBalanceSenderAfter + withdrawData.usedShares,
                "YieldToken balance of sender after withdraw is wrong"
            );
            assertEq(
                withdrawData.ytBalanceReceiverAfter,
                withdrawData.ytBalanceReceiverBefore,
                "YieldToken balance of receiver after withdraw is wrong"
            );
        }
        assertApproxEqAbs(
            withdrawData.ibtBalancePTContractBefore,
            withdrawData.ibtBalancePTContractAfter + expectedIBTWithdrawn,
            100,
            "IBT balance of PT contract after withdraw is wrong"
        );
        return withdrawData.usedShares;
    }

    /**
     * @dev Internal function for testing basic PT withdrawIBT and max shares
     * @param ibts Amount of IBT to receive
     * @param sender Address of the user that withdraws IBTs
     * @param receiver Address of the IBTs receiver
     * @param maxShares If false calls withdrawIBT function without max shares, with otherwise
     * @return shares Amount of shares burned for withdrawing IBTs
     */
    function _testWithdrawIBT1(
        uint256 ibts,
        address sender,
        address receiver,
        bool maxShares
    ) internal returns (uint256 shares) {
        DepositWithdrawRedeemData memory withdrawData;
        // data before
        withdrawData.underlyingBalanceSenderBefore = underlying.balanceOf(sender);
        withdrawData.ibtBalanceSenderBefore = ibt.balanceOf(sender);
        withdrawData.ptBalanceSenderBefore = principalToken.balanceOf(sender);
        withdrawData.ytBalanceSenderBefore = yt.actualBalanceOf(sender);
        withdrawData.underlyingBalanceReceiverBefore = underlying.balanceOf(receiver);
        withdrawData.ibtBalanceReceiverBefore = ibt.balanceOf(receiver);
        withdrawData.ptBalanceReceiverBefore = principalToken.balanceOf(receiver);
        withdrawData.ytBalanceReceiverBefore = yt.actualBalanceOf(receiver);
        withdrawData.ibtBalancePTContractBefore = ibt.balanceOf(address(principalToken));
        // data global
        withdrawData.expectedShares1 = principalToken.convertToPrincipal(ibt.convertToAssets(ibts));
        withdrawData.expectedShares2 = principalToken.previewWithdrawIBT(ibts);
        // withdrawIBT
        if (maxShares) {
            if (withdrawData.expectedShares1 > 0) {
                bytes memory revertData = abi.encodeWithSignature(
                    "ERC5143SlippageProtectionFailed()"
                );
                vm.expectRevert(revertData);
                principalToken.withdrawIBT(
                    ibts,
                    receiver,
                    sender,
                    withdrawData.expectedShares1 - 1
                );
            }
            withdrawData.usedShares = principalToken.withdrawIBT(
                ibts,
                receiver,
                sender,
                withdrawData.expectedShares1
            );
        } else {
            withdrawData.usedShares = principalToken.withdrawIBT(ibts, receiver, sender);
        }
        // data after
        withdrawData.underlyingBalanceSenderAfter = underlying.balanceOf(sender);
        withdrawData.ibtBalanceSenderAfter = ibt.balanceOf(sender);
        withdrawData.ptBalanceSenderAfter = principalToken.balanceOf(sender);
        withdrawData.ytBalanceSenderAfter = yt.actualBalanceOf(sender);
        withdrawData.underlyingBalanceReceiverAfter = underlying.balanceOf(receiver);
        withdrawData.ibtBalanceReceiverAfter = ibt.balanceOf(receiver);
        withdrawData.ptBalanceReceiverAfter = principalToken.balanceOf(receiver);
        withdrawData.ytBalanceReceiverAfter = yt.actualBalanceOf(receiver);
        withdrawData.ibtBalancePTContractAfter = ibt.balanceOf(address(principalToken));
        // assertions
        assertApproxEqAbs(
            withdrawData.usedShares,
            withdrawData.expectedShares1,
            100,
            "Received assets from withdrawIBT are not as expected (convertToShares)"
        );
        assertLe(
            withdrawData.usedShares,
            withdrawData.expectedShares1,
            "shares used have to be round up compared to expected value"
        );
        assertApproxEqAbs(
            withdrawData.usedShares,
            withdrawData.expectedShares2,
            100,
            "Received assets from withdrawIBT are not as expected (previewWithdrawIBT)"
        );
        assertLe(
            withdrawData.usedShares,
            withdrawData.expectedShares2,
            "shares used have to be round up compared to expected value"
        );
        if (sender == receiver) {
            assertEq(
                withdrawData.underlyingBalanceSenderAfter,
                withdrawData.underlyingBalanceSenderBefore,
                "Underlying balance of sender/receiver after withdrawIBT is wrong"
            );
            assertEq(
                withdrawData.ibtBalanceSenderBefore + ibts,
                withdrawData.ibtBalanceSenderAfter,
                "IBT balance of sender/receiver after withdrawIBT is wrong"
            );
            assertEq(
                withdrawData.ptBalanceSenderBefore,
                withdrawData.ptBalanceSenderAfter + withdrawData.usedShares,
                "PT balance of sender/receiver after withdrawIBT is wrong"
            );
            assertEq(
                withdrawData.ytBalanceSenderBefore,
                withdrawData.ytBalanceSenderAfter + withdrawData.usedShares,
                "YieldToken balance of sender/receiver after withdrawIBT is wrong"
            );
        } else {
            assertEq(
                withdrawData.underlyingBalanceSenderAfter,
                withdrawData.underlyingBalanceSenderBefore,
                "Underlying balance of sender after withdrawIBT is wrong"
            );
            assertEq(
                withdrawData.underlyingBalanceReceiverAfter,
                withdrawData.underlyingBalanceReceiverBefore,
                "Underlying balance of receiver after withdrawIBT is wrong"
            );
            assertEq(
                withdrawData.ibtBalanceSenderBefore,
                withdrawData.ibtBalanceSenderAfter,
                "IBT balance of sender after withdrawIBT is wrong"
            );
            assertEq(
                withdrawData.ibtBalanceReceiverBefore + ibts,
                withdrawData.ibtBalanceReceiverAfter,
                "IBT balance of receiver after withdrawIBT is wrong"
            );
            assertEq(
                withdrawData.ptBalanceSenderBefore,
                withdrawData.ptBalanceSenderAfter + withdrawData.usedShares,
                "PT balance of sender after withdrawIBT is wrong"
            );
            assertEq(
                withdrawData.ptBalanceReceiverAfter,
                withdrawData.ptBalanceReceiverBefore,
                "PT balance of receiver after withdrawIBT is wrong"
            );
            assertEq(
                withdrawData.ytBalanceSenderBefore,
                withdrawData.ytBalanceSenderAfter + withdrawData.usedShares,
                "YieldToken balance of sender after withdrawIBT is wrong"
            );
            assertEq(
                withdrawData.ytBalanceReceiverAfter,
                withdrawData.ytBalanceReceiverBefore,
                "YieldToken balance of receiver after withdrawIBT is wrong"
            );
        }
        assertApproxEqAbs(
            withdrawData.ibtBalancePTContractBefore,
            withdrawData.ibtBalancePTContractAfter + ibts,
            0,
            "IBT balance of PT contract after withdrawIBT is wrong"
        );
        return withdrawData.usedShares;
    }

    /**
     * @dev Internal function for max redeem + claimYield
     * @param sender address of the user that redeems shares
     * @param receiver address of the assets receiver
     */
    function _testRedeemMaxAndClaimYield(
        address sender,
        address receiver
    ) internal returns (uint256 assets) {
        DepositWithdrawRedeemData memory data;

        data.underlyingBalanceReceiverBefore = underlying.balanceOf(receiver);
        data.ptBalanceSenderBefore = principalToken.balanceOf(sender);
        data.ytBalanceSenderBefore = yt.balanceOf(sender);
        data.ibtBalancePTContractBefore = ibt.balanceOf(address(principalToken));

        uint256 previewYieldIBT = principalToken.getCurrentYieldOfUserInIBT(sender);
        data.maxRedeem = principalToken.maxRedeem(sender);
        uint256 expectedAssets = principalToken.previewRedeem(data.maxRedeem) +
            IERC4626(ibt).previewRedeem(previewYieldIBT);
        uint256 expectedAssetsInIBT = principalToken.previewRedeemForIBT(data.maxRedeem) +
            previewYieldIBT;

        if (expectedAssets > 0) {
            assets = principalToken.redeem(data.maxRedeem, receiver, sender);
            assets += principalToken.claimYield(receiver, 0);

            data.underlyingBalanceReceiverAfter = underlying.balanceOf(receiver);
            data.ptBalanceSenderAfter = principalToken.balanceOf(sender);
            data.ytBalanceSenderAfter = yt.actualBalanceOf(sender);
            data.ibtBalancePTContractAfter = ibt.balanceOf(address(principalToken));

            assertApproxEqRel(
                assets,
                expectedAssets,
                1e8,
                "preview for redeem max + claimYield is wrong"
            );

            assertGe(
                assets,
                expectedAssets,
                "After max redeem + claimYield, the user received more assets than expected"
            );

            assertEq(
                data.underlyingBalanceReceiverBefore + assets,
                data.underlyingBalanceReceiverAfter,
                "After max redeem + claimYield, underlying balance of receiver is wrong"
            );
            assertEq(
                data.ptBalanceSenderBefore,
                data.ptBalanceSenderAfter + data.maxRedeem,
                "After max redeem, PT balance of owner is wrong"
            );

            if (block.timestamp < principalToken.maturity()) {
                assertEq(
                    data.ytBalanceSenderBefore,
                    data.ytBalanceSenderAfter + data.maxRedeem,
                    "After max redeem, YT balance of owner is wrong"
                );
            } else {
                assertEq(
                    data.ytBalanceSenderBefore,
                    data.ytBalanceSenderAfter,
                    "After max redeem, YT balance of owner is wrong"
                );
            }

            assertEq(
                data.ibtBalancePTContractBefore,
                data.ibtBalancePTContractAfter + expectedAssetsInIBT,
                "After max redeem + claimYield, IBT balance of PT contract is wrong"
            );
            assertGe(
                data.ibtBalancePTContractBefore,
                data.ibtBalancePTContractAfter + expectedAssetsInIBT,
                "More IBTs than expected have been burned"
            );
        }
    }

    /**
     * @dev Internal function for changing ibt rate
     */
    function _changeRate(uint16 rate, bool isIncrease) internal returns (uint256) {
        uint256 newPrice = ibt.changeRate(rate, isIncrease);
        return newPrice;
    }

    /**
     * @dev Internal function for expiring principalToken
     */
    function _increaseTimeToExpiry() internal {
        uint256 time = block.timestamp + principalToken.maturity();
        vm.warp(time);
    }

    function _calculateYieldGain(uint256 amount, uint128 rate) internal pure returns (uint256) {
        return amount + (amount * (rate * 1e16)) / 1e18;
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
}
