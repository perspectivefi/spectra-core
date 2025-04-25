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
import "openzeppelin-contracts/proxy/beacon/UpgradeableBeacon.sol";

contract ContractPrincipalToken is Test {
    /* STRUCTS */
    struct DepositData {
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
        uint256 previewMint0;
        uint256 ibtAmount0;
        uint256 underlyingAmount0;
        uint256 amountInAsset0;
        uint256 mintResult0;
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
        uint256 previewMint1;
        uint256 ibtAmount1;
        uint256 underlyingAmount1;
        uint256 amountInAsset1;
        uint256 mintResult1;
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
        uint256 previewMint2_1;
        uint256 previewMint2_2;
        uint256 previewMint2_3;
        uint256 ibtAmount2_1;
        uint256 ibtAmount2_2;
        uint256 ibtAmount2_3;
        uint256 underlyingAmount2;
        uint256 amountInAsset2;
        uint256 mintResult2_1;
        uint256 mintResult2_2;
        uint256 mintResult2_3;
        uint256 redeemedAssets2;
        // t3
        uint256 amountInAsset3_1;
        uint256 amountInAsset3_2;
        uint256 amountInAsset3_3;
        uint256 mintResult3;
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
    address TEST_USER_1 = 0x0000000000000000000000000000000000000001;
    address TEST_USER_2 = 0x0000000000000000000000000000000000000002;
    address TEST_USER_3 = 0x0000000000000000000000000000000000000003;
    address TEST_USER_4 = 0x0000000000000000000000000000000000000004;
    uint256 public TOKENIZATION_FEE = 1e15;
    uint256 public YIELD_FEE = 0;
    uint256 public PT_FLASH_LOAN_FEE = 0;
    uint256 public EXPIRY = block.timestamp + 100000;
    uint256 public IBT_UNIT;
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
        underlying = new MockERC20();
        underlying.initialize("MOCK UNDERLYING", "MUDL"); // deploys underlying mints 100000e18 token to caller
        ibt = new MockIBT2();
        ibt.initialize("MOCK IBT", "MIBT", IERC20Metadata(address(underlying))); // deploys ibt which principalToken holds
        IBT_UNIT = 10 ** ibt.decimals();
        underlying.mint(TEST_USER_1, 1);
        vm.prank(TEST_USER_1);
        underlying.approve(address(ibt), 1);
        vm.prank(TEST_USER_1);
        ibt.deposit(1, TEST_USER_1);

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
    function testMultipleDepositsAtTrivialRateFuzz(uint256 amount) public {
        amount = bound(amount, 0, 10000000e18);
        TestUsersData memory usersData;
        // data before
        usersData.underlyingBalanceTestUser1_0 = underlying.balanceOf(TEST_USER_1);
        usersData.ibtBalanceTestUser1_0 = ibt.balanceOf(TEST_USER_1);
        usersData.ibtBalancePTContract_0 = ibt.balanceOf(address(principalToken));
        usersData.ptBalanceTestUser1_0 = principalToken.balanceOf(TEST_USER_1);
        usersData.ytBalanceTestUser1_0 = yt.balanceOf(TEST_USER_1);

        // start pranking user 1
        vm.startPrank(TEST_USER_1);

        /* DEPOSITING WITH UNDERLYING ASSETS */
        underlying.mint(TEST_USER_1, amount);
        underlying.approve(address(principalToken), amount);
        // first deposit
    }

    /**
     * @dev Internal function for changing ibt rate
     */
    function _changeRate(uint16 rate, bool isIncrease) internal returns (uint256) {
        uint256 newPrice = ibt.changeRate(rate, isIncrease);
        return newPrice;
    }
}
