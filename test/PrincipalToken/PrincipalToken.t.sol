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
import "src/libraries/RayMath.sol";
import "openzeppelin-contracts/proxy/beacon/UpgradeableBeacon.sol";

contract ContractPrincipalToken1 is Test {
    using RayMath for uint256;
    using Math for uint256;

    struct DepositWithdrawRedeemData {
        // data before
        uint256 underlyingBalanceBefore; //assetBalBefore
        uint256 ibtBalanceBefore; //ibtBalBefore
        uint256 ptBalanceBefore; //ptBalBefore
        uint256 ytBalanceBefore; //ytBalBefore
        uint256 ibtBalPTContractBefore;
        uint256 totalAssetsBefore;
        // data after
        uint256 underlyingBalanceAfter; //assetBalAfter
        uint256 ibtBalanceAfter; //ibtBalAfter
        uint256 ptBalanceAfter; //ptBalAfter
        uint256 ytBalanceAfter; //ytBalAfter
        uint256 ibtBalPTContractAfter;
        uint256 totalAssetsAfter;
        // data global
        uint256 expectedIBT;
        uint256 preview;
        uint256 maxRedeem;
        uint256 yieldInIBT;
    }
    struct Rate {
        uint256 rateIBT0;
        uint256 ratePT0;
        uint256 oldPTRateUser;
        uint256 newPTRateUser;
        uint256 oldIBTRateUser;
        uint256 newIBTRateUser;
        uint256 oldRate;
        uint256 newRate;
        uint256 oldIBTRate;
        uint256 newIBTRate;
        uint256 oldPTRate;
        uint256 newPTRate;
    }
    struct UserRate {
        uint256 oldPTRate;
        uint256 oldIBTRate;
        uint256 oldYieldOfUserInIBT;
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
        uint256 yieldClaimed;
        uint256 underlyingBalanceBefore;
    }
    struct TokenTransferData {
        uint256 amountToTransfer;
        uint256 ytBalanceBeforeSender;
        uint256 ytBalanceBeforeReceiver;
        uint256 yieldOfSenderInIBTBefore;
        uint256 yieldOfReceiverInIBTBefore;
        uint256 ytBalanceAfterSender;
        uint256 ytBalanceAfterReceiver;
        uint256 yieldOfSenderInIBTAfter;
        uint256 yieldOfReceiverInIBTAfter;
        uint256 ptBalanceBeforeSender;
        uint256 ptBalanceBeforeReceiver;
        uint256 ptBalanceAfterSender;
        uint256 ptBalanceAfterReceiver;
    }
    struct UserDataBeforeAfter {
        uint256 userYTBalanceBefore;
        uint256 userYTBalanceAfter;
        uint256 userUnderlyingBalanceBefore;
        uint256 userUnderlyingBalanceAfter;
    }
    struct UserUnderlyingData {
        bool isUserYieldNegativeUser1;
        bool isUserYieldNegativeUser2;
        uint256 underlyingBalanceBeforeUser1;
        uint256 underlyingBalanceBeforeUser2;
    }

    PrincipalToken public principalToken;
    Factory public factory;
    MockERC20 public underlying;
    MockIBT public ibt;
    UpgradeableBeacon public principalTokenBeacon;
    UpgradeableBeacon public ytBeacon;
    YieldToken public yt;
    Registry public registry;
    AccessManager public accessManager;
    address feeCollector = 0x0000000000000000000000000000000000000FEE;
    address MOCK_ADDR_1 = 0x0000000000000000000000000000000000000001;
    address MOCK_ADDR_2 = 0x0000000000000000000000000000000000000002;
    address MOCK_ADDR_3 = 0x0000000000000000000000000000000000000003;
    address MOCK_ADDR_4 = 0x0000000000000000000000000000000000000004;
    address MOCK_ADDR_5 = 0x0000000000000000000000000000000000000005;
    uint256 public MAX_FEE = 1e18;
    uint256 public TOKENIZATION_FEE = 1e15;
    uint256 public YIELD_FEE = 0;
    uint256 public PT_FLASH_LOAN_FEE = 0;
    uint256 public EXPIRY = block.timestamp + 100000;
    uint256 public IBT_UNIT;
    address public testUser;
    address public scriptAdmin;
    uint256 public ptRate;
    uint256 public ibtRate;
    bytes32 private constant PERMIT_TYPEHASH =
        keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );
    uint256 public RAY_UNIT = 1e27;

    // Events
    event PTDeployed(address indexed principalToken, address indexed poolCreator);
    event Redeem(address indexed from, address indexed to, uint256 amount);
    event Mint(address indexed from, address indexed to, uint256 amount);
    event Paused(address account);
    event Unpaused(address account);
    event YieldUpdated(address indexed user, uint256 indexed yieldInIBT);

    /**
     * @dev This is the function to deploy principalToken and other mock contracts
     * for testing. It is called before each test.
     */
    function setUp() public {
        testUser = address(this); // to reduce number of lines and repeated vm pranks
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
        factory = Factory(factoryScript.deployForTest(address(registry), address(accessManager)));

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
        (ptRate, ibtRate) = _getPTAndIBTRates();
        yt = YieldToken(principalToken.getYT());
    }

    // Unit tests

    function testPTSymbol() public {
        string memory expiry = NamingUtil.uintToString(principalToken.maturity());
        assertEq(
            principalToken.symbol(),
            NamingUtil.concatenate("PT-MIBT", NamingUtil.concatenate("-", expiry))
        );
    }

    function testPTGetIBTUnit() public {
        uint256 ibtUnitExpected = 10 ** ibt.decimals();
        assertEq(principalToken.getIBTUnit(), ibtUnitExpected);
    }

    function testYTDecimals() public {
        assertEq(principalToken.decimals(), yt.decimals());
    }

    function testYTgetPT() public {
        assertEq(address(principalToken), yt.getPT());
    }

    function testPTgetMaxDeposit() public {
        assertEq(type(uint256).max, principalToken.maxDeposit(address(0)));
    }

    function testYTTransferFromWhenNotPaused() public {
        uint256 amountToDeposit = 1e18;
        underlying.approve(address(principalToken), amountToDeposit);
        principalToken.deposit(amountToDeposit, MOCK_ADDR_1);

        uint256 ytBalance = yt.actualBalanceOf(MOCK_ADDR_1);

        assertEq(yt.actualBalanceOf(MOCK_ADDR_1), ytBalance);
        assertEq(yt.actualBalanceOf(MOCK_ADDR_2), 0);
        vm.prank(MOCK_ADDR_1);
        yt.approve(address(this), ytBalance);
        yt.transferFrom(MOCK_ADDR_1, MOCK_ADDR_2, ytBalance);
        assertEq(yt.actualBalanceOf(MOCK_ADDR_1), 0);
        assertEq(yt.actualBalanceOf(MOCK_ADDR_2), ytBalance);
    }

    function testYTSymbol() public {
        string memory expiry = NamingUtil.uintToString(principalToken.maturity());
        assertEq(
            yt.symbol(),
            NamingUtil.concatenate("YT-MIBT", NamingUtil.concatenate("-", expiry))
        );
    }

    function testYTBalanceOfWhenNotExpired() public {
        uint256 amountToDeposit = 1e18;
        underlying.approve(address(principalToken), amountToDeposit);
        principalToken.deposit(amountToDeposit, address(this));

        uint256 ptBalance = principalToken.balanceOf(address(this));
        uint256 ytBalance = yt.actualBalanceOf(address(this));

        // checks if PT balance is equal to deposited amount
        assertApproxEqAbs(
            ptBalance,
            amountToDeposit,
            1000,
            "After Deposit PT balance is not equal to expected value"
        );
        assertLe(ptBalance, amountToDeposit);

        // checks if YieldToken balance is equal to deposited amount
        assertApproxEqAbs(
            ytBalance,
            amountToDeposit,
            1000,
            "After Deposit YieldToken balance is not equal to expected value"
        );
        assertLe(ytBalance, amountToDeposit);
    }

    function testYTBalanceOfWhenExpired() public {
        uint256 amountToDeposit = 1e18;
        underlying.approve(address(principalToken), amountToDeposit);
        principalToken.deposit(amountToDeposit, address(this));

        _increaseTimeToExpiry();

        uint256 ptBalance = principalToken.balanceOf(address(this));
        uint256 ytBalance = yt.balanceOf(address(this));

        // checks if PT balance is equal to deposited amount
        assertApproxEqAbs(
            ptBalance,
            amountToDeposit,
            1000,
            "After Deposit PT balance is not equal to expected value"
        );
        assertLe(ptBalance, amountToDeposit);

        // checks if YieldToken balance is equal to deposited amount
        assertEq(ytBalance, 0, "After Deposit YieldToken balance is not equal to expected value");
    }

    function testDepositAtInitialRate() public {
        uint256 amountToDeposit = 1e18;
        underlying.approve(address(principalToken), amountToDeposit);

        vm.expectEmit(true, true, false, true);
        // Since PT rate = 1, shares = deposit;
        emit Mint(address(this), address(this), amountToDeposit);

        principalToken.deposit(amountToDeposit, address(this));

        uint256 ptBalance = principalToken.balanceOf(address(this));
        uint256 ytBalance = yt.balanceOf(address(this));

        // checks if PT balance is equal to deposited amount
        assertApproxEqAbs(
            ptBalance,
            amountToDeposit,
            1000,
            "After Deposit PT balance is not equal to expected value"
        );

        // checks if YieldToken balance is equal to deposited amount
        assertApproxEqAbs(
            ytBalance,
            amountToDeposit,
            1000,
            "After Deposit YieldToken balance is not equal to expected value"
        );

        // check IBT balance of PT contract
        uint256 ibtBalance = ibt.balanceOf(address(principalToken));
        assertApproxEqAbs(
            ibtBalance,
            amountToDeposit,
            1000,
            "After Deposit IBT balance of vualt is not equal to expected value"
        );
    }

    function testDepositAtInitialRateWithMinShares() public {
        uint256 amountToDeposit = 1e18;
        underlying.approve(address(principalToken), amountToDeposit);

        vm.expectEmit(true, true, false, true);
        // Since PT rate = 1, shares = deposit;
        emit Mint(address(this), address(this), amountToDeposit);

        principalToken.deposit(amountToDeposit, address(this), address(this), amountToDeposit);

        uint256 ptBalance = principalToken.balanceOf(address(this));
        uint256 ytBalance = yt.balanceOf(address(this));

        // checks if PT balance is equal to deposited amount
        assertApproxEqAbs(
            ptBalance,
            amountToDeposit,
            1000,
            "After Deposit PT balance is not equal to expected value"
        );

        // checks if YieldToken balance is equal to deposited amount
        assertApproxEqAbs(
            ytBalance,
            amountToDeposit,
            1000,
            "After Deposit YieldToken balance is not equal to expected value"
        );

        // check IBT balance of PT contract
        uint256 ibtBalance = ibt.balanceOf(address(principalToken));
        assertApproxEqAbs(
            ibtBalance,
            amountToDeposit,
            1000,
            "After Deposit IBT balance of vualt is not equal to expected value"
        );
    }

    function testDepositAtInitialRateWithMinSharesFails() public {
        uint256 amountToDeposit = 1e18;
        underlying.approve(address(principalToken), amountToDeposit);

        bytes memory revertData = abi.encodeWithSignature("ERC5143SlippageProtectionFailed()");
        vm.expectRevert(revertData);
        principalToken.deposit(amountToDeposit, address(this), address(this), amountToDeposit * 2);
    }

    function testDepositAtDoubleRate() public {
        uint256 amountToDeposit = 1e18;
        underlying.approve(address(principalToken), amountToDeposit);

        _increaseRate(100);

        vm.expectEmit(true, true, false, true);
        // Since PT rate = 1, shares = deposit;
        emit Mint(address(this), address(this), amountToDeposit);

        principalToken.deposit(amountToDeposit, address(this));

        uint256 ptBalance = principalToken.balanceOf(address(this));
        uint256 ytBalance = yt.balanceOf(address(this));

        // checks if PT balance is equal to deposited amount
        assertApproxEqAbs(
            ptBalance,
            amountToDeposit,
            1000,
            "After Deposit PT balance is not equal to expected value"
        );

        // checks if YieldToken balance is equal to deposited amount
        assertApproxEqAbs(
            ytBalance,
            amountToDeposit,
            1000,
            "After Deposit YieldToken balance is not equal to expected value"
        );

        // check IBT balance of PT contract
        uint256 ibtBalance = ibt.balanceOf(address(principalToken));
        assertApproxEqAbs(
            ibtBalance,
            amountToDeposit / 2,
            1000,
            "After Deposit IBT balance of vualt is not equal to expected value"
        );
    }

    function testDepositAtHalfRate() public {
        uint256 amountToDeposit = 1e18;
        underlying.approve(address(principalToken), amountToDeposit);

        _increaseRate(-50);

        vm.expectEmit(true, true, false, true);
        // Since PT rate = 0.5, shares = deposit * 2;
        emit Mint(address(this), address(this), amountToDeposit * 2);

        principalToken.deposit(amountToDeposit, address(this));

        uint256 ptBalance = principalToken.balanceOf(address(this));
        uint256 ytBalance = yt.balanceOf(address(this));

        // checks if PT balance is equal to deposited amount
        assertApproxEqAbs(
            ptBalance,
            amountToDeposit * 2,
            1000,
            "After Deposit PT balance is not equal to expected value"
        );

        // checks if YieldToken balance is equal to deposited amount
        assertApproxEqAbs(
            ytBalance,
            amountToDeposit * 2,
            1000,
            "After Deposit YieldToken balance is not equal to expected value"
        );

        // check IBT balance of PT contract
        uint256 ibtBalance = ibt.balanceOf(address(principalToken));
        assertApproxEqAbs(
            ibtBalance,
            amountToDeposit * 2,
            1000,
            "After Deposit IBT balance of vualt is not equal to expected value"
        );
    }

    function test100NYDepositFuzz(uint256 amountToDeposit) public {
        amountToDeposit = bound(amountToDeposit, 1e12, 1000e18);
        underlying.approve(address(principalToken), amountToDeposit);
        principalToken.deposit(amountToDeposit, address(this));

        _increaseRate(-100);

        underlying.approve(address(principalToken), amountToDeposit);
        vm.expectRevert();
        principalToken.deposit(amountToDeposit, address(this));
    }

    function testMultipleDepositWithPositiveYield() public {
        uint256 amountToDeposit = 1e18;
        underlying.approve(address(principalToken), amountToDeposit * 2);

        // initial deposit
        principalToken.deposit(amountToDeposit, address(this));

        _increaseRate(100);

        // second deposit
        principalToken.deposit(amountToDeposit, address(this));

        uint256 ptBalance = principalToken.balanceOf(address(this));
        uint256 ytBalance = yt.actualBalanceOf(address(this));

        // checks if PT balance is equal to deposited amount
        assertApproxEqAbs(
            ptBalance,
            amountToDeposit * 2,
            1000,
            "After Deposit PT balance is not equal to expected value"
        );

        // checks if YieldToken balance is equal to deposited amount
        assertApproxEqAbs(
            ytBalance,
            amountToDeposit * 2,
            1000,
            "After Deposit YieldToken balance is not equal to expected value"
        );

        // check IBT balance of PT contract
        uint256 ibtBalance = ibt.balanceOf(address(principalToken));
        assertApproxEqAbs(
            ibtBalance,
            amountToDeposit + (amountToDeposit / 2), // since second deposit was after increase in rate
            1000,
            "After Deposit IBT balance of vualt is not equal to expected value"
        );
    }

    function testMultipleDepositWithNegativeYield() public {
        uint256 amountToDeposit = 1e18;
        underlying.approve(address(principalToken), amountToDeposit * 2);

        // initial deposit
        principalToken.deposit(amountToDeposit, address(this));

        _increaseRate(-50);

        // second deposit
        principalToken.deposit(amountToDeposit, address(this));

        uint256 ptBalance = principalToken.balanceOf(address(this));
        uint256 ytBalance = yt.actualBalanceOf(address(this));

        // checks if PT balance is equal to deposited amount
        assertApproxEqAbs(
            ptBalance,
            amountToDeposit + (amountToDeposit * 2), // since pt rate is also 0.5
            1000,
            "After Deposit PT balance is not equal to expected value"
        );

        // checks if YieldToken balance is equal to deposited amount
        assertApproxEqAbs(
            ytBalance,
            amountToDeposit + (amountToDeposit * 2), // since pt rate is also 0.5
            1000,
            "After Deposit YieldToken balance is not equal to expected value"
        );

        // check IBT balance of PT contract
        uint256 ibtBalance = ibt.balanceOf(address(principalToken));
        assertApproxEqAbs(
            ibtBalance,
            amountToDeposit + (amountToDeposit * 2), // second deposit was after rate was smaller
            1000,
            "After Deposit IBT balance of vualt is not equal to expected value"
        );
    }

    function testDepositWithInsufficientFunds() public {
        underlying.mint(MOCK_ADDR_1, 1e18);
        bytes memory revertData = abi.encodeWithSelector(
            bytes4(keccak256("ERC20InsufficientAllowance(address,uint256,uint256)")),
            principalToken,
            0,
            1e18
        );
        vm.expectRevert(revertData);
        vm.prank(MOCK_ADDR_1);
        uint256 actual = principalToken.deposit(1e18, MOCK_ADDR_1);
        vm.prank(MOCK_ADDR_1);
        underlying.approve(address(principalToken), 1000000e18);
        revertData = abi.encodeWithSelector(
            bytes4(keccak256("ERC20InsufficientBalance(address,uint256,uint256)")),
            MOCK_ADDR_1,
            1e18,
            1000000e18
        );
        vm.expectRevert(revertData);
        vm.prank(MOCK_ADDR_1);
        actual = principalToken.deposit(1000000e18, MOCK_ADDR_1);
    }

    function testDepositIBTWithInsufficientFunds() public {
        underlying.mint(MOCK_ADDR_1, 1e18);
        vm.prank(MOCK_ADDR_1);
        underlying.approve(address(ibt), 1e18);
        vm.prank(MOCK_ADDR_1);
        uint256 ibtReceived = ibt.deposit(1e18, MOCK_ADDR_1);
        assertEq(ibt.balanceOf(MOCK_ADDR_1), ibtReceived);
        assertEq(ibtReceived, 1e18); // as rate is 1
        bytes memory revertData = abi.encodeWithSelector(
            bytes4(keccak256("ERC20InsufficientAllowance(address,uint256,uint256)")),
            principalToken,
            0,
            ibtReceived
        );
        vm.expectRevert(revertData);
        vm.prank(MOCK_ADDR_1);
        uint256 actual = principalToken.depositIBT(ibtReceived, MOCK_ADDR_1);
        vm.prank(MOCK_ADDR_1);
        ibt.approve(address(principalToken), 1000000e18);
        revertData = abi.encodeWithSelector(
            bytes4(keccak256("ERC20InsufficientBalance(address,uint256,uint256)")),
            MOCK_ADDR_1,
            1e18,
            1000000e18
        );
        vm.expectRevert(revertData);
        vm.prank(MOCK_ADDR_1);
        actual = principalToken.depositIBT(1000000e18, MOCK_ADDR_1);
    }

    function testDepositIBTAtInitialRate() public {
        uint256 amountOfIbtToDeposit = 1e18;
        _prepareForDepositIBT(testUser, amountOfIbtToDeposit);

        vm.startPrank(testUser);
        ibt.approve(address(principalToken), amountOfIbtToDeposit);
        principalToken.depositIBT(amountOfIbtToDeposit, testUser);
        vm.stopPrank();

        uint256 ptBalance = principalToken.balanceOf(testUser);
        uint256 ytBalance = yt.actualBalanceOf(testUser);

        // checks if PT balance is equal to deposited amount since rate = 1
        assertApproxEqAbs(
            ptBalance,
            amountOfIbtToDeposit,
            1000,
            "After Deposit PT balance is not equal to expected value"
        );

        // checks if YieldToken balance is equal to deposited amount since rate = 1
        assertApproxEqAbs(
            ytBalance,
            amountOfIbtToDeposit,
            1000,
            "After Deposit YieldToken balance is not equal to expected value"
        );

        // check IBT balance of PT contract
        uint256 ibtBalance = ibt.balanceOf(address(principalToken));
        assertApproxEqAbs(
            ibtBalance,
            amountOfIbtToDeposit,
            1000,
            "After Deposit IBT balance of vualt is not equal to expected value"
        );
    }

    function testDepositIBTAtInitialRateWithMinShares() public {
        uint256 amountOfIbtToDeposit = 1e18;
        _prepareForDepositIBT(testUser, amountOfIbtToDeposit);

        vm.startPrank(testUser);
        ibt.approve(address(principalToken), amountOfIbtToDeposit);
        principalToken.depositIBT(amountOfIbtToDeposit, testUser, testUser, amountOfIbtToDeposit);
        vm.stopPrank();

        uint256 ptBalance = principalToken.balanceOf(testUser);
        uint256 ytBalance = yt.actualBalanceOf(testUser);

        // checks if PT balance is equal to deposited amount since rate = 1
        assertApproxEqAbs(
            ptBalance,
            amountOfIbtToDeposit,
            1000,
            "After Deposit PT balance is not equal to expected value"
        );

        // checks if YieldToken balance is equal to deposited amount since rate = 1
        assertApproxEqAbs(
            ytBalance,
            amountOfIbtToDeposit,
            1000,
            "After Deposit YieldToken balance is not equal to expected value"
        );

        // check IBT balance of PT contract
        uint256 ibtBalance = ibt.balanceOf(address(principalToken));
        assertApproxEqAbs(
            ibtBalance,
            amountOfIbtToDeposit,
            1000,
            "After Deposit IBT balance of vualt is not equal to expected value"
        );
    }

    function testDepositIBTAtInitialRateWithMinSharesFails() public {
        uint256 amountOfIbtToDeposit = 1e18;
        _prepareForDepositIBT(testUser, amountOfIbtToDeposit);

        vm.startPrank(testUser);
        ibt.approve(address(principalToken), amountOfIbtToDeposit);
        bytes memory revertData = abi.encodeWithSignature("ERC5143SlippageProtectionFailed()");
        vm.expectRevert(revertData);
        principalToken.depositIBT(
            amountOfIbtToDeposit,
            testUser,
            testUser,
            amountOfIbtToDeposit * 2
        );
        vm.stopPrank();
    }

    function testDepositIBTAtDoubleRate() public {
        uint256 amountOfIbtToDeposit = 1e18;
        _prepareForDepositIBT(testUser, amountOfIbtToDeposit);

        _increaseRate(100);

        vm.startPrank(testUser);
        ibt.approve(address(principalToken), amountOfIbtToDeposit);
        principalToken.depositIBT(amountOfIbtToDeposit, testUser);
        vm.stopPrank();

        uint256 ptBalance = principalToken.balanceOf(testUser);
        uint256 ytBalance = yt.actualBalanceOf(testUser);

        // checks if PT balance is double the deposited amount since rate = 2
        assertApproxEqAbs(
            ptBalance,
            amountOfIbtToDeposit * 2,
            1000,
            "After Deposit PT balance is not equal to expected value"
        );

        // checks if YieldToken balance is double the deposited amount since rate = 2
        assertApproxEqAbs(
            ytBalance,
            amountOfIbtToDeposit * 2,
            1000,
            "After Deposit YieldToken balance is not equal to expected value"
        );

        // check IBT balance of PT contract
        uint256 ibtBalance = ibt.balanceOf(address(principalToken));
        assertApproxEqAbs(
            ibtBalance,
            amountOfIbtToDeposit,
            1000,
            "After Deposit IBT balance of vualt is not equal to expected value"
        );
    }

    function testDepositIBTAtHalfRate() public {
        uint256 amountOfIbtToDeposit = 1e18;
        _prepareForDepositIBT(testUser, amountOfIbtToDeposit);

        _increaseRate(-50);

        vm.startPrank(testUser);
        ibt.approve(address(principalToken), amountOfIbtToDeposit);
        principalToken.depositIBT(amountOfIbtToDeposit, testUser);
        vm.stopPrank();

        uint256 ptBalance = principalToken.balanceOf(testUser);
        uint256 ytBalance = yt.actualBalanceOf(testUser);

        // checks if PT balance is equal to the deposited amount since IBT rate and PT rate both equals 0.5
        assertApproxEqAbs(
            ptBalance,
            amountOfIbtToDeposit,
            1000,
            "After Deposit PT balance is not equal to expected value"
        );

        // checks if YieldToken balance is equal to the deposited amount since IBT rate and PT rate both equals 0.5
        assertApproxEqAbs(
            ytBalance,
            amountOfIbtToDeposit,
            1000,
            "After Deposit YieldToken balance is not equal to expected value"
        );

        // check IBT balance of PT contract
        uint256 ibtBalance = ibt.balanceOf(address(principalToken));
        assertApproxEqAbs(
            ibtBalance,
            amountOfIbtToDeposit,
            1000,
            "After Deposit IBT balance of vualt is not equal to expected value"
        );
    }

    function testDepositIBTAtDifferentPTAndIBTRates() public {
        uint256 amountOfIbtToDeposit = 1e18;
        _prepareForDepositIBT(testUser, amountOfIbtToDeposit);

        _increaseRate(-50);
        _increaseRate(25);

        vm.startPrank(testUser);
        uint256 ptBalanceBefore = principalToken.balanceOf(testUser);
        uint256 ytBalanceBefore = yt.actualBalanceOf(testUser);
        uint256 amountInUnderlying = ibt.convertToAssets(amountOfIbtToDeposit);
        ibt.approve(address(principalToken), amountOfIbtToDeposit);
        uint256 shares = principalToken.depositIBT(amountOfIbtToDeposit, testUser);
        vm.stopPrank();

        assertApproxEqAbs(
            shares,
            principalToken.convertToPrincipal(amountInUnderlying),
            1000,
            "After deposit with IBT, shares received are not as expected"
        );

        assertApproxEqAbs(
            principalToken.balanceOf(testUser),
            ptBalanceBefore + shares,
            1000,
            "After deposit with IBT, PT balance is not equal to expected value"
        );

        assertApproxEqAbs(
            yt.actualBalanceOf(testUser),
            ytBalanceBefore + shares,
            1000,
            "After deposit with IBT, YieldToken balance is not equal to expected value"
        );

        // check IBT balance of PT contract
        uint256 ibtBalance = ibt.balanceOf(address(principalToken));
        assertApproxEqAbs(
            ibtBalance,
            amountOfIbtToDeposit,
            1000,
            "After Deposit IBT balance of vualt is not equal to expected value"
        );
    }

    function testMultipleDepositIBTWithPositiveYield() public {
        uint256 amountToDeposit = 1e18;
        _prepareForDepositIBT(testUser, amountToDeposit);

        vm.startPrank(testUser);
        ibt.approve(address(principalToken), amountToDeposit);

        // initial deposit
        principalToken.depositIBT(amountToDeposit, testUser);
        vm.stopPrank();

        _increaseRate(100);

        _prepareForDepositIBT(testUser, amountToDeposit);

        vm.startPrank(testUser);
        ibt.approve(address(principalToken), amountToDeposit);
        // second deposit
        principalToken.depositIBT(amountToDeposit, testUser);
        vm.stopPrank();

        uint256 ptBalance = principalToken.balanceOf(testUser);
        uint256 ytBalance = yt.actualBalanceOf(testUser);

        // checks if PT balance is equal to deposited amount
        assertApproxEqAbs(
            ptBalance,
            amountToDeposit + (amountToDeposit * 2), // since second deposit was after increase in rate
            1000,
            "After Deposit PT balance is not equal to expected value"
        );
        assertLe(ytBalance, amountToDeposit + (amountToDeposit * 2));

        // checks if YieldToken balance is equal to deposited amount
        assertApproxEqAbs(
            ytBalance,
            amountToDeposit + (amountToDeposit * 2), // since second deposit was after increase in rate
            1000,
            "After Deposit YieldToken balance is not equal to expected value"
        );
        assertLe(ytBalance, amountToDeposit + (amountToDeposit * 2));

        // check IBT balance of PT contract
        uint256 ibtBalance = ibt.balanceOf(address(principalToken));
        assertApproxEqAbs(
            ibtBalance,
            amountToDeposit * 2,
            1000,
            "After Deposit IBT balance of PT contract is not equal to expected value"
        );
    }

    function testDoubleDepositIBTWithNegativeYield() public {
        uint256 amountToDeposit = 1e18;
        _prepareForDepositIBT(testUser, amountToDeposit);

        vm.startPrank(testUser);
        ibt.approve(address(principalToken), amountToDeposit);

        // initial deposit
        principalToken.depositIBT(amountToDeposit, testUser);
        vm.stopPrank();

        _increaseRate(-50);

        _prepareForDepositIBT(testUser, amountToDeposit);

        vm.startPrank(testUser);
        ibt.approve(address(principalToken), amountToDeposit);
        // second deposit
        principalToken.depositIBT(amountToDeposit, testUser);
        vm.stopPrank();

        uint256 ptBalance = principalToken.balanceOf(testUser);
        uint256 ytBalance = yt.actualBalanceOf(testUser);

        // checks if PT balance is equal to deposited amount
        assertApproxEqAbs(
            ptBalance,
            amountToDeposit * 2, // since pt rate is also 0.5
            1000,
            "After Deposit PT balance is not equal to expected value"
        );

        // checks if YieldToken balance is equal to deposited amount
        assertApproxEqAbs(
            ytBalance,
            amountToDeposit * 2, // since pt rate is also 0.5
            1000,
            "After Deposit YieldToken balance is not equal to expected value"
        );

        // check IBT balance of PT contract
        uint256 ibtBalance = ibt.balanceOf(address(principalToken));
        assertApproxEqAbs(
            ibtBalance,
            amountToDeposit * 2, // second deposit was after rate was smaller
            1000,
            "After Deposit IBT balance of vualt is not equal to expected value"
        );
    }

    function testDoubleDepositIBTWithBothPAndNYield() public {
        uint256 amountToDeposit = 1e18;
        uint256 ptBalance = principalToken.balanceOf(testUser);
        uint256 ytBalance = yt.actualBalanceOf(testUser);
        _prepareForDepositIBT(testUser, amountToDeposit);

        vm.startPrank(testUser);
        ibt.approve(address(principalToken), amountToDeposit);

        // initial deposit
        uint256 oldIBTRate = ibtRate;
        uint256 oldPTRate = ptRate;
        principalToken.depositIBT(amountToDeposit, testUser);
        vm.stopPrank();

        _increaseRate(25);
        _increaseRate(-50);

        _prepareForDepositIBT(testUser, amountToDeposit);

        vm.startPrank(testUser);
        ibt.approve(address(principalToken), amountToDeposit);

        // second deposit
        principalToken.depositIBT(amountToDeposit, testUser);
        uint256 newPTRate = principalToken.getPTRate();
        vm.stopPrank();

        // checks if PT balance is equal to deposited amount
        assertApproxEqAbs(
            principalToken.balanceOf(testUser),
            ptBalance +
                _convertToSharesWithRate(
                    _convertToAssetsWithRate(
                        amountToDeposit,
                        oldIBTRate,
                        false,
                        true,
                        Math.Rounding.Floor
                    ),
                    oldPTRate,
                    true,
                    false,
                    Math.Rounding.Floor
                ) +
                _convertToSharesWithRate(
                    ibt.convertToAssets(amountToDeposit),
                    newPTRate,
                    false,
                    false,
                    Math.Rounding.Floor
                ),
            1000,
            "After Deposit PT balance is not equal to expected value"
        );

        // checks if YieldToken balance is equal to deposited amount
        assertApproxEqAbs(
            yt.actualBalanceOf(testUser),
            ytBalance +
                _convertToSharesWithRate(
                    _convertToAssetsWithRate(
                        amountToDeposit,
                        oldIBTRate,
                        false,
                        true,
                        Math.Rounding.Floor
                    ),
                    oldPTRate,
                    true,
                    false,
                    Math.Rounding.Floor
                ) +
                _convertToSharesWithRate(
                    ibt.convertToAssets(amountToDeposit),
                    newPTRate,
                    false,
                    false,
                    Math.Rounding.Floor
                ),
            1000,
            "After Deposit YieldToken balance is not equal to expected value"
        );

        // check IBT balance of PT contract
        uint256 ibtBalance = ibt.balanceOf(address(principalToken));
        assertApproxEqAbs(
            ibtBalance,
            amountToDeposit * 2,
            1000,
            "After Deposit IBT balance of vualt is not equal to expected value"
        );
    }

    function testWithdraw() public {
        uint256 amount = 1e18;
        underlying.approve(address(principalToken), amount);
        principalToken.deposit(amount, testUser);

        uint256 beforeBalance = underlying.balanceOf(testUser);

        principalToken.withdraw(amount, testUser, testUser);

        assertEq(principalToken.balanceOf(testUser), 0, "User share balance is incorrect");
        assertEq(yt.actualBalanceOf(testUser), 0, "User YieldToken balance is incorrect");
        assertEq(
            underlying.balanceOf(testUser),
            beforeBalance + amount,
            "User underlying balance is incorrect"
        );
    }

    function testWithdrawWithMaxShares() public {
        uint256 amount = 1e18;
        underlying.approve(address(principalToken), amount);
        principalToken.deposit(amount, testUser);

        uint256 beforeBalance = underlying.balanceOf(testUser);

        principalToken.withdraw(amount, testUser, testUser, amount);

        assertEq(principalToken.balanceOf(testUser), 0, "User share balance is incorrect");
        assertEq(yt.actualBalanceOf(testUser), 0, "User YieldToken balance is incorrect");
        assertEq(
            underlying.balanceOf(testUser),
            beforeBalance + amount,
            "User underlying balance is incorrect"
        );
    }

    function testWithdrawWithMaxSharesFails() public {
        uint256 amount = 1e18;
        underlying.approve(address(principalToken), amount);
        principalToken.deposit(amount, testUser);

        bytes memory revertData = abi.encodeWithSignature("ERC5143SlippageProtectionFailed()");
        vm.expectRevert(revertData);
        principalToken.withdraw(amount, testUser, testUser, amount / 2);
    }

    function testWithdrawWithPositiveYield() public {
        uint256 amount = 1e18;
        underlying.approve(address(principalToken), amount);
        principalToken.deposit(amount, testUser);

        _increaseRate(100);

        uint256 beforeBalance = underlying.balanceOf(testUser);

        uint256 withdrawAmount = principalToken.maxWithdraw(testUser);

        // since there was a 100% positive yield
        principalToken.withdraw(withdrawAmount, testUser, testUser);

        assertApproxEqAbs(
            principalToken.balanceOf(testUser),
            0,
            1000,
            "User share balance is incorrect"
        );

        assertGe(principalToken.balanceOf(testUser), 0);

        assertApproxEqAbs(
            yt.actualBalanceOf(testUser),
            0,
            1000,
            "User YieldToken balance is incorrect"
        );

        assertGe(yt.actualBalanceOf(testUser), 0);

        assertApproxEqAbs(
            underlying.balanceOf(testUser),
            beforeBalance + withdrawAmount,
            1000,
            "User underlying balance is incorrect"
        );
        assertGe(beforeBalance + withdrawAmount, underlying.balanceOf(testUser));
    }

    function testWithdrawWithNegativeYield() public {
        uint256 amount = 1e18;
        underlying.approve(address(principalToken), amount);
        principalToken.deposit(amount, testUser);

        _increaseRate(-50);

        uint256 beforeBalance = underlying.balanceOf(testUser);

        uint256 withdrawAmount = principalToken.maxWithdraw(testUser);

        // since there was a 100% positive yield
        principalToken.withdraw(withdrawAmount, testUser, testUser);

        assertEq(principalToken.balanceOf(testUser), 0, "User share balance is incorrect");
        assertEq(yt.actualBalanceOf(testUser), 0, "User YieldToken balance is incorrect");
        assertEq(
            underlying.balanceOf(testUser),
            beforeBalance + withdrawAmount,
            "User underlying balance is incorrect"
        );
    }

    function test100NYWithdrawFuzz(uint256 amountToDeposit) public {
        amountToDeposit = bound(amountToDeposit, 1e16, 1000e18);
        uint256 amountToWithdraw = amountToDeposit / 2;
        vm.prank(testUser);

        underlying.approve(address(principalToken), amountToDeposit);
        principalToken.deposit(amountToDeposit, testUser);

        _increaseRate(-100);

        vm.expectRevert();
        principalToken.withdraw(amountToWithdraw, MOCK_ADDR_1, testUser);
    }

    function testWithdrawMoreThanLimit() public {
        uint256 amount = 1e18;
        underlying.approve(address(principalToken), amount);
        principalToken.deposit(amount, testUser);

        bytes memory revertData = abi.encodeWithSignature("UnsufficientBalance()");
        vm.expectRevert(revertData);
        principalToken.withdraw(amount * 2, testUser, testUser);
    }

    function testGetCurrentYieldPY() public {
        uint256 amount = 1e18;
        underlying.approve(address(principalToken), amount);
        principalToken.deposit(amount, testUser);

        _increaseRate(100);

        assertEq(
            principalToken.getCurrentYieldOfUserInIBT(testUser),
            amount / 2,
            "Yield in IBT is wrong"
        );
    }

    function testGetCurrentYieldNY() public {
        uint256 amount = 1e18;
        underlying.approve(address(principalToken), amount);
        principalToken.deposit(amount, testUser);

        _increaseRate(-50);

        assertEq(
            principalToken.getCurrentYieldOfUserInIBT(testUser),
            0, // No yield is generated for negative rate
            "Yield in IBT is wrong"
        );
    }

    function testClaimYield0Y() public {
        uint256 amount = 1e18;
        underlying.approve(address(principalToken), amount);
        principalToken.deposit(amount, address(this));

        uint256 underlyingBalanceBefore = underlying.balanceOf(address(this));
        principalToken.claimYield(address(this));
        uint256 underlyingBalanceAfter = underlying.balanceOf(address(this));

        assertEq(underlyingBalanceBefore, underlyingBalanceAfter, "Wrong underlying balance");
    }

    function testClaimYieldPY() public {
        uint256 amount = 2e18;
        underlying.approve(address(principalToken), amount);
        principalToken.deposit(amount, address(this));

        _increaseRate(100);
        uint256 underlyingBalanceBefore = underlying.balanceOf(address(this));
        principalToken.claimYield(address(this));
        uint256 underlyingBalanceAfter = underlying.balanceOf(address(this));

        assertApproxEqAbs(
            underlyingBalanceAfter,
            underlyingBalanceBefore + _amountMinusFee(amount, registry.getYieldFee()),
            1000,
            "Wrong underlying balance"
        );
    }

    function testClaimYieldNY() public {
        uint256 amount = 1e18;
        underlying.approve(address(principalToken), amount);
        principalToken.deposit(amount, address(this));

        _increaseRate(-50);

        uint256 underlyingBalanceBefore = underlying.balanceOf(address(this));
        principalToken.claimYield(address(this));
        uint256 underlyingBalanceAfter = underlying.balanceOf(address(this));

        assertEq(underlyingBalanceBefore, underlyingBalanceAfter, "Wrong underlying balance");
    }

    // PT and YieldToken token permit tests
    function testPermitPTAndYT() public {
        uint256 privateKey = 0xABCD; // taking a known private key so that can create address.
        address owner = vm.addr(privateKey);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    IERC20Permit(address(principalToken)).DOMAIN_SEPARATOR(),
                    keccak256(
                        abi.encode(
                            PERMIT_TYPEHASH,
                            owner,
                            MOCK_ADDR_1,
                            1e18,
                            0,
                            block.timestamp + 100000
                        )
                    )
                )
            )
        );

        IERC20Permit(address(principalToken)).permit(
            owner,
            MOCK_ADDR_1,
            1e18,
            block.timestamp + 100000,
            v,
            r,
            s
        );
        assertEq(IERC20(address(principalToken)).allowance(owner, MOCK_ADDR_1), 1e18);
        assertEq(IERC20Permit(address(principalToken)).nonces(owner), 1);

        (v, r, s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    IERC20Permit(address(yt)).DOMAIN_SEPARATOR(),
                    keccak256(
                        abi.encode(
                            PERMIT_TYPEHASH,
                            owner,
                            MOCK_ADDR_1,
                            1e18,
                            0,
                            block.timestamp + 100000
                        )
                    )
                )
            )
        );

        IERC20Permit(address(yt)).permit(
            owner,
            MOCK_ADDR_1,
            1e18,
            block.timestamp + 100000,
            v,
            r,
            s
        );
        assertEq(IERC20(address(yt)).allowance(owner, MOCK_ADDR_1), 1e18);
        assertEq(IERC20Permit(address(yt)).nonces(owner), 1);
    }

    function testPermitPTAndYTBadNonceFailFuzz(uint256 deadline, uint256 nonce) public {
        if (deadline < block.timestamp) deadline = block.timestamp;
        if (nonce == 0) nonce = 1;

        address owner = vm.addr(0xABCD);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            0xABCD,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    IERC20Permit(address(principalToken)).DOMAIN_SEPARATOR(),
                    keccak256(
                        abi.encode(PERMIT_TYPEHASH, owner, MOCK_ADDR_1, 1e18, nonce, deadline)
                    )
                )
            )
        );

        address recoveredSigner = ecrecover(
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    IERC20Permit(address(principalToken)).DOMAIN_SEPARATOR(),
                    keccak256(
                        abi.encode(
                            PERMIT_TYPEHASH,
                            owner,
                            MOCK_ADDR_1,
                            1e18,
                            IERC20Permit(address(principalToken)).nonces(owner),
                            deadline
                        )
                    )
                )
            ),
            v,
            r,
            s
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("ERC2612InvalidSigner(address,address)")),
                recoveredSigner,
                owner
            )
        );
        IERC20Permit(address(principalToken)).permit(owner, MOCK_ADDR_1, 1e18, deadline, v, r, s);

        (v, r, s) = vm.sign(
            0xABCD,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    IERC20Permit(address(yt)).DOMAIN_SEPARATOR(),
                    keccak256(
                        abi.encode(PERMIT_TYPEHASH, owner, MOCK_ADDR_1, 1e18, nonce, deadline)
                    )
                )
            )
        );

        recoveredSigner = ecrecover(
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    IERC20Permit(address(yt)).DOMAIN_SEPARATOR(),
                    keccak256(
                        abi.encode(
                            PERMIT_TYPEHASH,
                            owner,
                            MOCK_ADDR_1,
                            1e18,
                            IERC20Permit(address(yt)).nonces(owner),
                            deadline
                        )
                    )
                )
            ),
            v,
            r,
            s
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("ERC2612InvalidSigner(address,address)")),
                recoveredSigner,
                owner
            )
        );
        IERC20Permit(address(yt)).permit(owner, MOCK_ADDR_1, 1e18, deadline, v, r, s);
    }

    function testPermitPTAndYTBadDeadlineFailFuzz(uint256 deadline) public {
        if (deadline < block.timestamp) deadline = block.timestamp;

        uint256 privateKey = 0xABCD; // taking a known private key so that can create address.
        address owner = vm.addr(privateKey);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    IERC20Permit(address(principalToken)).DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(PERMIT_TYPEHASH, owner, MOCK_ADDR_1, 1e18, 0, deadline))
                )
            )
        );

        vm.expectRevert();
        IERC20Permit(address(principalToken)).permit(
            owner,
            MOCK_ADDR_1,
            1e18,
            deadline + 1,
            v,
            r,
            s
        );

        (v, r, s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    IERC20Permit(address(yt)).DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(PERMIT_TYPEHASH, owner, MOCK_ADDR_1, 1e18, 0, deadline))
                )
            )
        );

        vm.expectRevert();
        IERC20Permit(address(principalToken)).permit(
            owner,
            MOCK_ADDR_1,
            1e18,
            deadline + 1,
            v,
            r,
            s
        );
    }

    function testPermitPTAndYTPastDeadlineFailFuzz(uint256 deadline) public {
        deadline = bound(deadline, 0, block.timestamp - 1);

        uint256 privateKey = 0xABCD; // taking a known private key so that can create address.
        address owner = vm.addr(privateKey);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    IERC20Permit(address(principalToken)).DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(PERMIT_TYPEHASH, owner, MOCK_ADDR_1, 1e18, 0, deadline))
                )
            )
        );

        bytes memory revertData = abi.encodeWithSelector(
            bytes4(keccak256("ERC2612ExpiredSignature(uint256)")),
            deadline
        );
        vm.expectRevert(revertData);
        IERC20Permit(address(principalToken)).permit(owner, MOCK_ADDR_1, 1e18, deadline, v, r, s);

        (v, r, s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    IERC20Permit(address(yt)).DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(PERMIT_TYPEHASH, owner, MOCK_ADDR_1, 1e18, 0, deadline))
                )
            )
        );

        revertData = abi.encodeWithSelector(
            bytes4(keccak256("ERC2612ExpiredSignature(uint256)")),
            deadline
        );
        vm.expectRevert(revertData);
        IERC20Permit(address(yt)).permit(owner, MOCK_ADDR_1, 1e18, deadline, v, r, s);
    }

    function testPermitPTAndYTReplayFailFuzz(uint256 deadline) public {
        if (deadline < block.timestamp) deadline = block.timestamp;

        uint256 privateKey = 0xABCD; // taking a known private key so that can create address.
        address owner = vm.addr(privateKey);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    IERC20Permit(address(principalToken)).DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(PERMIT_TYPEHASH, owner, MOCK_ADDR_1, 1e18, 0, deadline))
                )
            )
        );

        IERC20Permit(address(principalToken)).permit(owner, MOCK_ADDR_1, 1e18, deadline, v, r, s);

        address recoveredSigner = ecrecover(
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    IERC20Permit(address(principalToken)).DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(PERMIT_TYPEHASH, owner, MOCK_ADDR_1, 1e18, 1, deadline))
                )
            ),
            v,
            r,
            s
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("ERC2612InvalidSigner(address,address)")),
                recoveredSigner,
                owner
            )
        );
        IERC20Permit(address(principalToken)).permit(owner, MOCK_ADDR_1, 1e18, deadline, v, r, s);

        (v, r, s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    IERC20Permit(address(yt)).DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(PERMIT_TYPEHASH, owner, MOCK_ADDR_1, 1e18, 0, deadline))
                )
            )
        );

        IERC20Permit(address(yt)).permit(owner, MOCK_ADDR_1, 1e18, deadline, v, r, s);

        recoveredSigner = ecrecover(
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    IERC20Permit(address(yt)).DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(PERMIT_TYPEHASH, owner, MOCK_ADDR_1, 1e18, 1, deadline))
                )
            ),
            v,
            r,
            s
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("ERC2612InvalidSigner(address,address)")),
                recoveredSigner,
                owner
            )
        );
        IERC20Permit(address(yt)).permit(owner, MOCK_ADDR_1, 1e18, deadline, v, r, s);
    }

    function testTransferPT() public {
        uint256 amountToDeposit = 10e18;
        uint256 amountToTransfer = 1e18;

        _testDeposit(amountToDeposit, address(this));

        uint256 ptContractBalanceBeforeTransfer = principalToken.balanceOf(address(this));
        uint256 userBalanceBeforeTransfer = principalToken.balanceOf(MOCK_ADDR_1);

        // transfers the amount to MOCK_ADDR_1
        principalToken.transfer(MOCK_ADDR_1, amountToTransfer);

        uint256 ptContractBalanceAfterTransfer = principalToken.balanceOf(address(this));
        uint256 userBalanceAfterTransfer = principalToken.balanceOf(MOCK_ADDR_1);

        // checks if balances are accurate after transfer
        assertEq(
            userBalanceAfterTransfer,
            userBalanceBeforeTransfer + amountToTransfer,
            "After transfer balance incorrect for User"
        );
        assertEq(
            ptContractBalanceAfterTransfer,
            ptContractBalanceBeforeTransfer - amountToTransfer,
            "After transfer balance incorrect for Future Vault"
        );
    }

    function testRedeem() public {
        uint256 amountToDeposit = 2e18;
        uint256 redeemShares = amountToDeposit / 2;
        vm.prank(testUser);

        underlying.approve(address(principalToken), amountToDeposit);
        principalToken.deposit(amountToDeposit, testUser);

        _increaseTimeToExpiry();
        principalToken.storeRatesAtExpiry();

        vm.expectEmit(true, true, false, true);
        emit Redeem(testUser, MOCK_ADDR_1, redeemShares);

        principalToken.redeem(redeemShares, MOCK_ADDR_1, testUser);

        assertEq(
            principalToken.balanceOf(testUser),
            redeemShares,
            "After redeem balance is incorrect"
        );
        assertEq(
            underlying.balanceOf(MOCK_ADDR_1),
            redeemShares, // since, rate in unchanged
            "After redeem balance is not equal to redeemed amount"
        );
    }

    function testRedeemWithMinAssets() public {
        uint256 amountToDeposit = 2e18;
        uint256 redeemShares = amountToDeposit / 2;
        vm.prank(testUser);

        underlying.approve(address(principalToken), amountToDeposit);
        principalToken.deposit(amountToDeposit, testUser);

        _increaseTimeToExpiry();
        principalToken.storeRatesAtExpiry();

        vm.expectEmit(true, true, false, true);
        emit Redeem(testUser, MOCK_ADDR_1, redeemShares);

        principalToken.redeem(redeemShares, MOCK_ADDR_1, testUser, amountToDeposit / 2);

        assertEq(
            principalToken.balanceOf(testUser),
            redeemShares,
            "After redeem balance is incorrect"
        );

        assertEq(
            underlying.balanceOf(MOCK_ADDR_1),
            redeemShares, // since, rate in unchanged
            "After redeem balance is not equal to redeemed amount"
        );
    }

    function testRedeemWithMinAssetsFails() public {
        uint256 amountToDeposit = 2e18;
        uint256 redeemShares = amountToDeposit / 2;
        vm.prank(testUser);

        underlying.approve(address(principalToken), amountToDeposit);
        principalToken.deposit(amountToDeposit, testUser);

        _increaseTimeToExpiry();
        principalToken.storeRatesAtExpiry();

        bytes memory revertData = abi.encodeWithSignature("ERC5143SlippageProtectionFailed()");
        vm.expectRevert(revertData);
        principalToken.redeem(redeemShares, MOCK_ADDR_1, testUser, amountToDeposit);
    }

    function testRedeemWithPositiveYield() public {
        uint256 amountToDeposit = 2e18;
        uint256 redeemShares = amountToDeposit / 2;
        vm.prank(testUser);

        underlying.approve(address(principalToken), amountToDeposit);
        principalToken.deposit(amountToDeposit, testUser);

        _increaseRate(100);

        _increaseTimeToExpiry();
        principalToken.storeRatesAtExpiry();

        vm.expectEmit(true, true, false, true);
        emit Redeem(testUser, MOCK_ADDR_1, redeemShares);

        principalToken.redeem(redeemShares, MOCK_ADDR_1, testUser);

        assertEq(
            principalToken.balanceOf(testUser),
            amountToDeposit - redeemShares, // half of the shares were redeemed
            "After redeem balance is incorrect"
        );
        assertEq(
            underlying.balanceOf(MOCK_ADDR_1),
            redeemShares, // since, yield is yet to be claimed
            "After redeem balance is not equal to redeemed amount"
        );
    }

    function testRedeemWithNegativeYield() public {
        uint256 amountToDeposit = 2e18;
        uint256 redeemShares = amountToDeposit / 2;
        vm.prank(testUser);

        underlying.approve(address(principalToken), amountToDeposit);
        principalToken.deposit(amountToDeposit, testUser);

        _increaseRate(-50);
        _increaseTimeToExpiry();
        principalToken.storeRatesAtExpiry();

        vm.expectEmit(true, true, false, true);
        emit Redeem(testUser, MOCK_ADDR_1, redeemShares);

        principalToken.redeem(redeemShares, MOCK_ADDR_1, testUser);

        assertEq(
            principalToken.balanceOf(testUser),
            amountToDeposit - redeemShares, // half of the shares were redeemed
            "After redeem balance is incorrect"
        );
        assertEq(
            underlying.balanceOf(MOCK_ADDR_1),
            redeemShares / 2, // since, rate is halfed
            "After redeem balance is not equal to redeemed amount"
        );
    }

    function test100NYRedeemFuzz(uint256 amountToDeposit) public {
        amountToDeposit = bound(amountToDeposit, 1e16, 1000e18);
        uint256 redeemShares = amountToDeposit / 2;
        vm.prank(testUser);

        underlying.approve(address(principalToken), amountToDeposit);
        principalToken.deposit(amountToDeposit, testUser);

        _increaseRate(-100);
        _increaseTimeToExpiry();
        principalToken.storeRatesAtExpiry();

        vm.expectRevert();
        principalToken.redeem(redeemShares, testUser, testUser);
    }

    function testRedeemWithoutAllowance() public {
        uint256 amountToDeposit = 1e18;
        vm.startPrank(testUser);

        underlying.approve(address(principalToken), amountToDeposit);
        principalToken.deposit(amountToDeposit, testUser);

        vm.stopPrank();
        _increaseTimeToExpiry();
        principalToken.storeRatesAtExpiry();

        vm.prank(MOCK_ADDR_1);
        bytes memory revertData = abi.encodeWithSignature("UnauthorizedCaller()");
        vm.expectRevert(revertData);
        principalToken.redeem(1e18, MOCK_ADDR_1, testUser);
    }

    function testRedeemMoreThanMax() public {
        uint256 amountToDeposit = 1e18;
        vm.prank(testUser);

        underlying.approve(address(principalToken), amountToDeposit);
        principalToken.deposit(amountToDeposit, testUser);

        _increaseTimeToExpiry();

        bytes memory revertData = abi.encodeWithSignature("UnsufficientBalance()");
        vm.expectRevert(revertData);
        principalToken.redeem(10e18, MOCK_ADDR_1, address(this));
    }

    function testClaimFees() public {
        uint256 amount = 1e18;
        underlying.approve(address(principalToken), amount);
        uint256 receivedShares = principalToken.deposit(amount, testUser);

        _increaseRate(100);

        principalToken.redeem(receivedShares, testUser, testUser);

        (uint256 _ptRate, uint256 _ibtRate) = _getPTAndIBTRates();
        uint256 expectedUnclaimedFeesInIBT = _convertPTSharesToIBTsWithRates(
            receivedShares,
            _ptRate,
            _ibtRate,
            false
        ).mulDiv(registry.getYieldFee(), 1e18); // since 100% yield was generated

        assertEq(
            underlying.balanceOf(feeCollector),
            0,
            "Incorrect balance of fee collector before claiming fees"
        );
        assertApproxEqAbs(
            principalToken.getUnclaimedFeesInIBT(),
            expectedUnclaimedFeesInIBT,
            10,
            "Incorrect value returned by the fee collected getter"
        );
        assertLe(principalToken.getUnclaimedFeesInIBT(), expectedUnclaimedFeesInIBT);
        vm.startPrank(feeCollector);
        uint256 expectedClaimedFees = ibt.previewRedeem(expectedUnclaimedFeesInIBT);
        principalToken.claimFees();
        assertApproxEqAbs(
            underlying.balanceOf(feeCollector),
            expectedClaimedFees,
            100,
            "Incorrect balance of fee collector after claiming fees"
        );
        assertLe(underlying.balanceOf(feeCollector), expectedClaimedFees);
    }

    function testClaimFeesCallWithoutAdmin() public {
        bytes memory revertData = abi.encodeWithSignature("UnauthorizedCaller()");
        vm.expectRevert(revertData);
        vm.prank(MOCK_ADDR_1);
        principalToken.claimFees();
    }

    // Unit tests: Getters

    function testPreviewRedeemWithoutRateChange() public {
        uint256 shares = 10e18;
        _increaseTimeToExpiry();
        principalToken.storeRatesAtExpiry();

        assertEq(
            principalToken.previewRedeem(shares),
            shares, // since rate is unchanged
            "Preview redeem balance is incorrect"
        );
    }

    function testPreviewRedeemWithPositiveRateChange() public {
        uint256 shares = 10e18;
        _increaseRate(100);
        _increaseTimeToExpiry();
        principalToken.storeRatesAtExpiry();

        assertEq(
            principalToken.previewRedeem(shares),
            shares, // since pt rate was not changed
            "Preview redeem balance is incorrect"
        );
    }

    function testPreviewRedeemWithNegativeRateChange() public {
        uint256 shares = 10e18;
        _increaseRate(-50);
        _increaseTimeToExpiry();
        principalToken.storeRatesAtExpiry();

        assertEq(
            principalToken.previewRedeem(shares),
            shares / 2, // since pt was depegged
            "Preview redeem balance is incorrect"
        );
    }

    function testMaxRedeem() public {
        uint256 amountToDeposit = 1e18;
        underlying.approve(address(principalToken), amountToDeposit);
        principalToken.deposit(amountToDeposit, address(this));
        _increaseTimeToExpiry();

        assertEq(
            principalToken.maxRedeem(address(this)),
            amountToDeposit,
            "Max redeem balance is not equal to expected value"
        );
    }

    function testPreviewWithdraw() public {
        uint256 amountToDeposit = 1e18;
        vm.prank(testUser);
        underlying.approve(address(principalToken), amountToDeposit);
        principalToken.deposit(amountToDeposit, testUser);

        assertEq(
            principalToken.previewWithdraw(amountToDeposit),
            amountToDeposit, // since no yield is generated
            "Withdraw preview is not equal to expected value"
        );
    }

    function testPreviewWithdrawWhenNoDeposit() public {
        uint256 amount = 1e18;
        assertEq(
            principalToken.previewWithdraw(amount),
            amount, // since no yield is generated
            "Withdraw preview is not equal to expected value"
        );
    }

    function testPreviewWithdrawWhenPositiveYield() public {
        uint256 amountToDeposit = 1e18;
        vm.startPrank(testUser);
        underlying.approve(address(principalToken), amountToDeposit);
        principalToken.deposit(amountToDeposit, testUser);
        _increaseRate(100);
        // previewWithdraw does not take yield into account
        assertApproxEqAbs(
            principalToken.previewWithdraw(amountToDeposit),
            amountToDeposit,
            1000,
            "Withdraw preview balance is not equal to expected value"
        );
        vm.stopPrank();
        assertLe(principalToken.previewWithdraw(amountToDeposit), amountToDeposit);
    }

    function testPreviewWithdrawWhenNegativeYield() public {
        uint256 amountToDeposit = 2e18;
        vm.startPrank(testUser);
        underlying.approve(address(principalToken), amountToDeposit);
        principalToken.deposit(amountToDeposit, testUser);
        _increaseRate(-50);

        // since -50% yield was generated, double the amount of shares would be burned
        assertEq(
            principalToken.previewWithdraw(amountToDeposit / 2),
            amountToDeposit,
            "Withdraw preview balance is not equal to expected value"
        );
        vm.stopPrank();
    }

    function test100NYPreviewWithdrawFuzz(uint256 amountToDeposit) public {
        amountToDeposit = bound(amountToDeposit, 1e16, 1000e18);
        uint256 amountToWithdraw = amountToDeposit / 2;
        vm.prank(testUser);

        underlying.approve(address(principalToken), amountToDeposit);
        principalToken.deposit(amountToDeposit, testUser);

        _increaseRate(-100);

        vm.expectRevert();
        principalToken.previewWithdraw(amountToWithdraw);
    }

    function testPreviewDeposit() public {
        uint256 amountToDeposit = 1e18;

        assertEq(
            principalToken.previewDeposit(amountToDeposit),
            amountToDeposit, // since PT rate is unchanged
            "Deposit preview balance is not equal to expected value"
        );
    }

    function testPreviewDepositWhenPositiveYield() public {
        uint256 amountToDeposit = 1e18;
        _increaseRate(100);

        assertEq(
            principalToken.previewDeposit(amountToDeposit),
            amountToDeposit, // since PT rate is unchanged
            "Deposit preview balance is not equal to expected value"
        );
    }

    function testPreviewDepositWhenNegativeYield() public {
        uint256 amountToDeposit = 1e18;
        _increaseRate(-50);

        assertEq(
            principalToken.previewDeposit(amountToDeposit),
            amountToDeposit * 2, // since PT was depegged
            "Deposit preview balance is not equal to expected value"
        );
    }

    function test100NYPreviewDepositFuzz(uint256 amountToDeposit) public {
        amountToDeposit = bound(amountToDeposit, 1e12, 1000e18);
        underlying.approve(address(principalToken), amountToDeposit);
        principalToken.deposit(amountToDeposit, address(this));

        _increaseRate(-100);

        underlying.approve(address(principalToken), amountToDeposit);
        bytes memory revertData = abi.encodeWithSignature("RateError()");
        vm.expectRevert(revertData);
        principalToken.previewDeposit(amountToDeposit);
    }

    function testPreviewDepositAfterExpiryFail() public {
        uint256 amountToDeposit = 1e18;
        _increaseTimeToExpiry();
        bytes memory revertData = abi.encodeWithSignature("PTExpired()");
        vm.expectRevert(revertData);
        principalToken.previewDeposit(amountToDeposit);
    }

    function testMaxWithdraw() public {
        uint256 amountToDeposit = 2e18;
        vm.prank(testUser);
        underlying.approve(address(principalToken), amountToDeposit);
        principalToken.deposit(amountToDeposit, testUser);

        assertEq(
            principalToken.maxWithdraw(testUser),
            principalToken.balanceOf(testUser), // since rate = 1
            "Max withdraw amount is not equal to expected value"
        );
    }

    function testMaxWithdrawWhenNoDeposit() public {
        assertEq(
            principalToken.maxWithdraw(testUser),
            0,
            "Max withdraw amount is not equal to expected value"
        );
    }

    function testMaxWithdrawPlusYieldPY() public {
        uint256 amountToDeposit = 2e18;
        vm.prank(testUser);
        underlying.approve(address(principalToken), amountToDeposit);
        principalToken.deposit(amountToDeposit, testUser);

        _increaseRate(100);
        _increaseTimeToExpiry();
        principalToken.storeRatesAtExpiry();

        // since there was a positive yield of 100%, yield = amountToDeposit
        uint256 expectedMaxWithdraw = (amountToDeposit * 2) -
            _getFee(amountToDeposit, registry.getYieldFee());

        assertApproxEqAbs(
            principalToken.maxWithdraw(testUser) +
                ibt.previewRedeem(principalToken.getCurrentYieldOfUserInIBT(testUser)),
            expectedMaxWithdraw,
            10,
            "Max withdraw amount is not equal to expected value"
        );
    }

    function testMaxWithdrawNY() public {
        uint256 amountToDeposit = 2e18;
        vm.prank(testUser);
        underlying.approve(address(principalToken), amountToDeposit);
        principalToken.deposit(amountToDeposit, testUser);

        _increaseRate(-50);

        assertApproxEqAbs(
            principalToken.maxWithdraw(testUser),
            (principalToken.balanceOf(testUser) / 2), // since there was a negative yield of 50%
            1,
            "Max withdraw amount is not equal to expected value"
        );
    }

    function testTotalAssets() public {
        uint256 amountToDeposit = 2e18;
        underlying.approve(address(principalToken), amountToDeposit);
        principalToken.deposit(amountToDeposit, testUser);

        vm.startPrank(testUser);
        underlying.approve(address(principalToken), amountToDeposit);
        principalToken.deposit(amountToDeposit, testUser);
        vm.stopPrank();

        assertEq(
            principalToken.totalAssets(),
            amountToDeposit * 2,
            "Total asset is not equal to expected value"
        );
    }

    function testTotalAssetsWithPositiveYield() public {
        uint256 amountToDeposit = 2e18;
        underlying.approve(address(principalToken), amountToDeposit);
        principalToken.deposit(amountToDeposit, testUser);

        _increaseRate(100);

        vm.startPrank(testUser);
        underlying.approve(address(principalToken), amountToDeposit);
        principalToken.deposit(amountToDeposit, testUser);
        vm.stopPrank();

        assertEq(
            principalToken.totalAssets(),
            amountToDeposit + (amountToDeposit * 2), // since rate was increased in second deposit
            "Total asset is not equal to expected value"
        );
    }

    function testTotalAssetsWithNegativeYield() public {
        uint256 amountToDeposit = 2e18;
        underlying.approve(address(principalToken), amountToDeposit);
        principalToken.deposit(amountToDeposit, testUser);

        _increaseRate(-50);

        vm.startPrank(testUser);
        underlying.approve(address(principalToken), amountToDeposit);
        principalToken.deposit(amountToDeposit, testUser);
        vm.stopPrank();

        assertEq(
            principalToken.totalAssets(),
            amountToDeposit + (amountToDeposit / 2), // since rate was decreased in second deposit
            "Total asset is not equal to expected value"
        );
    }

    function testConvertToShares() public {
        uint256 amountToDeposit = 2e18;
        underlying.approve(address(principalToken), amountToDeposit);
        principalToken.deposit(amountToDeposit, testUser);

        assertEq(
            principalToken.convertToPrincipal(amountToDeposit),
            amountToDeposit, // since rate is unchanged
            "Shares amount is not equal to expected value"
        );

        _increaseRate(-50);

        assertEq(
            principalToken.convertToPrincipal(amountToDeposit),
            amountToDeposit * 2, // since rate was halved
            "Shares amount is not equal to expected value"
        );
    }

    function testConvertToUnderlying() public {
        uint256 amountToDeposit = 2e18;
        underlying.approve(address(principalToken), amountToDeposit);
        principalToken.deposit(amountToDeposit, testUser);

        assertEq(
            principalToken.convertToUnderlying(amountToDeposit),
            amountToDeposit, // since rate is unchanged
            "Underlying amount is not equal to expected value"
        );

        _increaseRate(-50);

        assertEq(
            principalToken.convertToUnderlying(amountToDeposit),
            amountToDeposit / 2, // since rate was halved
            "Underlying amount is not equal to expected value"
        );
    }

    function testConvertToPrincipal() public {
        uint256 amountToDeposit = 2e18;
        underlying.approve(address(principalToken), amountToDeposit);
        principalToken.deposit(amountToDeposit, testUser);

        assertEq(
            principalToken.convertToPrincipal(amountToDeposit),
            amountToDeposit, // since rate is unchanged
            "Principal amount is not equal to expected value"
        );

        _increaseRate(-50);

        assertEq(
            principalToken.convertToPrincipal(amountToDeposit),
            amountToDeposit * 2, // since rate was halved
            "Principal amount is not equal to expected value"
        );
    }

    function testGetUnderlying() public {
        assertEq(
            principalToken.underlying(),
            address(underlying),
            "Wrong addres for underlying returned"
        );
    }

    function testGetMaturity() public {
        assertEq(
            principalToken.maturity(),
            EXPIRY + block.timestamp,
            "Inaccurate maturity returned"
        );
    }

    // Scenario tests for deposit with IBT

    function testMultipleDepositIBTWithNegativeYield() public {
        uint256 amountOfIbtToDeposit = 1e18;
        _prepareForDepositIBT(testUser, amountOfIbtToDeposit);
        uint256 amountInUnderlying = ibt.convertToAssets(amountOfIbtToDeposit);
        uint256 ptMintedByFuture = _testDepositIBT(amountOfIbtToDeposit, testUser);
        uint256 expectedPT = principalToken.convertToPrincipal(amountInUnderlying);
        assertApproxEqAbs(
            expectedPT,
            ptMintedByFuture,
            1000,
            "After Deposit balance is not equal to expected value"
        );

        _increaseRate(-50);

        _prepareForDepositIBT(testUser, amountOfIbtToDeposit);
        amountInUnderlying = ibt.convertToAssets(amountOfIbtToDeposit);
        ptMintedByFuture = _testDepositIBT(amountOfIbtToDeposit, testUser);
        expectedPT = principalToken.convertToPrincipal(amountInUnderlying);
        assertApproxEqAbs(
            expectedPT,
            ptMintedByFuture,
            1000,
            "After Deposit balance is not equal to expected value"
        );

        _increaseRate(-50);

        _prepareForDepositIBT(testUser, amountOfIbtToDeposit);
        amountInUnderlying = ibt.convertToAssets(amountOfIbtToDeposit);
        ptMintedByFuture = _testDepositIBT(amountOfIbtToDeposit, testUser);
        expectedPT = principalToken.convertToPrincipal(amountInUnderlying);
        assertApproxEqAbs(
            expectedPT,
            ptMintedByFuture,
            1000,
            "After Deposit balance is not equal to expected value"
        );
    }

    function testFailDepositIBT() public {
        uint256 amountOfIbtToDeposit = 1e18;
        _prepareForDepositIBT(testUser, amountOfIbtToDeposit);
        uint256 amountInUnderlying = ibt.convertToAssets(amountOfIbtToDeposit);
        uint256 ptMintedByFuture = _testDepositIBT(amountOfIbtToDeposit, testUser);
        uint256 expectedPT = principalToken.convertToPrincipal(amountInUnderlying);
        assertApproxEqAbs(
            expectedPT,
            ptMintedByFuture,
            1000,
            "After Deposit balance is not equal to expected value"
        );

        _increaseRate(-100);
        _prepareForDepositIBT(testUser, amountOfIbtToDeposit);
        ptMintedByFuture = _testDepositIBT(amountOfIbtToDeposit, testUser);
    }

    /**
     * @dev Tests deposit and then transfers of PT to otehr addresses when yield is zero and when yield is positive
       followed by transfers of yt to check if user is able to transfer yt even if he doesn't have pt in zero yield
       or positive yield case.
     */
    function testYTTransferWhenPTZeroAndZeroOrPositiveYield() public {
        uint256 amountToDeposit = 10e18;
        uint256 actual = _testDeposit(amountToDeposit, address(this));
        uint256 expected = principalToken.convertToPrincipal(amountToDeposit);
        assertEq(expected, actual, "After deposit balance is not equal to expected value"); // checks if balances are accurate after deposit

        uint256 amountToTransfer = principalToken.balanceOf(address(this)) / 2;
        uint256 expectedBalance1 = amountToTransfer;
        uint256 expectedBalance2 = principalToken.balanceOf(address(this)) - amountToTransfer;

        principalToken.transfer(MOCK_ADDR_1, amountToTransfer); // transfers amountToTransfer with first argument being receiver
        uint256 actualBalance1 = principalToken.balanceOf(MOCK_ADDR_1);
        uint256 actualBalance2 = principalToken.balanceOf(address(this));
        // checks if balances are accurate after deposit
        assertEq(
            expectedBalance1,
            actualBalance1,
            "After transfer balance is not equal to expected value 1"
        );
        assertEq(
            expectedBalance2,
            actualBalance2,
            "After transfer balance is not equal to expected value 2"
        );

        amountToTransfer = yt.actualBalanceOf(address(this)) / 2;
        expectedBalance1 = amountToTransfer;
        expectedBalance2 = yt.actualBalanceOf(address(this)) - amountToTransfer;

        yt.transfer(MOCK_ADDR_1, amountToTransfer); // transfers amountToTransfer with first argument being receiver
        actualBalance1 = yt.actualBalanceOf(MOCK_ADDR_1);
        actualBalance2 = yt.actualBalanceOf(address(this));
        // checks if balances are accurate after deposit
        assertEq(
            expectedBalance1,
            actualBalance1,
            "After transfer balance is not equal to expected value 3"
        );
        assertEq(
            expectedBalance2,
            actualBalance2,
            "After transfer balance is not equal to expected value 4"
        );

        _increaseRate(50);

        amountToTransfer = principalToken.balanceOf(address(this));
        expectedBalance1 = amountToTransfer;
        expectedBalance2 = principalToken.balanceOf(address(this)) - amountToTransfer;

        principalToken.transfer(MOCK_ADDR_2, amountToTransfer); // transfers amountToTransfer with first argument being receiver
        actualBalance1 = principalToken.balanceOf(MOCK_ADDR_2);
        actualBalance2 = principalToken.balanceOf(address(this));
        // checks if balances are accurate after deposit
        assertEq(
            expectedBalance1,
            actualBalance1,
            "After transfer balance is not equal to expected value 5"
        );
        assertEq(
            expectedBalance2,
            actualBalance2,
            "After transfer balance is not equal to expected value 6"
        );

        amountToTransfer = yt.actualBalanceOf(address(this));
        expectedBalance1 = amountToTransfer;
        expectedBalance2 = yt.actualBalanceOf(address(this)) - amountToTransfer;

        yt.transfer(MOCK_ADDR_2, amountToTransfer); // transfers amountToTransfer with first argument being receiver
        actualBalance1 = yt.actualBalanceOf(MOCK_ADDR_2);
        actualBalance2 = yt.actualBalanceOf(address(this));
        // checks if balances are accurate after deposit
        assertEq(
            expectedBalance1,
            actualBalance1,
            "After transfer balance is not equal to expected value 7"
        );
        assertEq(
            expectedBalance2,
            actualBalance2,
            "After transfer balance is not equal to expected value 8"
        );
    }

    /**
     * @dev Tests transfer YieldToken and PT in different yield situations for both sender and receiver.
     */
    function testTransferYTAndPT() public {
        TokenTransferData memory transferData;

        _testDeposit(100e18, address(this));

        // +50% of positive yield
        _increaseRate(50);

        _testDeposit(50e18, MOCK_ADDR_1);

        // -25% of positive yield
        _increaseRate(-25);

        _testDeposit(10e18, MOCK_ADDR_2);

        /* YieldToken TRANSFERS */
        // Each user transfer to other 2 users
        // address(this) as the YieldToken sender
        transferData.amountToTransfer = (3 * yt.actualBalanceOf(address(this))) / 10;
        transferData.ytBalanceBeforeSender = yt.actualBalanceOf(address(this));
        transferData.ytBalanceBeforeReceiver = yt.actualBalanceOf(MOCK_ADDR_1);
        transferData.yieldOfSenderInIBTBefore = principalToken.getCurrentYieldOfUserInIBT(
            address(this)
        );
        transferData.yieldOfReceiverInIBTBefore = principalToken.getCurrentYieldOfUserInIBT(
            MOCK_ADDR_1
        );

        (, uint256 newIbtRate) = _getPTAndIBTRates();

        assertApproxEqAbs(
            transferData.yieldOfSenderInIBTBefore,
            _convertToSharesWithRate(
                (75 * ((50 * 100e18) / 100)) / 100,
                newIbtRate,
                false,
                false,
                Math.Rounding.Floor
            ), // +50% of positive yield that are then subject to the -25%
            1000,
            "Positive yield for address(this) is wrong"
        );
        assertApproxEqAbs(
            transferData.yieldOfReceiverInIBTBefore,
            0, // There have been only negative yield
            1000,
            "Positive yield for MOCK_ADDR_1 is wrong"
        );

        yt.transfer(MOCK_ADDR_1, transferData.amountToTransfer);
        transferData.ytBalanceAfterSender = yt.actualBalanceOf(address(this));
        transferData.ytBalanceAfterReceiver = yt.actualBalanceOf(MOCK_ADDR_1);
        transferData.yieldOfSenderInIBTAfter = principalToken.getCurrentYieldOfUserInIBT(
            address(this)
        );
        transferData.yieldOfReceiverInIBTAfter = principalToken.getCurrentYieldOfUserInIBT(
            MOCK_ADDR_1
        );
        assertEq(
            transferData.yieldOfSenderInIBTAfter,
            transferData.yieldOfSenderInIBTBefore,
            "Yield update for sender is not correct"
        );
        assertEq(
            transferData.yieldOfReceiverInIBTAfter,
            transferData.yieldOfReceiverInIBTBefore,
            "Yield update for receiver is not correct"
        );
        assertEq(
            transferData.ytBalanceAfterSender + transferData.amountToTransfer,
            transferData.ytBalanceBeforeSender,
            "YieldToken balance of sender is wrong"
        );
        assertEq(
            transferData.ytBalanceAfterReceiver,
            transferData.ytBalanceBeforeReceiver + transferData.amountToTransfer,
            "YieldToken Balance of receiver is wrong"
        );

        transferData.amountToTransfer = (4 * yt.actualBalanceOf(address(this))) / 10;
        transferData.ytBalanceBeforeSender = yt.actualBalanceOf(address(this));
        transferData.ytBalanceBeforeReceiver = yt.actualBalanceOf(MOCK_ADDR_2);
        transferData.yieldOfReceiverInIBTBefore = principalToken.getCurrentYieldOfUserInIBT(
            MOCK_ADDR_2
        );
        assertApproxEqAbs(
            transferData.yieldOfReceiverInIBTBefore,
            0, // No yield since deposit
            1000,
            "Positive yield for MOCK_ADDR_2 is wrong"
        );

        yt.transfer(MOCK_ADDR_2, transferData.amountToTransfer);
        transferData.ytBalanceAfterSender = yt.actualBalanceOf(address(this));
        transferData.ytBalanceAfterReceiver = yt.actualBalanceOf(MOCK_ADDR_2);
        transferData.yieldOfReceiverInIBTAfter = principalToken.getCurrentYieldOfUserInIBT(
            MOCK_ADDR_2
        );
        assertEq(
            transferData.yieldOfReceiverInIBTAfter,
            transferData.yieldOfReceiverInIBTBefore,
            "Yield update for receiver is not correct"
        );
        assertEq(
            transferData.ytBalanceAfterSender + transferData.amountToTransfer,
            transferData.ytBalanceBeforeSender
        );
        assertEq(
            transferData.ytBalanceAfterReceiver,
            transferData.ytBalanceBeforeReceiver + transferData.amountToTransfer
        );

        // MOCK_ADDR_1 as YieldToken sender
        transferData.amountToTransfer = (1 * yt.actualBalanceOf(MOCK_ADDR_1)) / 10;
        transferData.ytBalanceBeforeSender = yt.actualBalanceOf(MOCK_ADDR_1);
        transferData.ytBalanceBeforeReceiver = yt.actualBalanceOf(address(this));
        vm.prank(MOCK_ADDR_1);
        yt.transfer(address(this), transferData.amountToTransfer);
        transferData.ytBalanceAfterSender = yt.actualBalanceOf(MOCK_ADDR_1);
        transferData.ytBalanceAfterReceiver = yt.actualBalanceOf(address(this));
        assertEq(
            transferData.ytBalanceAfterSender + transferData.amountToTransfer,
            transferData.ytBalanceBeforeSender,
            "YieldToken balance of sender is wrong"
        );
        assertEq(
            transferData.ytBalanceAfterReceiver,
            transferData.ytBalanceBeforeReceiver + transferData.amountToTransfer,
            "YieldToken Balance of receiver is wrong"
        );

        transferData.amountToTransfer = yt.actualBalanceOf(MOCK_ADDR_1);
        transferData.ytBalanceBeforeSender = yt.actualBalanceOf(MOCK_ADDR_1);
        transferData.ytBalanceBeforeReceiver = yt.actualBalanceOf(MOCK_ADDR_2);
        vm.prank(MOCK_ADDR_1);
        bytes memory revertData = abi.encodeWithSelector(
            bytes4(keccak256("ERC20InsufficientBalance(address,uint256,uint256)")),
            MOCK_ADDR_1,
            transferData.ytBalanceBeforeSender,
            transferData.amountToTransfer + 1
        );
        vm.expectRevert(revertData);
        yt.transfer(MOCK_ADDR_2, transferData.amountToTransfer + 1);
        vm.prank(MOCK_ADDR_1);
        yt.transfer(MOCK_ADDR_2, transferData.amountToTransfer);
        transferData.ytBalanceAfterSender = yt.actualBalanceOf(MOCK_ADDR_1);
        transferData.ytBalanceAfterReceiver = yt.actualBalanceOf(MOCK_ADDR_2);
        assertEq(
            transferData.ytBalanceAfterSender + transferData.amountToTransfer,
            transferData.ytBalanceBeforeSender
        );
        assertEq(
            transferData.ytBalanceAfterReceiver,
            transferData.ytBalanceBeforeReceiver + transferData.amountToTransfer
        );

        // MOCK_ADDR_2 as the YieldToken sender
        transferData.amountToTransfer = (5 * yt.actualBalanceOf(MOCK_ADDR_2)) / 10;
        transferData.ytBalanceBeforeSender = yt.actualBalanceOf(MOCK_ADDR_2);
        transferData.ytBalanceBeforeReceiver = yt.actualBalanceOf(address(this));
        vm.prank(MOCK_ADDR_2);
        yt.transfer(address(this), transferData.amountToTransfer);
        transferData.ytBalanceAfterSender = yt.actualBalanceOf(MOCK_ADDR_2);
        transferData.ytBalanceAfterReceiver = yt.actualBalanceOf(address(this));
        assertEq(
            transferData.ytBalanceAfterSender + transferData.amountToTransfer,
            transferData.ytBalanceBeforeSender,
            "YieldToken balance of sender is wrong"
        );
        assertEq(
            transferData.ytBalanceAfterReceiver,
            transferData.ytBalanceBeforeReceiver + transferData.amountToTransfer,
            "YieldToken Balance of receiver is wrong"
        );

        transferData.amountToTransfer = (7 * yt.actualBalanceOf(MOCK_ADDR_2)) / 10;
        transferData.ytBalanceBeforeSender = yt.actualBalanceOf(MOCK_ADDR_2);
        transferData.ytBalanceBeforeReceiver = yt.actualBalanceOf(MOCK_ADDR_1);
        vm.prank(MOCK_ADDR_2);
        yt.transfer(MOCK_ADDR_1, transferData.amountToTransfer);
        transferData.ytBalanceAfterSender = yt.actualBalanceOf(MOCK_ADDR_2);
        transferData.ytBalanceAfterReceiver = yt.actualBalanceOf(MOCK_ADDR_1);
        assertEq(
            transferData.ytBalanceAfterSender + transferData.amountToTransfer,
            transferData.ytBalanceBeforeSender
        );
        assertEq(
            transferData.ytBalanceAfterReceiver,
            transferData.ytBalanceBeforeReceiver + transferData.amountToTransfer
        );

        /* PT TRANSFERS */
        // Each user transfer to other 2 users
        // address(this) as the PT sender
        transferData.amountToTransfer = (3 * principalToken.balanceOf(address(this))) / 10;
        transferData.ptBalanceBeforeSender = principalToken.balanceOf(address(this));
        transferData.ptBalanceBeforeReceiver = principalToken.balanceOf(MOCK_ADDR_1);

        principalToken.transfer(MOCK_ADDR_1, transferData.amountToTransfer);
        transferData.ptBalanceAfterSender = principalToken.balanceOf(address(this));
        transferData.ptBalanceAfterReceiver = principalToken.balanceOf(MOCK_ADDR_1);
        assertEq(
            transferData.ptBalanceAfterSender + transferData.amountToTransfer,
            transferData.ptBalanceBeforeSender,
            "PT balance of sender is wrong"
        );
        assertEq(
            transferData.ptBalanceAfterReceiver,
            transferData.ptBalanceBeforeReceiver + transferData.amountToTransfer,
            "PT Balance of receiver is wrong"
        );

        transferData.amountToTransfer = (4 * principalToken.balanceOf(address(this))) / 10;
        transferData.ptBalanceBeforeSender = principalToken.balanceOf(address(this));
        transferData.ptBalanceBeforeReceiver = principalToken.balanceOf(MOCK_ADDR_2);

        principalToken.transfer(MOCK_ADDR_2, transferData.amountToTransfer);
        transferData.ptBalanceAfterSender = principalToken.balanceOf(address(this));
        transferData.ptBalanceAfterReceiver = principalToken.balanceOf(MOCK_ADDR_2);
        assertEq(
            transferData.ptBalanceAfterSender + transferData.amountToTransfer,
            transferData.ptBalanceBeforeSender
        );
        assertEq(
            transferData.ptBalanceAfterReceiver,
            transferData.ptBalanceBeforeReceiver + transferData.amountToTransfer
        );

        // MOCK_ADDR_1 as PT sender
        transferData.amountToTransfer = (1 * principalToken.balanceOf(MOCK_ADDR_1)) / 10;
        transferData.ptBalanceBeforeSender = principalToken.balanceOf(MOCK_ADDR_1);
        transferData.ptBalanceBeforeReceiver = principalToken.balanceOf(address(this));
        vm.prank(MOCK_ADDR_1);
        principalToken.transfer(address(this), transferData.amountToTransfer);
        transferData.ptBalanceAfterSender = principalToken.balanceOf(MOCK_ADDR_1);
        transferData.ptBalanceAfterReceiver = principalToken.balanceOf(address(this));
        assertEq(
            transferData.ptBalanceAfterSender + transferData.amountToTransfer,
            transferData.ptBalanceBeforeSender,
            "PT balance of sender is wrong"
        );
        assertEq(
            transferData.ptBalanceAfterReceiver,
            transferData.ptBalanceBeforeReceiver + transferData.amountToTransfer,
            "PT Balance of receiver is wrong"
        );

        transferData.amountToTransfer = principalToken.balanceOf(MOCK_ADDR_1);
        transferData.ptBalanceBeforeSender = principalToken.balanceOf(MOCK_ADDR_1);
        transferData.ptBalanceBeforeReceiver = principalToken.balanceOf(MOCK_ADDR_2);
        vm.prank(MOCK_ADDR_1);
        revertData = abi.encodeWithSelector(
            bytes4(keccak256("ERC20InsufficientBalance(address,uint256,uint256)")),
            MOCK_ADDR_1,
            transferData.ptBalanceBeforeSender,
            transferData.amountToTransfer + 1
        );
        vm.expectRevert(revertData);
        principalToken.transfer(MOCK_ADDR_2, transferData.amountToTransfer + 1);
        vm.prank(MOCK_ADDR_1);
        principalToken.transfer(MOCK_ADDR_2, transferData.amountToTransfer);
        transferData.ptBalanceAfterSender = principalToken.balanceOf(MOCK_ADDR_1);
        transferData.ptBalanceAfterReceiver = principalToken.balanceOf(MOCK_ADDR_2);
        assertEq(
            transferData.ptBalanceAfterSender + transferData.amountToTransfer,
            transferData.ptBalanceBeforeSender
        );
        assertEq(
            transferData.ptBalanceAfterReceiver,
            transferData.ptBalanceBeforeReceiver + transferData.amountToTransfer
        );

        // MOCK_ADDR_2 as the PT sender
        transferData.amountToTransfer = (5 * principalToken.balanceOf(MOCK_ADDR_2)) / 10;
        transferData.ptBalanceBeforeSender = principalToken.balanceOf(MOCK_ADDR_2);
        transferData.ptBalanceBeforeReceiver = principalToken.balanceOf(address(this));
        vm.prank(MOCK_ADDR_2);
        principalToken.transfer(address(this), transferData.amountToTransfer);
        transferData.ptBalanceAfterSender = principalToken.balanceOf(MOCK_ADDR_2);
        transferData.ptBalanceAfterReceiver = principalToken.balanceOf(address(this));
        assertEq(
            transferData.ptBalanceAfterSender + transferData.amountToTransfer,
            transferData.ptBalanceBeforeSender,
            "YieldToken balance of sender is wrong"
        );
        assertEq(
            transferData.ptBalanceAfterReceiver,
            transferData.ptBalanceBeforeReceiver + transferData.amountToTransfer,
            "YieldToken Balance of receiver is wrong"
        );

        transferData.amountToTransfer = (7 * principalToken.balanceOf(MOCK_ADDR_2)) / 10;
        transferData.ptBalanceBeforeSender = principalToken.balanceOf(MOCK_ADDR_2);
        transferData.ptBalanceBeforeReceiver = principalToken.balanceOf(MOCK_ADDR_1);
        vm.prank(MOCK_ADDR_2);
        principalToken.transfer(MOCK_ADDR_1, transferData.amountToTransfer);
        transferData.ptBalanceAfterSender = principalToken.balanceOf(MOCK_ADDR_2);
        transferData.ptBalanceAfterReceiver = principalToken.balanceOf(MOCK_ADDR_1);
        assertEq(
            transferData.ptBalanceAfterSender + transferData.amountToTransfer,
            transferData.ptBalanceBeforeSender
        );
        assertEq(
            transferData.ptBalanceAfterReceiver,
            transferData.ptBalanceBeforeReceiver + transferData.amountToTransfer
        );
    }

    function testTransferYTFails() public {
        uint256 amountToDeposit = 10e18;
        uint256 actual = _testDeposit(amountToDeposit, address(this));
        uint256 expected = principalToken.convertToPrincipal(amountToDeposit);
        assertEq(expected, actual, "After deposit balance is not equal to expected value"); // checks if balances are accurate after deposit

        uint256 amountToTransfer = yt.actualBalanceOf(address(this)) * 2;

        bytes memory revertData = abi.encodeWithSelector(
            bytes4(keccak256("ERC20InsufficientBalance(address,uint256,uint256)")),
            address(this),
            yt.actualBalanceOf(address(this)),
            amountToTransfer
        );
        vm.expectRevert(revertData);
        yt.transfer(MOCK_ADDR_1, amountToTransfer);
    }

    function testTransferPTFrom() public {
        uint256 amountToDeposit = 10e18;
        uint256 actual = _testDeposit(amountToDeposit, address(this));
        uint256 expected = principalToken.convertToPrincipal(amountToDeposit);
        assertEq(expected, actual, "After deposit balance is not equal to expected value"); // checks if balances are accurate after deposit
        principalToken.approve(address(this), 2e18);
        uint256 amountToTransfer = 1e18;
        uint256 expectedBalance2 = principalToken.balanceOf(address(this)) - amountToTransfer;
        principalToken.transferFrom(address(this), MOCK_ADDR_1, amountToTransfer); // transfers amountToTransfer with second argument being receiver
        uint256 expectedBalance1 = amountToTransfer;
        uint256 actualBalance1 = principalToken.balanceOf(MOCK_ADDR_1);
        uint256 actualBalance2 = principalToken.balanceOf(address(this));
        // checks if balances are accurate after deposit
        assertEq(
            expectedBalance1,
            actualBalance1,
            "After transfer balance is not equal to expected value"
        );
        assertEq(
            expectedBalance2,
            actualBalance2,
            "After transfer balance is not equal to expected value"
        );
    }

    /**
     * @dev Tests burning of yt tokens in various yield conditions. In particular, burning should update user's yield only if there have been some positive yield.
     */
    function testBurn() public {
        uint256 amountToDeposit = 100e18;
        _testDeposit(amountToDeposit, address(this));

        // only negative yield
        _increaseRate(-50);

        uint256 amountToBurn = yt.actualBalanceOf(address(this)) / 2;
        uint256 ytBalanceBefore = yt.actualBalanceOf(address(this));
        uint256 yieldOfUserInIBTBefore = principalToken.getCurrentYieldOfUserInIBT(address(this));

        yt.burn(amountToBurn);

        uint256 ytBalanceAfter = yt.actualBalanceOf(address(this));
        uint256 yieldOfUserInIBTAfter = principalToken.getCurrentYieldOfUserInIBT(address(this));

        assertEq(
            ytBalanceBefore,
            ytBalanceAfter + amountToBurn,
            "YieldToken Balance after burn is not equal to expected value"
        );
        assertEq(
            yieldOfUserInIBTBefore,
            yieldOfUserInIBTAfter,
            "Yield of user should be null with only negative yield"
        );

        (, uint256 oldIBTRate) = _getPTAndIBTRates();
        // only positive yield

        amountToBurn = yt.actualBalanceOf(address(this)) / 2;
        ytBalanceBefore = yt.actualBalanceOf(address(this));
        yieldOfUserInIBTBefore = principalToken.getCurrentYieldOfUserInIBT(address(this));

        _increaseRate(100);
        (uint256 newPTRate, uint256 newIBTRate) = _getPTAndIBTRates();

        yt.burn(amountToBurn);

        ytBalanceAfter = yt.actualBalanceOf(address(this));
        yieldOfUserInIBTAfter = principalToken.getCurrentYieldOfUserInIBT(address(this));

        assertEq(
            ytBalanceBefore,
            ytBalanceAfter + amountToBurn,
            "Balance after burn is not equal to expected value"
        );
        assertApproxEqAbs(
            yieldOfUserInIBTBefore +
                _convertToSharesWithRate(
                    _convertToAssetsWithRate(
                        _convertToSharesWithRate(
                            _convertToAssetsWithRate(
                                ytBalanceBefore,
                                newPTRate,
                                false,
                                true,
                                Math.Rounding.Floor
                            ),
                            oldIBTRate,
                            true,
                            true,
                            Math.Rounding.Floor
                        ),
                        (newIBTRate - oldIBTRate),
                        true,
                        true,
                        Math.Rounding.Floor
                    ),
                    newIBTRate,
                    true,
                    false,
                    Math.Rounding.Floor
                ),
            yieldOfUserInIBTAfter,
            1000,
            "yield of user in IBT after burn is not equal to expected value"
        );

        // both negative and positive yield variations
        oldIBTRate = newIBTRate;
        uint256 oldPTRate = newPTRate;
        _increaseRate(-10);
        // another user deposits (updating pt rate)
        amountToDeposit = 1e18;
        _testDeposit(amountToDeposit, MOCK_ADDR_1);

        amountToBurn = yt.actualBalanceOf(address(this)) / 2;
        ytBalanceBefore = yt.actualBalanceOf(address(this));
        yieldOfUserInIBTBefore = principalToken.getCurrentYieldOfUserInIBT(address(this));

        _increaseRate(33);
        (newPTRate, newIBTRate) = _getPTAndIBTRates();

        uint256 IBTLostThroughPTAsCollateralPerYT = _convertToSharesWithRate(
            _convertToAssetsWithRate(
                yt.actualBalanceOf(address(this)),
                (oldPTRate - newPTRate),
                false,
                true,
                Math.Rounding.Floor
            ),
            newIBTRate,
            true,
            false,
            Math.Rounding.Floor
        );
        uint256 IBTAddedInPositiveYield;
        if (newIBTRate >= oldIBTRate) {
            IBTAddedInPositiveYield =
                IBTLostThroughPTAsCollateralPerYT +
                _convertToSharesWithRate(
                    _convertToAssetsWithRate(
                        _convertToSharesWithRate(
                            _convertToAssetsWithRate(
                                yt.actualBalanceOf(address(this)),
                                oldPTRate,
                                false,
                                true,
                                Math.Rounding.Floor
                            ),
                            oldIBTRate,
                            true,
                            true,
                            Math.Rounding.Floor
                        ),
                        (newIBTRate - oldIBTRate),
                        true,
                        true,
                        Math.Rounding.Floor
                    ),
                    newIBTRate,
                    true,
                    false,
                    Math.Rounding.Floor
                );
        } else {
            revert();
        }

        yt.burn(amountToBurn);

        ytBalanceAfter = yt.actualBalanceOf(address(this));
        yieldOfUserInIBTAfter = principalToken.getCurrentYieldOfUserInIBT(address(this));

        assertEq(
            ytBalanceBefore,
            ytBalanceAfter + amountToBurn,
            "Balance after burn is not equal to expected value"
        );
        assertApproxEqAbs(
            yieldOfUserInIBTBefore + IBTAddedInPositiveYield,
            yieldOfUserInIBTAfter,
            10,
            "yield of user in IBT after burn is not equal to expected value"
        );
    }

    /**
     * @dev Tests burnWithoutUpdate of YTs in various yield conditions.
     * As opposed to the normal burn, calling burnWithoutUpdate of some YT amount should not update user yield
     * and hence erase the user yield generated for this amount since last update.
     */
    function testBurnWithoutUpdate() public {
        uint256 amountToDeposit = 100e18;
        uint256 actual = _testDeposit(amountToDeposit, address(this));
        uint256 expected = principalToken.convertToPrincipal(amountToDeposit);
        assertEq(expected, actual, "After deposit balance is not equal to expected value"); // checks if shares received by address(this) are the ones we expected

        // only negative yield
        _increaseRate(-50);

        uint256 amountToBurn = yt.actualBalanceOf(address(this)) / 2;
        uint256 ytBalanceBefore = yt.actualBalanceOf(address(this));
        uint256 yieldOfUserInIBTBefore = principalToken.getCurrentYieldOfUserInIBT(address(this));

        vm.prank(address(principalToken));
        yt.burnWithoutUpdate(address(this), amountToBurn);

        uint256 ytBalanceAfter = yt.actualBalanceOf(address(this));
        uint256 yieldOfUserInIBTAfter = principalToken.getCurrentYieldOfUserInIBT(address(this));

        assertEq(
            ytBalanceBefore,
            ytBalanceAfter + amountToBurn,
            "YieldToken Balance after burn is not equal to expected value"
        );
        assertEq(
            yieldOfUserInIBTBefore,
            yieldOfUserInIBTAfter,
            "yield of user in IBT after burn is not equal to expected value"
        );

        amountToBurn = yt.actualBalanceOf(address(this)) / 2;
        ytBalanceBefore = yt.actualBalanceOf(address(this));
        yieldOfUserInIBTBefore = principalToken.getCurrentYieldOfUserInIBT(address(this));

        // only positive yield
        _increaseRate(100);

        vm.prank(address(principalToken));
        yt.burnWithoutUpdate(address(this), amountToBurn);

        ytBalanceAfter = yt.actualBalanceOf(address(this));
        yieldOfUserInIBTAfter = principalToken.getCurrentYieldOfUserInIBT(address(this));

        assertEq(
            ytBalanceBefore,
            ytBalanceAfter + amountToBurn,
            "Balance after burn is not equal to expected value"
        );
        assertEq(
            yieldOfUserInIBTBefore,
            yieldOfUserInIBTAfter,
            "yield of user in IBT after burn is not equal to expected value"
        );

        // both negative and positive yield variations
        _increaseRate(-10);
        // another user deposits (updating pt rate)
        amountToDeposit = 1e18;
        _testDeposit(amountToDeposit, MOCK_ADDR_1);

        _increaseRate(33);

        amountToBurn = yt.actualBalanceOf(address(this)) / 2;
        ytBalanceBefore = yt.actualBalanceOf(address(this));
        yieldOfUserInIBTBefore = principalToken.getCurrentYieldOfUserInIBT(address(this));

        // burn half of user's YT
        vm.prank(address(principalToken));
        yt.burnWithoutUpdate(address(this), amountToBurn);

        ytBalanceAfter = yt.actualBalanceOf(address(this));
        yieldOfUserInIBTAfter = principalToken.getCurrentYieldOfUserInIBT(address(this));

        assertEq(
            ytBalanceBefore,
            ytBalanceAfter + amountToBurn,
            "Balance after burn is not equal to expected value"
        );
        assertEq(
            yieldOfUserInIBTBefore / 2,
            yieldOfUserInIBTAfter,
            "yield of user in IBT after burn is not equal to expected value"
        );
    }

    function testPauseInDeposit() public {
        underlying.approve(address(principalToken), 1e18);

        vm.expectEmit(false, false, false, true);
        emit Paused(scriptAdmin);
        vm.prank(scriptAdmin);
        principalToken.pause();

        bytes memory revertData = abi.encodeWithSignature("EnforcedPause()");
        vm.expectRevert(revertData);
        principalToken.deposit(1e18, address(this));

        vm.expectEmit(false, false, false, true);
        emit Unpaused(scriptAdmin);
        vm.prank(scriptAdmin);
        principalToken.unPause();

        uint256 amountToDeposit = 1e18;
        _testDeposit(amountToDeposit, address(this));
    }

    function testPauseInWithdraw() public {
        uint256 amountToDeposit = 1e18;
        _testDeposit(amountToDeposit, address(this));

        uint256 maxWithdraw = principalToken.maxWithdraw(address(this));

        vm.expectEmit(false, false, false, true);
        emit Paused(scriptAdmin);
        vm.prank(scriptAdmin);
        principalToken.pause();

        bytes memory revertData = abi.encodeWithSignature("EnforcedPause()");
        vm.expectRevert(revertData);
        principalToken.withdraw(maxWithdraw, MOCK_ADDR_1, address(this));

        vm.expectEmit(false, false, false, true);
        emit Unpaused(scriptAdmin);
        vm.prank(scriptAdmin);
        principalToken.unPause();

        _testWithdraw(maxWithdraw, MOCK_ADDR_1, address(this));
    }

    /**
     * @dev Tests claimYield for 2 users with deposit for 1st, then positive yield then deposit for 2nd
        then negative yield then positive yield (twice, one with more + and one with more -) and finish by claimYield
        for both users.
     */
    function testClaimYieldWithMultipleRateChanges() public {
        Rate memory rateData;
        YieldData memory yieldData;

        // deposits 10 underlying for user1 (MOCK_ADDR_1)
        _testDeposit(10e18, MOCK_ADDR_1);

        (rateData.oldPTRate, rateData.oldIBTRate) = _getPTAndIBTRates();
        rateData.ratePT0 = rateData.oldPTRate;
        rateData.rateIBT0 = rateData.oldIBTRate;
        yieldData.oldYieldUser1 = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_1);
        assertEq(yieldData.oldYieldUser1, 0, "Yield of user 1 is wrong");

        _increaseRate(50);

        (, rateData.newIBTRate) = _getPTAndIBTRates();

        yieldData.expectedYieldInIBTUser1 = _convertPTSharesToIBTsWithRates(
            yt.actualBalanceOf(MOCK_ADDR_1).toRay(18),
            rateData.oldPTRate,
            rateData.oldIBTRate,
            false
        ).mulDiv((rateData.newIBTRate - rateData.oldIBTRate), rateData.newIBTRate).fromRay(18);
        yieldData.actualYieldUser1 = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_1);
        assertApproxEqAbs(
            yieldData.actualYieldUser1,
            yieldData.oldYieldUser1 + yieldData.expectedYieldInIBTUser1,
            1000,
            "After rate change yield of user1 is not equal to expected value"
        );

        // update variables
        rateData.oldIBTRate = rateData.newIBTRate;
        yieldData.oldYieldUser1 = yieldData.actualYieldUser1;

        // deposits 2 underlying for user2 (MOCK_ADDR_2)
        _testDeposit(2e18, MOCK_ADDR_2);

        // increase time
        vm.warp(block.timestamp + 1000);

        yieldData.oldYieldUser2 = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_2);
        assertEq(yieldData.oldYieldUser2, 0, "Yield of user 2 is wrong");

        _increaseRate(-10);

        (rateData.newPTRate, rateData.newIBTRate) = _getPTAndIBTRates();

        // computes the yield generated by user1 after rate increase then decrease
        uint256 assetLostThroughDepegForYTUser1;
        if (rateData.newIBTRate > rateData.rateIBT0) {
            // more positive yield
            assetLostThroughDepegForYTUser1 = _convertToAssetsWithRate(
                yt.actualBalanceOf(MOCK_ADDR_1),
                (rateData.ratePT0 - rateData.newPTRate),
                false,
                true,
                Math.Rounding.Floor
            );
            yieldData.yieldInUnderlyingUser1 = _convertToAssetsWithRate(
                _convertPTSharesToIBTsWithRates(
                    yt.actualBalanceOf(MOCK_ADDR_1).toRay(18),
                    rateData.ratePT0,
                    rateData.rateIBT0,
                    false
                ),
                (rateData.newIBTRate - rateData.rateIBT0),
                true,
                true,
                Math.Rounding.Floor
            );
            yieldData.expectedYieldInIBTUser1 = _convertToSharesWithRate(
                assetLostThroughDepegForYTUser1 + yieldData.yieldInUnderlyingUser1,
                rateData.newIBTRate,
                true,
                false,
                Math.Rounding.Floor
            );
        } else {
            // more negative yield
            assetLostThroughDepegForYTUser1 = _convertToAssetsWithRate(
                yt.actualBalanceOf(MOCK_ADDR_1),
                (rateData.ratePT0 - rateData.newPTRate),
                false,
                true,
                Math.Rounding.Floor
            );
            yieldData.yieldInUnderlyingUser1 = _convertToAssetsWithRate(
                _convertPTSharesToIBTsWithRates(
                    yt.actualBalanceOf(MOCK_ADDR_1).toRay(18),
                    rateData.ratePT0,
                    rateData.rateIBT0,
                    false
                ),
                (rateData.rateIBT0 - rateData.newIBTRate),
                true,
                true,
                Math.Rounding.Floor
            );
            yieldData.expectedYieldInIBTUser1 = _convertToSharesWithRate(
                assetLostThroughDepegForYTUser1 - yieldData.yieldInUnderlyingUser1,
                rateData.newIBTRate,
                true,
                false,
                Math.Rounding.Floor
            );
        }

        yieldData.actualYieldUser1 = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_1);
        yieldData.actualYieldUser2 = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_2);
        assertLe(
            yieldData.actualYieldUser1,
            yieldData.oldYieldUser1,
            "Yield of user 1 in IBT should have decreased"
        );
        assertApproxEqAbs(
            yieldData.actualYieldUser1,
            yieldData.expectedYieldInIBTUser1,
            1000,
            "After rate change yield of user1 is not equal to expected value 2"
        );
        // only negative yield for user 2 so yield in IBT should remain the same
        assertEq(
            yieldData.actualYieldUser2,
            yieldData.oldYieldUser2,
            "Yield of user 2 in IBT should not have changed"
        );

        // update variables
        rateData.oldIBTRate = rateData.newIBTRate;
        yieldData.oldYieldUser1 = yieldData.actualYieldUser1;
        yieldData.oldYieldUser2 = yieldData.actualYieldUser2;
        rateData.oldPTRate = principalToken.getPTRate();

        // user1 transfer 3/4 of his YT to user 2
        vm.startPrank(MOCK_ADDR_1);
        yt.transfer(MOCK_ADDR_2, (yt.actualBalanceOf(MOCK_ADDR_1) * 3) / 4);
        vm.stopPrank();

        // Both + and - yield but more - (in proportion)
        // increase time
        vm.warp(block.timestamp + 1000);
        // rate +
        _increaseRate(20);
        // increase time
        vm.warp(block.timestamp + 1000);
        // more rate - (the same - will actually impact more than +)
        _increaseRate(-20);

        (rateData.newPTRate, rateData.newIBTRate) = _getPTAndIBTRates();

        // computes the yield generated by user1 and user2 through rate variations
        uint256 underlyingLostThroughDepegForYTUser1 = _convertToAssetsWithRate(
            yt.actualBalanceOf(MOCK_ADDR_1),
            (rateData.oldPTRate - rateData.newPTRate),
            false,
            true,
            Math.Rounding.Floor
        );
        yieldData.yieldInUnderlyingUser1 = _convertToAssetsWithRate(
            _convertPTSharesToIBTsWithRates(
                yt.actualBalanceOf(MOCK_ADDR_1).toRay(18),
                rateData.oldPTRate,
                rateData.oldIBTRate,
                false
            ),
            (rateData.oldIBTRate - rateData.newIBTRate),
            true,
            true,
            Math.Rounding.Floor
        );
        yieldData.expectedYieldInIBTUser1 = _convertToSharesWithRate(
            underlyingLostThroughDepegForYTUser1 - yieldData.yieldInUnderlyingUser1,
            rateData.newIBTRate,
            true,
            false,
            Math.Rounding.Floor
        );
        yieldData.actualYieldUser1 = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_1);

        uint256 underlyingLostThroughDepegForYTUser2 = _convertToAssetsWithRate(
            yt.actualBalanceOf(MOCK_ADDR_2),
            (rateData.oldPTRate - rateData.newPTRate),
            false,
            true,
            Math.Rounding.Floor
        );
        yieldData.yieldInUnderlyingUser2 = _convertToAssetsWithRate(
            _convertPTSharesToIBTsWithRates(
                yt.actualBalanceOf(MOCK_ADDR_2).toRay(18),
                rateData.oldPTRate,
                rateData.oldIBTRate,
                false
            ),
            (rateData.oldIBTRate - rateData.newIBTRate),
            true,
            true,
            Math.Rounding.Floor
        );
        yieldData.expectedYieldInIBTUser2 = _convertToSharesWithRate(
            underlyingLostThroughDepegForYTUser2 - yieldData.yieldInUnderlyingUser2,
            rateData.newIBTRate,
            true,
            false,
            Math.Rounding.Floor
        );
        yieldData.actualYieldUser2 = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_2);

        assertApproxEqAbs(
            yieldData.actualYieldUser1,
            yieldData.oldYieldUser1 + yieldData.expectedYieldInIBTUser1,
            1000,
            "After rate change yield of user1 is not equal to expected value"
        );

        assertApproxEqAbs(
            yieldData.actualYieldUser2,
            yieldData.oldYieldUser2 + yieldData.expectedYieldInIBTUser2,
            1000,
            "After rate change yield of user2 is not equal to expected value"
        );

        // update variables
        rateData.oldIBTRate = rateData.newIBTRate;
        rateData.oldPTRate = rateData.newPTRate;
        yieldData.oldYieldUser1 = yieldData.actualYieldUser1;
        yieldData.oldYieldUser2 = yieldData.actualYieldUser2;

        // user1 transfer 1/10 of his YT to user 2
        vm.startPrank(MOCK_ADDR_1);
        yt.transfer(MOCK_ADDR_2, yt.actualBalanceOf(MOCK_ADDR_1) / 10);
        vm.stopPrank();

        // Both + and - yield but more +
        // increase time
        vm.warp(block.timestamp + 1000);
        // rate -
        _increaseRate(-10);
        // increase time
        vm.warp(block.timestamp + 1000);
        // more rate +
        _increaseRate(100);

        (rateData.newPTRate, rateData.newIBTRate) = _getPTAndIBTRates();

        underlyingLostThroughDepegForYTUser1 = _convertToAssetsWithRate(
            yt.actualBalanceOf(MOCK_ADDR_1),
            (rateData.oldPTRate - rateData.newPTRate),
            false,
            true,
            Math.Rounding.Floor
        );
        yieldData.yieldInUnderlyingUser1 = _convertToAssetsWithRate(
            _convertPTSharesToIBTsWithRates(
                yt.actualBalanceOf(MOCK_ADDR_1).toRay(18),
                rateData.oldPTRate,
                rateData.oldIBTRate,
                false
            ),
            (rateData.newIBTRate - rateData.oldIBTRate),
            true,
            true,
            Math.Rounding.Floor
        );
        yieldData.expectedYieldInIBTUser1 = _convertToSharesWithRate(
            underlyingLostThroughDepegForYTUser1 + yieldData.yieldInUnderlyingUser1,
            rateData.newIBTRate,
            true,
            false,
            Math.Rounding.Floor
        );
        yieldData.actualYieldUser1 = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_1);

        underlyingLostThroughDepegForYTUser2 = _convertToAssetsWithRate(
            yt.actualBalanceOf(MOCK_ADDR_2),
            (rateData.oldPTRate - rateData.newPTRate),
            false,
            true,
            Math.Rounding.Floor
        );
        yieldData.yieldInUnderlyingUser2 = _convertToAssetsWithRate(
            _convertPTSharesToIBTsWithRates(
                yt.actualBalanceOf(MOCK_ADDR_2).toRay(18),
                rateData.oldPTRate,
                rateData.oldIBTRate,
                false
            ),
            (rateData.newIBTRate - rateData.oldIBTRate),
            true,
            true,
            Math.Rounding.Floor
        );
        yieldData.expectedYieldInIBTUser2 = _convertToSharesWithRate(
            underlyingLostThroughDepegForYTUser2 + yieldData.yieldInUnderlyingUser2,
            rateData.newIBTRate,
            true,
            false,
            Math.Rounding.Floor
        );
        yieldData.actualYieldUser2 = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_2);

        assertApproxEqAbs(
            yieldData.actualYieldUser1,
            yieldData.oldYieldUser1 + yieldData.expectedYieldInIBTUser1,
            1000,
            "After rate change yield of user1 is not equal to expected value"
        );
        assertApproxEqAbs(
            yieldData.actualYieldUser2,
            yieldData.oldYieldUser2 + yieldData.expectedYieldInIBTUser2,
            1000,
            "After rate change yield of user2 is not equal to expected value"
        );

        uint256 underlyingBalanceBefore = underlying.balanceOf(MOCK_ADDR_1);
        vm.prank(MOCK_ADDR_1);
        principalToken.claimYield(MOCK_ADDR_1);
        assertApproxEqAbs(
            underlying.balanceOf(MOCK_ADDR_1),
            underlyingBalanceBefore + ibt.previewRedeem(yieldData.actualYieldUser1),
            1000,
            "After Claiming yield balance is not equal to expected value"
        );

        underlyingBalanceBefore = underlying.balanceOf(MOCK_ADDR_2);
        vm.prank(MOCK_ADDR_2);
        principalToken.claimYield(MOCK_ADDR_2);
        assertApproxEqAbs(
            underlying.balanceOf(MOCK_ADDR_2),
            underlyingBalanceBefore + ibt.previewRedeem(yieldData.actualYieldUser2),
            1000,
            "After Claiming yield balance is not equal to expected value"
        );
    }

    /**
     * @dev Fuzz tests claimYield for 2 users with deposit for 1st, then positive yield then deposit for 2nd
        then negative yield then positive yield (twice, one with more + and one with more -) and finish by claimYield
        for both users.
     */
    function testClaimYieldFuzz(
        uint256 amountToDeposit,
        uint256 amountToTransfer,
        uint16 _rate
    ) public {
        Rate memory rateData;
        YieldData memory yieldData;

        int256 rate = int256(bound(_rate, 0, 99));
        amountToDeposit = bound(amountToDeposit, 0, 1000e18);

        // deposits amountToDeposit underlying for user1 (MOCK_ADDR_1)
        _testDeposit(amountToDeposit, MOCK_ADDR_1);

        (rateData.oldPTRate, rateData.oldIBTRate) = _getPTAndIBTRates();
        rateData.ratePT0 = rateData.oldPTRate;
        rateData.rateIBT0 = rateData.oldIBTRate;
        yieldData.oldYieldUser1 = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_1);
        assertEq(yieldData.oldYieldUser1, 0, "Yield of user 1 is wrong");

        _increaseRate(rate * 3);

        (, rateData.newIBTRate) = _getPTAndIBTRates();

        // computes the yield generated by user1 after rate increase
        yieldData.expectedYieldInIBTUser1 = _convertPTSharesToIBTsWithRates(
            yt.actualBalanceOf(MOCK_ADDR_1).toRay(18),
            rateData.oldPTRate,
            rateData.oldIBTRate,
            false
        ).mulDiv((rateData.newIBTRate - rateData.oldIBTRate), rateData.newIBTRate).fromRay(18);
        yieldData.actualYieldUser1 = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_1);

        assertApproxEqAbs(
            yieldData.actualYieldUser1,
            yieldData.expectedYieldInIBTUser1,
            1000,
            "After rate change yield of user1 is not equal to expected value 1"
        );

        // update variables
        rateData.oldIBTRate = rateData.newIBTRate;
        yieldData.oldYieldUser1 = yieldData.actualYieldUser1;

        // deposits amountToDeposit / 5 underlying for user2 (MOCK_ADDR_2)
        _testDeposit(amountToDeposit / 5, MOCK_ADDR_2);

        yieldData.oldYieldUser2 = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_2);

        // increase time
        vm.warp(block.timestamp + 1000);

        assertEq(yieldData.oldYieldUser2, 0, "Yield of user 2 is wrong");

        _increaseRate(-1 * rate);

        (rateData.newPTRate, rateData.newIBTRate) = _getPTAndIBTRates();

        // computes the yield generated by user1 after rate increase then decrease
        uint256 assetLostThroughDepegForYTUser1;
        if (rateData.newIBTRate > rateData.rateIBT0) {
            // more positive yield
            assetLostThroughDepegForYTUser1 = _convertToAssetsWithRate(
                yt.actualBalanceOf(MOCK_ADDR_1),
                (rateData.ratePT0 - rateData.newPTRate),
                false,
                true,
                Math.Rounding.Floor
            );
            yieldData.yieldInUnderlyingUser1 = _convertToAssetsWithRate(
                _convertPTSharesToIBTsWithRates(
                    yt.actualBalanceOf(MOCK_ADDR_1).toRay(18),
                    rateData.ratePT0,
                    rateData.rateIBT0,
                    false
                ),
                (rateData.newIBTRate - rateData.rateIBT0),
                true,
                true,
                Math.Rounding.Floor
            );
            yieldData.expectedYieldInIBTUser1 = _convertToSharesWithRate(
                assetLostThroughDepegForYTUser1 + yieldData.yieldInUnderlyingUser1,
                rateData.newIBTRate,
                true,
                false,
                Math.Rounding.Floor
            );
        } else {
            // more negative yield
            assetLostThroughDepegForYTUser1 = _convertToAssetsWithRate(
                yt.actualBalanceOf(MOCK_ADDR_1),
                (rateData.ratePT0 - rateData.newPTRate),
                false,
                true,
                Math.Rounding.Floor
            );
            yieldData.yieldInUnderlyingUser1 = _convertToAssetsWithRate(
                _convertPTSharesToIBTsWithRates(
                    yt.actualBalanceOf(MOCK_ADDR_1).toRay(18),
                    rateData.ratePT0,
                    rateData.rateIBT0,
                    false
                ),
                (rateData.rateIBT0 - rateData.newIBTRate),
                true,
                true,
                Math.Rounding.Floor
            );
            yieldData.expectedYieldInIBTUser1 = _convertToSharesWithRate(
                assetLostThroughDepegForYTUser1 - yieldData.yieldInUnderlyingUser1,
                rateData.newIBTRate,
                true,
                false,
                Math.Rounding.Floor
            );
        }

        yieldData.actualYieldUser1 = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_1);
        yieldData.actualYieldUser2 = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_2);
        assertLe(
            yieldData.actualYieldUser1,
            yieldData.oldYieldUser1,
            "Yield of user 1 in IBT should have decreased"
        );
        assertApproxEqAbs(
            yieldData.actualYieldUser1,
            yieldData.expectedYieldInIBTUser1,
            1000 + ibt.convertToShares(100), // taking into account the safety bound
            "After rate change yield of user1 is not equal to expected value 2"
        );
        // only negative yield for user 2 so yield in IBT should remain the same
        assertEq(
            yieldData.actualYieldUser2,
            yieldData.oldYieldUser2,
            "Yield of user 2 in IBT should not have changed"
        );

        // update variables
        rateData.oldIBTRate = rateData.newIBTRate;
        yieldData.oldYieldUser1 = yieldData.actualYieldUser1;
        yieldData.oldYieldUser2 = yieldData.actualYieldUser2;
        rateData.oldPTRate = principalToken.getPTRate();

        // user1 transfer some YTs to user 2
        amountToTransfer = bound(amountToTransfer, 0, yt.actualBalanceOf(MOCK_ADDR_1).mulDiv(3, 4));
        vm.startPrank(MOCK_ADDR_1);
        yt.transfer(MOCK_ADDR_2, amountToTransfer);
        vm.stopPrank();

        // Both + and - yield but more - (in proportion)
        // increase time
        vm.warp(block.timestamp + 1000);
        // rate +
        _increaseRate(rate / 10);
        // increase time
        vm.warp(block.timestamp + 1000);
        // more rate - (the same - will actually impact more than +)
        _increaseRate((-1 * rate) / 10);

        (rateData.newPTRate, rateData.newIBTRate) = _getPTAndIBTRates();

        // computes the yield generated by user1 and user2 through rate variations
        uint256 underlyingLostThroughDepegForYTUser1 = _convertToAssetsWithRate(
            yt.actualBalanceOf(MOCK_ADDR_1),
            (rateData.oldPTRate - rateData.newPTRate),
            false,
            true,
            Math.Rounding.Floor
        );
        yieldData.yieldInUnderlyingUser1 = _convertToAssetsWithRate(
            _convertPTSharesToIBTsWithRates(
                yt.actualBalanceOf(MOCK_ADDR_1).toRay(18),
                rateData.oldPTRate,
                rateData.oldIBTRate,
                false
            ),
            (rateData.oldIBTRate - rateData.newIBTRate),
            true,
            true,
            Math.Rounding.Floor
        );
        yieldData.expectedYieldInIBTUser1 = _convertToSharesWithRate(
            underlyingLostThroughDepegForYTUser1 - yieldData.yieldInUnderlyingUser1,
            rateData.newIBTRate,
            true,
            false,
            Math.Rounding.Floor
        );
        yieldData.actualYieldUser1 = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_1);

        uint256 underlyingLostThroughDepegForYTUser2 = _convertToAssetsWithRate(
            yt.actualBalanceOf(MOCK_ADDR_2),
            (rateData.oldPTRate - rateData.newPTRate),
            false,
            true,
            Math.Rounding.Floor
        );
        yieldData.yieldInUnderlyingUser2 = _convertToAssetsWithRate(
            _convertPTSharesToIBTsWithRates(
                yt.actualBalanceOf(MOCK_ADDR_2).toRay(18),
                rateData.oldPTRate,
                rateData.oldIBTRate,
                false
            ),
            (rateData.oldIBTRate - rateData.newIBTRate),
            true,
            true,
            Math.Rounding.Floor
        );
        yieldData.expectedYieldInIBTUser2 = _convertToSharesWithRate(
            underlyingLostThroughDepegForYTUser2 - yieldData.yieldInUnderlyingUser2,
            rateData.newIBTRate,
            true,
            false,
            Math.Rounding.Floor
        );
        yieldData.actualYieldUser2 = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_2);

        assertApproxEqAbs(
            yieldData.actualYieldUser1,
            yieldData.oldYieldUser1 + yieldData.expectedYieldInIBTUser1,
            1000,
            "After rate change yield of user1 is not equal to expected value 3"
        );
        assertEq(
            yieldData.actualYieldUser1,
            yieldData.oldYieldUser1,
            "After rate change yield of user1 is not equal to expected value 4"
        );

        assertApproxEqAbs(
            yieldData.actualYieldUser2,
            yieldData.oldYieldUser2 + yieldData.expectedYieldInIBTUser2,
            1000,
            "After rate change yield of user2 is not equal to expected value 1"
        );
        assertEq(
            yieldData.actualYieldUser2,
            yieldData.oldYieldUser2,
            "After rate change yield of user2 is not equal to expected value 2"
        );

        // update variables
        rateData.oldIBTRate = rateData.newIBTRate;
        rateData.oldPTRate = rateData.newPTRate;
        yieldData.oldYieldUser1 = yieldData.actualYieldUser1;
        yieldData.oldYieldUser2 = yieldData.actualYieldUser2;

        // user1 transfer some YTs to user 2
        amountToTransfer = bound(amountToTransfer, 0, yt.actualBalanceOf(MOCK_ADDR_1));
        vm.startPrank(MOCK_ADDR_1);
        yt.transfer(MOCK_ADDR_2, amountToTransfer);
        vm.stopPrank();

        // Both + and - yield but more +
        // increase time
        vm.warp(block.timestamp + 1000);
        // rate -
        _increaseRate(-1 * rate);
        // increase time
        vm.warp(block.timestamp + 1000);
        // more rate +
        _increaseRate(100 * rate);

        (rateData.newPTRate, rateData.newIBTRate) = _getPTAndIBTRates();

        // computes the yield generated by user1 and user2 through rate variations
        underlyingLostThroughDepegForYTUser1 = _convertToAssetsWithRate(
            yt.actualBalanceOf(MOCK_ADDR_1),
            (rateData.oldPTRate - rateData.newPTRate),
            false,
            true,
            Math.Rounding.Floor
        );
        yieldData.yieldInUnderlyingUser1 = _convertToAssetsWithRate(
            _convertPTSharesToIBTsWithRates(
                yt.actualBalanceOf(MOCK_ADDR_1).toRay(18),
                rateData.oldPTRate,
                rateData.oldIBTRate,
                false
            ),
            (rateData.newIBTRate - rateData.oldIBTRate),
            true,
            true,
            Math.Rounding.Floor
        );
        yieldData.expectedYieldInIBTUser1 = _convertToSharesWithRate(
            underlyingLostThroughDepegForYTUser1 + yieldData.yieldInUnderlyingUser1,
            rateData.newIBTRate,
            true,
            false,
            Math.Rounding.Floor
        );
        yieldData.actualYieldUser1 = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_1);

        underlyingLostThroughDepegForYTUser2 = _convertToAssetsWithRate(
            yt.actualBalanceOf(MOCK_ADDR_2),
            (rateData.oldPTRate - rateData.newPTRate),
            false,
            true,
            Math.Rounding.Floor
        );
        yieldData.yieldInUnderlyingUser2 = _convertToAssetsWithRate(
            _convertPTSharesToIBTsWithRates(
                yt.actualBalanceOf(MOCK_ADDR_2).toRay(18),
                rateData.oldPTRate,
                rateData.oldIBTRate,
                false
            ),
            (rateData.newIBTRate - rateData.oldIBTRate),
            true,
            true,
            Math.Rounding.Floor
        );
        yieldData.expectedYieldInIBTUser2 = _convertToSharesWithRate(
            underlyingLostThroughDepegForYTUser2 + yieldData.yieldInUnderlyingUser2,
            rateData.newIBTRate,
            true,
            false,
            Math.Rounding.Floor
        );
        yieldData.actualYieldUser2 = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_2);

        assertApproxEqAbs(
            yieldData.actualYieldUser1,
            yieldData.oldYieldUser1 + yieldData.expectedYieldInIBTUser1,
            1000,
            "After rate change yield of user1 is not equal to expected value 5"
        );

        assertApproxEqAbs(
            yieldData.actualYieldUser2,
            yieldData.oldYieldUser2 + yieldData.expectedYieldInIBTUser2,
            1000,
            "After rate change yield of user1 is not equal to expected value 6"
        );

        // user1 claims his yield
        uint256 underlyingBalanceBefore = underlying.balanceOf(MOCK_ADDR_1);
        vm.prank(MOCK_ADDR_1);
        principalToken.claimYield(MOCK_ADDR_1);
        assertApproxEqAbs(
            underlying.balanceOf(MOCK_ADDR_1),
            underlyingBalanceBefore + ibt.previewRedeem(yieldData.actualYieldUser1),
            1000,
            "After Claiming yield balance is not equal to expected value 7"
        );

        // user2 claims his yield
        underlyingBalanceBefore = underlying.balanceOf(MOCK_ADDR_2);
        vm.prank(MOCK_ADDR_2);
        principalToken.claimYield(MOCK_ADDR_2);
        assertApproxEqAbs(
            underlying.balanceOf(MOCK_ADDR_2),
            underlyingBalanceBefore + ibt.previewRedeem(yieldData.actualYieldUser2),
            1000,
            "After Claiming yield balance is not equal to expected value 8"
        );
    }

    /**
     * @dev Tests Claim Yield of amount for 4 users with positive yield.
     */
    function testClaimPositiveYieldOfAmount() public {
        Rate memory rateData;
        YieldData memory yieldData;

        // deposit 1 underlying for user1 and user2
        assertEq(
            _testDeposit(1e18, MOCK_ADDR_1),
            _testDeposit(1e18, MOCK_ADDR_2),
            "received shares should be the same for user1 and user2"
        );

        yieldData.oldYieldUser1 = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_1);
        assertEq(yieldData.oldYieldUser1, 0, "Yield of user 1 is wrong");
        yieldData.oldYieldUser2 = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_2);
        assertEq(yieldData.oldYieldUser2, 0, "Yield of user 2 is wrong");
        rateData.oldIBTRate = _toRay(ibt.previewRedeem(IBT_UNIT), 18);
        rateData.oldPTRate = principalToken.getPTRate();
        // increase rate and time
        _increaseRate(10);
        vm.warp(block.timestamp + 100);

        (, rateData.newIBTRate) = _getPTAndIBTRates();

        // computing yield generated by last step
        yieldData.expectedYieldInIBTUser1 = _convertPTSharesToIBTsWithRates(
            yt.actualBalanceOf(MOCK_ADDR_1).toRay(18),
            rateData.oldPTRate,
            rateData.oldIBTRate,
            false
        ).mulDiv((rateData.newIBTRate - rateData.oldIBTRate), rateData.newIBTRate).fromRay(18);
        yieldData.actualYieldUser1 = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_1);

        yieldData.expectedYieldInIBTUser2 = _convertPTSharesToIBTsWithRates(
            yt.actualBalanceOf(MOCK_ADDR_2).toRay(18),
            rateData.oldPTRate,
            rateData.oldIBTRate,
            false
        ).mulDiv((rateData.newIBTRate - rateData.oldIBTRate), rateData.newIBTRate).fromRay(18);
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
        vm.startPrank(MOCK_ADDR_2);
        principalToken.claimYield(MOCK_ADDR_2);
        vm.stopPrank();
        assertEq(
            underlying.balanceOf(MOCK_ADDR_2),
            yieldData.underlyingBalanceBefore + ibt.previewRedeem(yieldData.actualYieldUser2),
            "After claiming yield, underlying balance of user2 is not equal to expected value"
        );
        yieldData.actualYieldUser2 = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_2);
        assertEq(
            yieldData.actualYieldUser2,
            0,
            "After claiming yield, stored yield of user2 is not equal to expected value"
        );

        yieldData.oldYieldUser2 = yieldData.actualYieldUser2;

        // increase time (no rate change)
        vm.warp(block.timestamp + 100);

        yieldData.actualYieldUser2 = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_2);
        assertEq(
            yieldData.oldYieldUser2,
            yieldData.actualYieldUser2,
            "Yield of user2 should not have changed"
        );

        rateData.oldIBTRate = rateData.newIBTRate;

        // deposit 2 underlying for user3 and user4
        assertEq(
            _testDeposit(2e18, MOCK_ADDR_3),
            _testDeposit(2e18, MOCK_ADDR_4),
            "received shares should be the same for user3 and user4"
        );

        yieldData.oldYieldUser3 = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_3);
        yieldData.oldYieldUser4 = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_4);
        assertEq(yieldData.oldYieldUser3, 0, "Yield of user3 is wrong");
        assertEq(yieldData.oldYieldUser4, 0, "Yield of user4 is wrong");

        // increase time and rate
        vm.warp(block.timestamp + 100);
        _increaseRate(50);

        (, rateData.newIBTRate) = _getPTAndIBTRates();

        // computes yield for the last step for the 4 users
        yieldData.expectedYieldInIBTUser1 = _convertPTSharesToIBTsWithRates(
            yt.actualBalanceOf(MOCK_ADDR_1).toRay(18),
            rateData.oldPTRate,
            rateData.oldIBTRate,
            false
        ).mulDiv((rateData.newIBTRate - rateData.oldIBTRate), rateData.newIBTRate).fromRay(18);
        yieldData.actualYieldUser1 = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_1);

        yieldData.expectedYieldInIBTUser2 = _convertPTSharesToIBTsWithRates(
            yt.actualBalanceOf(MOCK_ADDR_2).toRay(18),
            rateData.oldPTRate,
            rateData.oldIBTRate,
            false
        ).mulDiv((rateData.newIBTRate - rateData.oldIBTRate), rateData.newIBTRate).fromRay(18);
        yieldData.actualYieldUser2 = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_2);

        yieldData.expectedYieldInIBTUser3 = _convertPTSharesToIBTsWithRates(
            yt.actualBalanceOf(MOCK_ADDR_3).toRay(18),
            rateData.oldPTRate,
            rateData.oldIBTRate,
            false
        ).mulDiv((rateData.newIBTRate - rateData.oldIBTRate), rateData.newIBTRate).fromRay(18);
        yieldData.actualYieldUser3 = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_3);

        yieldData.expectedYieldInIBTUser4 = _convertPTSharesToIBTsWithRates(
            yt.actualBalanceOf(MOCK_ADDR_4).toRay(18),
            rateData.oldPTRate,
            rateData.oldIBTRate,
            false
        ).mulDiv((rateData.newIBTRate - rateData.oldIBTRate), rateData.newIBTRate).fromRay(18);
        yieldData.actualYieldUser4 = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_4);

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
        yieldData.underlyingBalanceBefore = underlying.balanceOf(MOCK_ADDR_2);
        vm.startPrank(MOCK_ADDR_2);
        principalToken.claimYield(MOCK_ADDR_2);
        vm.stopPrank();
        assertEq(
            underlying.balanceOf(MOCK_ADDR_2),
            yieldData.underlyingBalanceBefore + ibt.previewRedeem(yieldData.actualYieldUser2),
            "After claiming yield, underlying balance of user2 is not equal to expected value"
        );

        yieldData.actualYieldUser2 = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_2);
        assertEq(
            yieldData.actualYieldUser2,
            0,
            "After Claiming yield, current yield of user2 should be 0"
        );
        yieldData.oldYieldUser2 = yieldData.actualYieldUser2;

        // user 3 claims his yield
        yieldData.underlyingBalanceBefore = underlying.balanceOf(MOCK_ADDR_3);
        vm.startPrank(MOCK_ADDR_3);
        principalToken.claimYield(MOCK_ADDR_3);
        vm.stopPrank();
        assertEq(
            underlying.balanceOf(MOCK_ADDR_3),
            yieldData.underlyingBalanceBefore + ibt.previewRedeem(yieldData.actualYieldUser3),
            "After claiming yield, underlying balance of user3 is not equal to expected value"
        );
        yieldData.actualYieldUser3 = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_3);
        assertEq(
            yieldData.actualYieldUser3,
            0,
            "After Claiming yield, current yield of user3 should be 0"
        );
        yieldData.oldYieldUser3 = yieldData.actualYieldUser3;

        rateData.oldIBTRate = rateData.newIBTRate;

        // increase time and rate
        vm.warp(block.timestamp + 100);
        _increaseRate(10);

        (, rateData.newIBTRate) = _getPTAndIBTRates();

        // computes the yield generated by the last step for the four users
        yieldData.expectedYieldInIBTUser1 = _convertPTSharesToIBTsWithRates(
            yt.actualBalanceOf(MOCK_ADDR_1).toRay(18),
            rateData.oldPTRate,
            rateData.oldIBTRate,
            false
        ).mulDiv((rateData.newIBTRate - rateData.oldIBTRate), rateData.newIBTRate).fromRay(18);
        yieldData.actualYieldUser1 = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_1);

        yieldData.expectedYieldInIBTUser2 = _convertPTSharesToIBTsWithRates(
            yt.actualBalanceOf(MOCK_ADDR_2).toRay(18),
            rateData.oldPTRate,
            rateData.oldIBTRate,
            false
        ).mulDiv((rateData.newIBTRate - rateData.oldIBTRate), rateData.newIBTRate).fromRay(18);
        yieldData.actualYieldUser2 = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_2);

        yieldData.expectedYieldInIBTUser3 = _convertPTSharesToIBTsWithRates(
            yt.actualBalanceOf(MOCK_ADDR_3).toRay(18),
            rateData.oldPTRate,
            rateData.oldIBTRate,
            false
        ).mulDiv((rateData.newIBTRate - rateData.oldIBTRate), rateData.newIBTRate).fromRay(18);
        yieldData.actualYieldUser3 = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_3);

        yieldData.expectedYieldInIBTUser4 = _convertPTSharesToIBTsWithRates(
            yt.actualBalanceOf(MOCK_ADDR_4).toRay(18),
            rateData.oldPTRate,
            rateData.oldIBTRate,
            false
        ).mulDiv((rateData.newIBTRate - rateData.oldIBTRate), rateData.newIBTRate).fromRay(18);
        yieldData.actualYieldUser4 = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_4);

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
        yieldData.underlyingBalanceBefore = underlying.balanceOf(MOCK_ADDR_2);
        vm.startPrank(MOCK_ADDR_2);
        principalToken.claimYield(MOCK_ADDR_2);
        vm.stopPrank();
        assertEq(
            underlying.balanceOf(MOCK_ADDR_2),
            yieldData.underlyingBalanceBefore + ibt.previewRedeem(yieldData.actualYieldUser2),
            "After claiming yield, underlying balance of user2 is not equal to expected value"
        );

        yieldData.actualYieldUser2 = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_2);
        assertEq(
            yieldData.actualYieldUser2,
            0,
            "After claiming yield, current yield of user2 should be 0"
        );
        yieldData.oldYieldUser2 = yieldData.actualYieldUser2;

        rateData.oldIBTRate = rateData.newIBTRate;

        // increase time and rate
        vm.warp(block.timestamp + 100);
        _increaseRate(25);

        (, rateData.newIBTRate) = _getPTAndIBTRates();

        // computes the yield of the last step for the 4 users
        yieldData.expectedYieldInIBTUser1 = _convertPTSharesToIBTsWithRates(
            yt.actualBalanceOf(MOCK_ADDR_1).toRay(18),
            rateData.oldPTRate,
            rateData.oldIBTRate,
            false
        ).mulDiv((rateData.newIBTRate - rateData.oldIBTRate), rateData.newIBTRate).fromRay(18);
        yieldData.actualYieldUser1 = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_1);

        yieldData.expectedYieldInIBTUser2 = _convertPTSharesToIBTsWithRates(
            yt.actualBalanceOf(MOCK_ADDR_2).toRay(18),
            rateData.oldPTRate,
            rateData.oldIBTRate,
            false
        ).mulDiv((rateData.newIBTRate - rateData.oldIBTRate), rateData.newIBTRate).fromRay(18);
        yieldData.actualYieldUser2 = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_2);

        yieldData.expectedYieldInIBTUser3 = _convertPTSharesToIBTsWithRates(
            yt.actualBalanceOf(MOCK_ADDR_3).toRay(18),
            rateData.oldPTRate,
            rateData.oldIBTRate,
            false
        ).mulDiv((rateData.newIBTRate - rateData.oldIBTRate), rateData.newIBTRate).fromRay(18);
        yieldData.actualYieldUser3 = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_3);

        yieldData.expectedYieldInIBTUser4 = _convertPTSharesToIBTsWithRates(
            yt.actualBalanceOf(MOCK_ADDR_4).toRay(18),
            rateData.oldPTRate,
            rateData.oldIBTRate,
            false
        ).mulDiv((rateData.newIBTRate - rateData.oldIBTRate), rateData.newIBTRate).fromRay(18);
        yieldData.actualYieldUser4 = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_4);

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
        // user 4 transfers 1/5th of his YTs to user3
        yieldData.ytBalanceBeforeUser3 = yt.actualBalanceOf(MOCK_ADDR_3);
        yieldData.ytBalanceBeforeUser4 = yt.actualBalanceOf(MOCK_ADDR_4);
        vm.prank(MOCK_ADDR_4);
        yt.transfer(MOCK_ADDR_3, yieldData.ytBalanceBeforeUser4 / 5);
        yieldData.ytBalanceAfterUser3 = yt.actualBalanceOf(MOCK_ADDR_3);
        yieldData.ytBalanceAfterUser4 = yt.actualBalanceOf(MOCK_ADDR_4);
        assertEq(
            yieldData.ytBalanceAfterUser3,
            yieldData.ytBalanceBeforeUser3 + yieldData.ytBalanceBeforeUser4 / 5
        );
        assertEq(
            yieldData.ytBalanceAfterUser4,
            yieldData.ytBalanceBeforeUser4 - yieldData.ytBalanceBeforeUser4 / 5
        );

        // update yield with user3 and 4
        yieldData.actualYieldUser3 = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_3);
        yieldData.actualYieldUser4 = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_4);
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
        yieldData.underlyingBalanceBefore = underlying.balanceOf(MOCK_ADDR_3);
        vm.startPrank(MOCK_ADDR_3);
        principalToken.claimYield(MOCK_ADDR_3);
        vm.stopPrank();
        assertEq(
            underlying.balanceOf(MOCK_ADDR_3),
            yieldData.underlyingBalanceBefore + ibt.previewRedeem(yieldData.actualYieldUser3),
            "After claiming yield, underlying balance of user3 is not equal to expected value"
        );
        yieldData.actualYieldUser3 = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_3);
        assertEq(
            yieldData.actualYieldUser3,
            0,
            "After claiming yield, current yield of user3 should be 0"
        );
        yieldData.oldYieldUser3 = yieldData.actualYieldUser3;

        rateData.oldIBTRate = rateData.newIBTRate;

        // increase time and rate
        vm.warp(block.timestamp + 100);
        _increaseRate(50);

        (, rateData.newIBTRate) = _getPTAndIBTRates();

        // computes yield of last step for the 4 users
        yieldData.expectedYieldInIBTUser1 = _convertPTSharesToIBTsWithRates(
            yt.actualBalanceOf(MOCK_ADDR_1).toRay(18),
            rateData.oldPTRate,
            rateData.oldIBTRate,
            false
        ).mulDiv((rateData.newIBTRate - rateData.oldIBTRate), rateData.newIBTRate).fromRay(18);
        yieldData.actualYieldUser1 = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_1);

        yieldData.expectedYieldInIBTUser2 = _convertPTSharesToIBTsWithRates(
            yt.actualBalanceOf(MOCK_ADDR_2).toRay(18),
            rateData.oldPTRate,
            rateData.oldIBTRate,
            false
        ).mulDiv((rateData.newIBTRate - rateData.oldIBTRate), rateData.newIBTRate).fromRay(18);
        yieldData.actualYieldUser2 = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_2);

        yieldData.expectedYieldInIBTUser3 = _convertPTSharesToIBTsWithRates(
            yt.actualBalanceOf(MOCK_ADDR_3).toRay(18),
            rateData.oldPTRate,
            rateData.oldIBTRate,
            false
        ).mulDiv((rateData.newIBTRate - rateData.oldIBTRate), rateData.newIBTRate).fromRay(18);
        yieldData.actualYieldUser3 = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_3);

        yieldData.expectedYieldInIBTUser4 = _convertPTSharesToIBTsWithRates(
            yt.actualBalanceOf(MOCK_ADDR_4).toRay(18),
            rateData.oldPTRate,
            rateData.oldIBTRate,
            false
        ).mulDiv((rateData.newIBTRate - rateData.oldIBTRate), rateData.newIBTRate).fromRay(18);
        yieldData.actualYieldUser4 = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_4);

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

        // user 3 claims his yield
        yieldData.underlyingBalanceBefore = underlying.balanceOf(MOCK_ADDR_3);
        vm.startPrank(MOCK_ADDR_3);
        principalToken.claimYield(MOCK_ADDR_3);
        vm.stopPrank();
        assertEq(
            underlying.balanceOf(MOCK_ADDR_3),
            yieldData.underlyingBalanceBefore + ibt.previewRedeem(yieldData.actualYieldUser3),
            "After claiming yield, underlying balance of user3 is not equal to expected value"
        );
        yieldData.actualYieldUser3 = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_3);
        assertEq(
            yieldData.actualYieldUser3,
            0,
            "After claiming yield, current yield of user3 should be 0"
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
        yieldData.actualYieldUser3 = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_3);
        yieldData.actualYieldUser4 = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_4);
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
        yieldData.underlyingBalanceBefore = underlying.balanceOf(MOCK_ADDR_4);
        vm.startPrank(MOCK_ADDR_4);
        principalToken.claimYield(MOCK_ADDR_4);
        vm.stopPrank();
        assertEq(
            underlying.balanceOf(MOCK_ADDR_4),
            yieldData.underlyingBalanceBefore + ibt.previewRedeem(yieldData.actualYieldUser4),
            "After claiming yield, underlying balance of user4 is not equal to expected value"
        );

        yieldData.actualYieldUser4 = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_4);
        assertEq(
            yieldData.actualYieldUser4,
            0,
            "After claiming yield, current yield of user4 should be 0"
        );
        yieldData.oldYieldUser4 = yieldData.actualYieldUser4;

        rateData.oldIBTRate = rateData.newIBTRate;

        // increase time and rate
        vm.warp(block.timestamp + 100);
        _increaseRate(20);

        (, rateData.newIBTRate) = _getPTAndIBTRates();

        // computes the yield of the last step for the 4 users
        yieldData.expectedYieldInIBTUser1 = _convertPTSharesToIBTsWithRates(
            yt.actualBalanceOf(MOCK_ADDR_1).toRay(18),
            rateData.oldPTRate,
            rateData.oldIBTRate,
            false
        ).mulDiv((rateData.newIBTRate - rateData.oldIBTRate), rateData.newIBTRate).fromRay(18);
        yieldData.actualYieldUser1 = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_1);

        yieldData.expectedYieldInIBTUser2 = _convertPTSharesToIBTsWithRates(
            yt.actualBalanceOf(MOCK_ADDR_2).toRay(18),
            rateData.oldPTRate,
            rateData.oldIBTRate,
            false
        ).mulDiv((rateData.newIBTRate - rateData.oldIBTRate), rateData.newIBTRate).fromRay(18);
        yieldData.actualYieldUser2 = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_2);

        yieldData.expectedYieldInIBTUser3 = _convertPTSharesToIBTsWithRates(
            yt.actualBalanceOf(MOCK_ADDR_3).toRay(18),
            rateData.oldPTRate,
            rateData.oldIBTRate,
            false
        ).mulDiv((rateData.newIBTRate - rateData.oldIBTRate), rateData.newIBTRate).fromRay(18);
        yieldData.actualYieldUser3 = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_3);

        yieldData.expectedYieldInIBTUser4 = _convertPTSharesToIBTsWithRates(
            yt.actualBalanceOf(MOCK_ADDR_4).toRay(18),
            rateData.oldPTRate,
            rateData.oldIBTRate,
            false
        ).mulDiv((rateData.newIBTRate - rateData.oldIBTRate), rateData.newIBTRate).fromRay(18);
        yieldData.actualYieldUser4 = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_4);

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
            "After rate change, yield for user3 is not equal to expected value"
        );
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

        // claimYield for all users
        yieldData.underlyingBalanceBefore = underlying.balanceOf(MOCK_ADDR_1);
        vm.prank(MOCK_ADDR_1);
        principalToken.claimYield(MOCK_ADDR_1);
        assertEq(
            underlying.balanceOf(MOCK_ADDR_1),
            yieldData.underlyingBalanceBefore + ibt.previewRedeem(yieldData.actualYieldUser1),
            "After Claiming yield, balance of user1 is not equal to expected value"
        );
        yieldData.actualYieldUser1 = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_1);
        assertEq(
            yieldData.actualYieldUser1,
            0,
            "After claiming yield, current yield of user1 should be 0"
        );

        yieldData.underlyingBalanceBefore = underlying.balanceOf(MOCK_ADDR_2);
        vm.startPrank(MOCK_ADDR_2);
        principalToken.claimYield(MOCK_ADDR_2);
        vm.stopPrank();
        assertEq(
            underlying.balanceOf(MOCK_ADDR_2),
            yieldData.underlyingBalanceBefore + ibt.previewRedeem(yieldData.actualYieldUser2),
            "After Claiming yield, balance of user2 is not equal to expected value"
        );
        yieldData.actualYieldUser2 = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_2);
        assertEq(
            yieldData.actualYieldUser2,
            0,
            "After claiming yield, current yield of user2 should be 0"
        );

        yieldData.underlyingBalanceBefore = underlying.balanceOf(MOCK_ADDR_3);
        vm.startPrank(MOCK_ADDR_3);
        principalToken.claimYield(MOCK_ADDR_3);
        vm.stopPrank();
        assertEq(
            underlying.balanceOf(MOCK_ADDR_3),
            yieldData.underlyingBalanceBefore + ibt.previewRedeem(yieldData.actualYieldUser3),
            "After Claiming yield, balance of user3 is not equal to expected value"
        );
        yieldData.actualYieldUser3 = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_3);
        assertEq(
            yieldData.actualYieldUser3,
            0,
            "After claiming yield, current yield of user3 should be 0"
        );

        yieldData.underlyingBalanceBefore = underlying.balanceOf(MOCK_ADDR_4);
        vm.startPrank(MOCK_ADDR_4);
        principalToken.claimYield(MOCK_ADDR_4);
        vm.stopPrank();
        assertEq(
            underlying.balanceOf(MOCK_ADDR_4),
            yieldData.underlyingBalanceBefore + ibt.previewRedeem(yieldData.actualYieldUser4),
            "After Claiming yield, balance of user4 is not equal to expected value"
        );
        yieldData.actualYieldUser4 = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_4);
        assertEq(
            yieldData.actualYieldUser4,
            0,
            "After claiming yield, current yield of user4 should be 0"
        );
        assertApproxEqAbs(
            underlying.balanceOf(MOCK_ADDR_4),
            yieldData.underlyingBalanceBefore,
            10,
            "After Claiming yield, balance of user4 is not equal to expected value"
        );
    }

    /**
     * @dev When the ibt rate is stable at 1, previewRedeem should return an underlying amount
     * equal to the shares amount passed as parameters.
     */
    function testPreviewRedeemTrivial() public {
        uint256 amountToDeposit = 1e18;
        uint256 receivedShares = _testDeposit(amountToDeposit, address(this));

        underlying.mint(address(this), amountToDeposit);
        underlying.approve(address(principalToken), amountToDeposit);
        principalToken.deposit(amountToDeposit, address(this));

        uint256 previewRedeem = principalToken.previewRedeem(receivedShares);

        _increaseTimeToExpiry();
        assertEq(
            previewRedeem,
            principalToken.previewRedeem(receivedShares),
            "PreviewRedeem is wrong after expiry"
        );

        principalToken.storeRatesAtExpiry();
        assertEq(
            previewRedeem,
            principalToken.previewRedeem(receivedShares),
            "PreviewRedeem is wrong after storeRatesAtExpiry"
        );

        // increase time
        vm.warp(block.timestamp + 10000);

        assertEq(
            previewRedeem,
            principalToken.previewRedeem(receivedShares),
            "PreviewRedeem is wrong after increasing time"
        );

        // assuming 0 tokenization fee
        uint256 expected = ibt.previewRedeem(
            _convertPTSharesToIBTsWithRates(
                receivedShares,
                principalToken.getPTRate(),
                principalToken.getIBTRate(),
                false
            )
        );
        assertEq(expected, previewRedeem, "PreviewRedeem is not equal to expected value");
    }

    /**
     * @dev The following will test the behaviour of previewRedeem as well as storing and getting
     * rates after expiry (ibt and pt), in the particular case where there was -100% yield.
     */
    function testPreviewRedeemWithMaximumNegativeYield() public {
        _increaseRate(-100);
        _increaseTimeToExpiry();
        principalToken.storeRatesAtExpiry();
        assertEq(principalToken.getIBTRate(), 0, "IBT rate at expiry is wrong");
        assertEq(principalToken.getPTRate(), 0, "PT rate at expiry is wrong");
        vm.expectRevert(); // reverts cause ibt rate at expiry is 0
        principalToken.previewRedeem(1e18);
    }

    /*
     * @dev Fuzz test of preview redeem in max negative yield condition
     */
    function test100NYPreviewRedeemFuzz(uint256 amountToDeposit) public {
        amountToDeposit = bound(amountToDeposit, 1e16, 1000e18);
        uint256 redeemShares = amountToDeposit / 2;
        vm.prank(testUser);

        underlying.approve(address(principalToken), amountToDeposit);
        principalToken.deposit(amountToDeposit, testUser);

        _increaseRate(-100);
        _increaseTimeToExpiry();
        principalToken.storeRatesAtExpiry();

        vm.expectRevert();
        principalToken.previewRedeem(redeemShares);
    }

    function testRedeemTrivial() public {
        uint256 amountToDeposit = 1e18;
        uint256 expected = _testDeposit(amountToDeposit, address(this));
        _increaseTimeToExpiry();
        principalToken.storeRatesAtExpiry();
        vm.expectEmit(true, true, false, true);
        emit Redeem(address(this), MOCK_ADDR_1, amountToDeposit);
        uint256 actual = principalToken.redeem(expected, MOCK_ADDR_1, address(this));
        assertEq(expected, actual, "Redeem balance is not equal to expected value");
        uint256 expected2 = 0;
        assertEq(
            expected2,
            principalToken.balanceOf(address(this)),
            "After redeem balance is not equal to expected value"
        );
        assertEq(
            amountToDeposit,
            underlying.balanceOf(MOCK_ADDR_1),
            "After redeem balance is not equal to expected value"
        );
    }

    function testPauseUnpauseFail() public {
        bytes memory revertData = abi.encodeWithSelector(
            bytes4(keccak256("AccessManagedUnauthorized(address)")),
            MOCK_ADDR_1
        );
        vm.expectRevert(revertData);
        vm.startPrank(MOCK_ADDR_1);
        principalToken.pause();
        vm.expectRevert(revertData);
        principalToken.unPause();
    }

    function testYTBurnWithoutUpdateFail() public {
        bytes memory revertData = abi.encodeWithSignature("CallerIsNotPtContract()");
        vm.expectRevert(revertData);
        yt.burnWithoutUpdate(MOCK_ADDR_1, 1e18);
    }

    function testYTMintFail() public {
        bytes memory revertData = abi.encodeWithSignature("CallerIsNotPtContract()");
        vm.expectRevert(revertData);
        yt.mint(MOCK_ADDR_1, 1e18);
    }

    function testBeforeYtTransferFail() public {
        bytes memory revertData = abi.encodeWithSignature("UnauthorizedCaller()");
        vm.expectRevert(revertData);
        principalToken.beforeYtTransfer(address(this), MOCK_ADDR_1);
    }

    function testMultipleClaimFees() public {
        uint256 assetsToDeposit = 10e18;
        uint256 shares = _testDeposit(assetsToDeposit, address(this));
        uint256 expectedShares = principalToken.convertToPrincipal(assetsToDeposit);
        assertEq(expectedShares, shares);
        _increaseRate(50);

        uint256 netUserYieldInUnderlying = ibt.previewRedeem(
            principalToken.getCurrentYieldOfUserInIBT(address(this))
        );
        uint256 underlyingBalanceBefore = underlying.balanceOf(address(this));
        principalToken.claimYield(address(this));
        assertApproxEqAbs(
            underlyingBalanceBefore + netUserYieldInUnderlying,
            underlying.balanceOf(address(this)),
            1000,
            "After claimYield balance is not equal to expected value"
        );
        vm.prank(feeCollector);
        uint256 actualFees = principalToken.claimFees();
        uint256 feeCollectorBalance = underlying.balanceOf(feeCollector);
        assertEq(actualFees, feeCollectorBalance);
    }

    function testPrincipalTokenInitWithoutProxyFails() public {
        PrincipalToken newPrincipalToken = new PrincipalToken(address(registry));

        bytes memory revertData = abi.encodeWithSignature("InvalidInitialization()");
        vm.expectRevert(revertData);
        newPrincipalToken.initialize(address(ibt), 10000000, address(accessManager)); // deploys principalToken
    }

    function testYTInitWithoutProxyFails() public {
        PrincipalToken newPrincipalToken = new PrincipalToken(address(registry));
        yt = new YieldToken();

        bytes memory revertData = abi.encodeWithSignature("InvalidInitialization()");
        vm.expectRevert(revertData);
        yt.initialize("MOCK YieldToken", "MYT", address(newPrincipalToken));
    }

    function testPrincipalTokenGetters() public {
        assertEq(address(ibt), principalToken.getIBT(), "IBT getter is wrong");
        assertEq(
            type(uint256).max,
            principalToken.maxDeposit(MOCK_ADDR_1),
            "maxDeposit method is wrong"
        );
        assertEq(0, principalToken.totalSupply(), "totalSupply method is wrong");
        assertEq(0, principalToken.maxWithdraw(MOCK_ADDR_1), "maxWithdraw method is wrong");
        assertEq(
            address(feeCollector),
            registry.getFeeCollector(),
            "getFeeCollector method is wrong"
        );
        uint256 assets = 100 * (10 ** underlying.decimals());
        ibtRate = 5e27;
        uint256 expectedIBT = Math.mulDiv(assets, 1e27, ibtRate);
        assertEq(
            expectedIBT,
            _convertToSharesWithRate(assets, ibtRate, false, false, Math.Rounding.Floor),
            "convertToSharesWithRate method is wrong"
        );
    }

    /**============ Full cycle tests =============**/

    function testFullCycle1() public {
        UserRate memory user1;
        UserRate memory user2;
        UserRate memory user3;
        UserRate memory user4;
        UserRate memory user5;

        _testDeposit(2e18, MOCK_ADDR_1);
        user1.oldPTRate = ptRate;
        user1.oldIBTRate = ibtRate;

        _prepareForDepositIBT(MOCK_ADDR_2, 1e18);
        _testDepositIBT(1e18, MOCK_ADDR_2);
        user2.oldPTRate = ptRate;
        user2.oldIBTRate = ibtRate;

        _increaseRate(12);

        // transfer some pt to user3
        _transferPT(MOCK_ADDR_1, MOCK_ADDR_3, principalToken.balanceOf(MOCK_ADDR_1) / 2);

        _increaseRate(15);

        (ptRate, ibtRate) = _getPTAndIBTRates();
        uint256 yieldInIBT = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_1);

        _testYieldUpdate(MOCK_ADDR_1, user1, ptRate, ibtRate, yieldInIBT);

        // yield should be zero
        yieldInIBT = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_3);
        user3 = _testYieldUpdate(MOCK_ADDR_3, user3, ptRate, ibtRate, yieldInIBT);

        _transferYT(MOCK_ADDR_1, MOCK_ADDR_3, yt.actualBalanceOf(MOCK_ADDR_1) / 2);

        _increaseRate(-20);

        _testDeposit(5e18, MOCK_ADDR_4);
        (ptRate, ibtRate) = _getPTAndIBTRates();
        user4.oldIBTRate = ibtRate;
        user4.oldPTRate = ptRate;

        yieldInIBT = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_3);
        user3 = _testYieldUpdate(MOCK_ADDR_3, user3, ptRate, ibtRate, yieldInIBT);

        uint256 maxWithdraw = principalToken.maxWithdraw(MOCK_ADDR_3);
        _testWithdraw(maxWithdraw, MOCK_ADDR_3, MOCK_ADDR_3);

        _increaseRate(25);

        _testDeposit(5e18, MOCK_ADDR_5);
        (ptRate, ibtRate) = _getPTAndIBTRates();
        user5.oldIBTRate = ibtRate;
        user5.oldPTRate = ptRate;

        yieldInIBT = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_1);
        user1 = _testYieldUpdate(MOCK_ADDR_1, user1, ptRate, ibtRate, yieldInIBT);

        maxWithdraw = principalToken.maxWithdraw(MOCK_ADDR_1);
        _testWithdraw(maxWithdraw, MOCK_ADDR_1, MOCK_ADDR_1);

        _increaseTimeToExpiry();

        principalToken.storeRatesAtExpiry();
        yieldInIBT = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_4);
        user4 = _testYieldUpdate(MOCK_ADDR_4, user4, ptRate, ibtRate, yieldInIBT);
        _testRedeemMaxAndClaimYield(MOCK_ADDR_4, MOCK_ADDR_4);

        yieldInIBT = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_2);
        user2 = _testYieldUpdate(MOCK_ADDR_2, user2, ptRate, ibtRate, yieldInIBT);
        yieldInIBT = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_5);
        user5 = _testYieldUpdate(MOCK_ADDR_5, user5, ptRate, ibtRate, yieldInIBT);

        _testRedeem(principalToken.balanceOf(MOCK_ADDR_2), MOCK_ADDR_2);
        _testRedeem(principalToken.balanceOf(MOCK_ADDR_5), MOCK_ADDR_5);
    }

    function testFullCycle2() public {
        UserRate memory user1;
        UserRate memory user2;
        UserRate memory user3;
        UserRate memory user4;
        UserRate memory user5;

        _testDeposit(5e18, MOCK_ADDR_1);
        user1.oldPTRate = ptRate;
        user1.oldIBTRate = ibtRate;

        _increaseRate(-20);

        _testDeposit(2e18, MOCK_ADDR_2);
        (ptRate, ibtRate) = _getPTAndIBTRates();
        user2.oldPTRate = ptRate;
        user2.oldIBTRate = ibtRate;

        _increaseRate(15);

        _testDeposit(1e18, MOCK_ADDR_3);
        (ptRate, ibtRate) = _getPTAndIBTRates();
        user3.oldPTRate = ptRate;
        user3.oldIBTRate = ibtRate;

        _transferPT(MOCK_ADDR_1, MOCK_ADDR_4, principalToken.balanceOf(MOCK_ADDR_1) / 3);

        _increaseRate(-25);

        uint256 yieldInIBT = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_1);
        (ptRate, ibtRate) = _getPTAndIBTRates();
        user1 = _testYieldUpdate(MOCK_ADDR_1, user1, ptRate, ibtRate, yieldInIBT);

        yieldInIBT = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_4);
        user4 = _testYieldUpdate(MOCK_ADDR_4, user4, ptRate, ibtRate, yieldInIBT);

        _transferYT(MOCK_ADDR_1, MOCK_ADDR_4, yt.actualBalanceOf(MOCK_ADDR_1) / 2);

        _increaseRate(30);

        yieldInIBT = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_1);
        (ptRate, ibtRate) = _getPTAndIBTRates();
        user1 = _testYieldUpdate(MOCK_ADDR_1, user1, ptRate, ibtRate, yieldInIBT);

        uint256 maxWithdraw = principalToken.maxWithdraw(MOCK_ADDR_1);
        _testWithdraw(maxWithdraw, MOCK_ADDR_1, MOCK_ADDR_1);

        _testDeposit(3e18, MOCK_ADDR_5);
        (ptRate, ibtRate) = _getPTAndIBTRates();
        user5.oldPTRate = ptRate;
        user5.oldIBTRate = ibtRate;

        _increaseRate(-40);

        yieldInIBT = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_3);
        (ptRate, ibtRate) = _getPTAndIBTRates();
        user3 = _testYieldUpdate(MOCK_ADDR_3, user3, ptRate, ibtRate, yieldInIBT);

        maxWithdraw = principalToken.maxWithdraw(MOCK_ADDR_3);
        _testWithdraw(maxWithdraw, MOCK_ADDR_3, MOCK_ADDR_3);

        _increaseTimeToExpiry();
        principalToken.storeRatesAtExpiry();

        yieldInIBT = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_4);
        user4 = _testYieldUpdate(MOCK_ADDR_4, user4, ptRate, ibtRate, yieldInIBT);

        _testRedeemMaxAndClaimYield(MOCK_ADDR_4, MOCK_ADDR_4);

        yieldInIBT = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_2);
        user2 = _testYieldUpdate(MOCK_ADDR_2, user2, ptRate, ibtRate, yieldInIBT);
        yieldInIBT = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_5);
        user5 = _testYieldUpdate(MOCK_ADDR_5, user5, ptRate, ibtRate, yieldInIBT);

        _testRedeem(principalToken.balanceOf(MOCK_ADDR_2), MOCK_ADDR_2);
        _testRedeem(principalToken.balanceOf(MOCK_ADDR_5), MOCK_ADDR_5);
    }

    function testFullCycle3() public {
        _increaseRate(80);

        UserRate memory user1;
        UserRate memory user2;
        UserRate memory user3;
        UserRate memory user4;
        UserRate memory user5;

        _testDeposit(5e18, MOCK_ADDR_1);
        (ptRate, ibtRate) = _getPTAndIBTRates();
        user1.oldPTRate = ptRate;
        user1.oldIBTRate = ibtRate;

        _increaseRate(-70);

        _testDeposit(2e18, MOCK_ADDR_2);
        (ptRate, ibtRate) = _getPTAndIBTRates();
        user2.oldPTRate = ptRate;
        user2.oldIBTRate = ibtRate;

        _increaseRate(15);
        uint256 yieldInIBT = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_1);
        (ptRate, ibtRate) = _getPTAndIBTRates();
        user1 = _testYieldUpdate(MOCK_ADDR_1, user1, ptRate, ibtRate, yieldInIBT);

        _claimYield(MOCK_ADDR_1);
        user1.oldYieldOfUserInIBT = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_1);

        _testDeposit(1e18, MOCK_ADDR_3);
        user3.oldPTRate = ptRate;
        user3.oldIBTRate = ibtRate;

        _increaseRate(-5);

        yieldInIBT = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_1);
        (ptRate, ibtRate) = _getPTAndIBTRates();
        user1 = _testYieldUpdate(MOCK_ADDR_1, user1, ptRate, ibtRate, yieldInIBT);
        yieldInIBT = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_2);
        user2 = _testYieldUpdate(MOCK_ADDR_2, user2, ptRate, ibtRate, yieldInIBT);

        _claimYield(MOCK_ADDR_1);
        _claimYield(MOCK_ADDR_2);
        user1.oldYieldOfUserInIBT = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_1);
        user2.oldYieldOfUserInIBT = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_2);

        _increaseRate(-5);

        _testDeposit(10e18, MOCK_ADDR_4);
        _testDeposit(10e18, MOCK_ADDR_5);
        (ptRate, ibtRate) = _getPTAndIBTRates();
        user4.oldPTRate = ptRate;
        user4.oldIBTRate = ibtRate;
        user5.oldPTRate = ptRate;
        user5.oldIBTRate = ibtRate;

        _transferYT(MOCK_ADDR_4, MOCK_ADDR_5, yt.actualBalanceOf(MOCK_ADDR_4) / 2);

        _increaseRate(15);

        yieldInIBT = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_1);
        (ptRate, ibtRate) = _getPTAndIBTRates();
        user1 = _testYieldUpdate(MOCK_ADDR_1, user1, ptRate, ibtRate, yieldInIBT);

        uint256 maxWithdraw = principalToken.maxWithdraw(MOCK_ADDR_1);
        _testWithdraw(maxWithdraw, MOCK_ADDR_1, MOCK_ADDR_1);

        yieldInIBT = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_3);
        user3 = _testYieldUpdate(MOCK_ADDR_3, user3, ptRate, ibtRate, yieldInIBT);

        maxWithdraw = principalToken.maxWithdraw(MOCK_ADDR_3);
        _testWithdraw(maxWithdraw, MOCK_ADDR_3, MOCK_ADDR_3);

        _increaseTimeToExpiry();
        principalToken.storeRatesAtExpiry();

        yieldInIBT = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_4);
        user4 = _testYieldUpdate(MOCK_ADDR_4, user4, ptRate, ibtRate, yieldInIBT);

        maxWithdraw = principalToken.maxWithdraw(MOCK_ADDR_4);
        _testRedeemMaxAndClaimYield(MOCK_ADDR_4, MOCK_ADDR_4);

        yieldInIBT = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_2);
        user2 = _testYieldUpdate(MOCK_ADDR_2, user2, ptRate, ibtRate, yieldInIBT);
        yieldInIBT = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_5);
        user5 = _testYieldUpdate(MOCK_ADDR_5, user5, ptRate, ibtRate, yieldInIBT);

        _testRedeem(principalToken.balanceOf(MOCK_ADDR_2), MOCK_ADDR_2);
        _testRedeem(principalToken.balanceOf(MOCK_ADDR_5), MOCK_ADDR_5);
    }

    function testFullCycle4() public {
        _increaseRate(-70);

        _increaseRate(600);

        UserRate memory user1;
        UserRate memory user2;
        UserRate memory user3;
        UserRate memory user4;
        UserRate memory user5;

        _testDeposit(3e18, MOCK_ADDR_1);
        (ptRate, ibtRate) = _getPTAndIBTRates();
        user1.oldPTRate = ptRate;
        user1.oldIBTRate = ibtRate;

        _increaseRate(-50);

        _testDeposit(5e18, MOCK_ADDR_2);
        (ptRate, ibtRate) = _getPTAndIBTRates();
        user2.oldPTRate = ptRate;
        user2.oldIBTRate = ibtRate;

        _increaseRate(15);

        uint256 yieldInIBT = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_1);
        (ptRate, ibtRate) = _getPTAndIBTRates();
        user1 = _testYieldUpdate(MOCK_ADDR_1, user1, ptRate, ibtRate, yieldInIBT);

        _transferYT(MOCK_ADDR_1, MOCK_ADDR_3, yt.actualBalanceOf(MOCK_ADDR_1) / 2);

        _testDeposit(1e18, MOCK_ADDR_3);
        (ptRate, ibtRate) = _getPTAndIBTRates();
        user3.oldPTRate = ptRate;
        user3.oldIBTRate = ibtRate;

        _increaseRate(20);

        yieldInIBT = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_1);
        (ptRate, ibtRate) = _getPTAndIBTRates();
        user1 = _testYieldUpdate(MOCK_ADDR_1, user1, ptRate, ibtRate, yieldInIBT);
        yieldInIBT = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_2);
        user2 = _testYieldUpdate(MOCK_ADDR_2, user2, ptRate, ibtRate, yieldInIBT);

        _claimYield(MOCK_ADDR_1);
        _claimYield(MOCK_ADDR_2);
        user1.oldYieldOfUserInIBT = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_1);
        user2.oldYieldOfUserInIBT = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_2);

        _testDeposit(10e18, MOCK_ADDR_4);
        _testDeposit(10e18, MOCK_ADDR_5);
        (ptRate, ibtRate) = _getPTAndIBTRates();
        user4.oldPTRate = ptRate;
        user4.oldIBTRate = ibtRate;
        user5.oldPTRate = ptRate;
        user5.oldIBTRate = ibtRate;

        _increaseRate(-10);

        _transferPT(MOCK_ADDR_5, MOCK_ADDR_4, principalToken.balanceOf(MOCK_ADDR_5));

        yieldInIBT = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_1);
        (ptRate, ibtRate) = _getPTAndIBTRates();
        user1 = _testYieldUpdate(MOCK_ADDR_1, user1, ptRate, ibtRate, yieldInIBT);
        yieldInIBT = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_2);
        user2 = _testYieldUpdate(MOCK_ADDR_2, user2, ptRate, ibtRate, yieldInIBT);

        uint256 maxWithdraw = principalToken.maxWithdraw(MOCK_ADDR_1);
        _testWithdraw(maxWithdraw, MOCK_ADDR_1, MOCK_ADDR_1);

        maxWithdraw = principalToken.maxWithdraw(MOCK_ADDR_2);
        _testWithdraw(maxWithdraw, MOCK_ADDR_2, MOCK_ADDR_2);

        _increaseRate(-50);

        _increaseTimeToExpiry();
        principalToken.storeRatesAtExpiry();

        yieldInIBT = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_3);
        user3 = _testYieldUpdate(MOCK_ADDR_3, user3, ptRate, ibtRate, yieldInIBT);
        (ptRate, ibtRate) = _getPTAndIBTRates();
        _testRedeemMaxAndClaimYield(MOCK_ADDR_2, MOCK_ADDR_3);

        yieldInIBT = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_4);
        user4 = _testYieldUpdate(MOCK_ADDR_4, user4, ptRate, ibtRate, yieldInIBT);
        yieldInIBT = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_5);
        user5 = _testYieldUpdate(MOCK_ADDR_5, user5, ptRate, ibtRate, yieldInIBT);

        _testRedeem(principalToken.balanceOf(MOCK_ADDR_4), MOCK_ADDR_4);
        _testRedeem(principalToken.balanceOf(MOCK_ADDR_5), MOCK_ADDR_5);
    }

    /**============Fuzz tests begin here=============**/
    function testTransferPTFuzz(uint256 amount0, uint256 amount1) public {
        amount0 = bound(amount0, 1e18, 100000e18);
        amount1 = bound(amount1, 1e18, amount0);
        uint256 actualBalance1 = _testDeposit(amount0, MOCK_ADDR_1);
        uint256 expectedBalance1 = amount0;
        assertEq(expectedBalance1, actualBalance1);
        vm.prank(MOCK_ADDR_1);
        principalToken.transfer(MOCK_ADDR_2, amount1);
        uint256 expectedBalance2 = amount1;
        uint256 expectedBalance3 = amount0 - amount1;
        uint256 actualBalance2 = principalToken.balanceOf(MOCK_ADDR_2);
        uint256 actualBalance3 = principalToken.balanceOf(MOCK_ADDR_1);
        assertEq(expectedBalance2, actualBalance2);
        assertEq(expectedBalance3, actualBalance3);
    }

    /**
     * @dev Fuzz tests transfer YieldToken and PT in different yield situations for both sender and receiver.
     */
    function testTransferYTAndPTFuzz(
        uint256 amountToDeposit,
        uint256 amountToTransfer,
        uint16 _rate
    ) public {
        // address(this) deposits
        amountToDeposit = bound(amountToDeposit, 0, 1000e18);
        int256 rate = int256(bound(_rate, 0, 100));
        _testDeposit(amountToDeposit, address(this));

        // +50% of positive yield
        _increaseRate(rate);

        // MOCK_ADDR_1 deposits
        _testDeposit(amountToDeposit * 3, MOCK_ADDR_1);

        // -25% of positive yield
        _increaseRate((-1 * rate) / 3);

        // MOCK_ADDR_2 deposits 10 underlying
        _testDeposit(amountToDeposit / 5, MOCK_ADDR_2);

        /* YieldToken TRANSFERS */
        // Each user transfer to other 2 users
        // address(this) as the YieldToken sender
        amountToTransfer = bound(amountToTransfer, 0, (3 * yt.actualBalanceOf(address(this))) / 10);
        uint256 ytBalanceBeforeSender = yt.actualBalanceOf(address(this));
        uint256 ytBalanceBeforeReceiver = yt.actualBalanceOf(MOCK_ADDR_1);

        yt.transfer(MOCK_ADDR_1, amountToTransfer);
        uint256 ytBalanceAfterSender = yt.actualBalanceOf(address(this));
        uint256 ytBalanceAfterReceiver = yt.actualBalanceOf(MOCK_ADDR_1);
        assertEq(
            ytBalanceAfterSender + amountToTransfer,
            ytBalanceBeforeSender,
            "YieldToken balance of sender is wrong"
        );
        assertEq(
            ytBalanceAfterReceiver,
            ytBalanceBeforeReceiver + amountToTransfer,
            "YieldToken Balance of receiver is wrong"
        );

        amountToTransfer = bound(amountToTransfer, 0, (4 * yt.actualBalanceOf(address(this))) / 10);
        ytBalanceBeforeSender = yt.actualBalanceOf(address(this));
        ytBalanceBeforeReceiver = yt.actualBalanceOf(MOCK_ADDR_2);

        yt.transfer(MOCK_ADDR_2, amountToTransfer);
        ytBalanceAfterSender = yt.actualBalanceOf(address(this));
        ytBalanceAfterReceiver = yt.actualBalanceOf(MOCK_ADDR_2);
        assertEq(ytBalanceAfterSender + amountToTransfer, ytBalanceBeforeSender);
        assertEq(ytBalanceAfterReceiver, ytBalanceBeforeReceiver + amountToTransfer);

        // MOCK_ADDR_1 as YieldToken sender
        amountToTransfer = bound(amountToTransfer, 0, yt.actualBalanceOf(MOCK_ADDR_1) / 10);
        ytBalanceBeforeSender = yt.actualBalanceOf(MOCK_ADDR_1);
        ytBalanceBeforeReceiver = yt.actualBalanceOf(address(this));
        vm.prank(MOCK_ADDR_1);
        yt.transfer(address(this), amountToTransfer);
        ytBalanceAfterSender = yt.actualBalanceOf(MOCK_ADDR_1);
        ytBalanceAfterReceiver = yt.actualBalanceOf(address(this));
        assertEq(
            ytBalanceAfterSender + amountToTransfer,
            ytBalanceBeforeSender,
            "YieldToken balance of sender is wrong"
        );
        assertEq(
            ytBalanceAfterReceiver,
            ytBalanceBeforeReceiver + amountToTransfer,
            "YieldToken Balance of receiver is wrong"
        );

        amountToTransfer = yt.actualBalanceOf(MOCK_ADDR_1);
        ytBalanceBeforeSender = yt.actualBalanceOf(MOCK_ADDR_1);
        ytBalanceBeforeReceiver = yt.actualBalanceOf(MOCK_ADDR_2);
        vm.prank(MOCK_ADDR_1);
        bytes memory revertData = abi.encodeWithSelector(
            bytes4(keccak256("ERC20InsufficientBalance(address,uint256,uint256)")),
            MOCK_ADDR_1,
            ytBalanceBeforeSender,
            amountToTransfer + 1
        );
        vm.expectRevert(revertData);
        yt.transfer(MOCK_ADDR_2, amountToTransfer + 1);
        vm.prank(MOCK_ADDR_1);
        yt.transfer(MOCK_ADDR_2, amountToTransfer);
        ytBalanceAfterSender = yt.actualBalanceOf(MOCK_ADDR_1);
        ytBalanceAfterReceiver = yt.actualBalanceOf(MOCK_ADDR_2);
        assertEq(ytBalanceAfterSender + amountToTransfer, ytBalanceBeforeSender);
        assertEq(ytBalanceAfterReceiver, ytBalanceBeforeReceiver + amountToTransfer);

        // MOCK_ADDR_2 as the YieldToken sender
        amountToTransfer = bound(amountToTransfer, 0, (5 * yt.actualBalanceOf(MOCK_ADDR_2)) / 10);
        ytBalanceBeforeSender = yt.actualBalanceOf(MOCK_ADDR_2);
        ytBalanceBeforeReceiver = yt.actualBalanceOf(address(this));
        vm.prank(MOCK_ADDR_2);
        yt.transfer(address(this), amountToTransfer);
        ytBalanceAfterSender = yt.actualBalanceOf(MOCK_ADDR_2);
        ytBalanceAfterReceiver = yt.actualBalanceOf(address(this));
        assertEq(
            ytBalanceAfterSender + amountToTransfer,
            ytBalanceBeforeSender,
            "YieldToken balance of sender is wrong"
        );
        assertEq(
            ytBalanceAfterReceiver,
            ytBalanceBeforeReceiver + amountToTransfer,
            "YieldToken Balance of receiver is wrong"
        );

        amountToTransfer = bound(amountToTransfer, 0, (7 * yt.actualBalanceOf(MOCK_ADDR_2)) / 10);
        ytBalanceBeforeSender = yt.actualBalanceOf(MOCK_ADDR_2);
        ytBalanceBeforeReceiver = yt.actualBalanceOf(MOCK_ADDR_1);
        vm.prank(MOCK_ADDR_2);
        yt.transfer(MOCK_ADDR_1, amountToTransfer);
        ytBalanceAfterSender = yt.actualBalanceOf(MOCK_ADDR_2);
        ytBalanceAfterReceiver = yt.actualBalanceOf(MOCK_ADDR_1);
        assertEq(ytBalanceAfterSender + amountToTransfer, ytBalanceBeforeSender);
        assertEq(ytBalanceAfterReceiver, ytBalanceBeforeReceiver + amountToTransfer);

        /* PT TRANSFERS */
        // Each user transfer to other 2 users
        // address(this) as the PT sender
        amountToTransfer = bound(
            amountToTransfer,
            0,
            (3 * principalToken.balanceOf(address(this))) / 10
        );
        uint256 ptBalanceBeforeSender = principalToken.balanceOf(address(this));
        uint256 ptBalanceBeforeReceiver = principalToken.balanceOf(MOCK_ADDR_1);

        principalToken.transfer(MOCK_ADDR_1, amountToTransfer);
        uint256 ptBalanceAfterSender = principalToken.balanceOf(address(this));
        uint256 ptBalanceAfterReceiver = principalToken.balanceOf(MOCK_ADDR_1);
        assertEq(
            ptBalanceAfterSender + amountToTransfer,
            ptBalanceBeforeSender,
            "PT balance of sender is wrong"
        );
        assertEq(
            ptBalanceAfterReceiver,
            ptBalanceBeforeReceiver + amountToTransfer,
            "PT Balance of receiver is wrong"
        );

        amountToTransfer = bound(
            amountToTransfer,
            0,
            (4 * principalToken.balanceOf(address(this))) / 10
        );
        ptBalanceBeforeSender = principalToken.balanceOf(address(this));
        ptBalanceBeforeReceiver = principalToken.balanceOf(MOCK_ADDR_2);

        principalToken.transfer(MOCK_ADDR_2, amountToTransfer);
        ptBalanceAfterSender = principalToken.balanceOf(address(this));
        ptBalanceAfterReceiver = principalToken.balanceOf(MOCK_ADDR_2);
        assertEq(ptBalanceAfterSender + amountToTransfer, ptBalanceBeforeSender);
        assertEq(ptBalanceAfterReceiver, ptBalanceBeforeReceiver + amountToTransfer);

        // MOCK_ADDR_1 as PT sender
        amountToTransfer = bound(amountToTransfer, 0, principalToken.balanceOf(MOCK_ADDR_1) / 10);
        ptBalanceBeforeSender = principalToken.balanceOf(MOCK_ADDR_1);
        ptBalanceBeforeReceiver = principalToken.balanceOf(address(this));
        vm.prank(MOCK_ADDR_1);
        principalToken.transfer(address(this), amountToTransfer);
        ptBalanceAfterSender = principalToken.balanceOf(MOCK_ADDR_1);
        ptBalanceAfterReceiver = principalToken.balanceOf(address(this));
        assertEq(
            ptBalanceAfterSender + amountToTransfer,
            ptBalanceBeforeSender,
            "PT balance of sender is wrong"
        );
        assertEq(
            ptBalanceAfterReceiver,
            ptBalanceBeforeReceiver + amountToTransfer,
            "PT Balance of receiver is wrong"
        );

        amountToTransfer = principalToken.balanceOf(MOCK_ADDR_1);
        ptBalanceBeforeSender = principalToken.balanceOf(MOCK_ADDR_1);
        ptBalanceBeforeReceiver = principalToken.balanceOf(MOCK_ADDR_2);
        vm.prank(MOCK_ADDR_1);
        revertData = abi.encodeWithSelector(
            bytes4(keccak256("ERC20InsufficientBalance(address,uint256,uint256)")),
            MOCK_ADDR_1,
            ptBalanceBeforeSender,
            amountToTransfer + 1
        );
        vm.expectRevert(revertData);
        principalToken.transfer(MOCK_ADDR_2, amountToTransfer + 1);
        vm.prank(MOCK_ADDR_1);
        principalToken.transfer(MOCK_ADDR_2, amountToTransfer);
        ptBalanceAfterSender = principalToken.balanceOf(MOCK_ADDR_1);
        ptBalanceAfterReceiver = principalToken.balanceOf(MOCK_ADDR_2);
        assertEq(ptBalanceAfterSender + amountToTransfer, ptBalanceBeforeSender);
        assertEq(ptBalanceAfterReceiver, ptBalanceBeforeReceiver + amountToTransfer);

        // MOCK_ADDR_2 as the PT sender
        amountToTransfer = bound(
            amountToTransfer,
            0,
            (5 * principalToken.balanceOf(MOCK_ADDR_2)) / 10
        );
        ptBalanceBeforeSender = principalToken.balanceOf(MOCK_ADDR_2);
        ptBalanceBeforeReceiver = principalToken.balanceOf(address(this));
        vm.prank(MOCK_ADDR_2);
        principalToken.transfer(address(this), amountToTransfer);
        ptBalanceAfterSender = principalToken.balanceOf(MOCK_ADDR_2);
        ptBalanceAfterReceiver = principalToken.balanceOf(address(this));
        assertEq(
            ptBalanceAfterSender + amountToTransfer,
            ptBalanceBeforeSender,
            "YieldToken balance of sender is wrong"
        );
        assertEq(
            ptBalanceAfterReceiver,
            ptBalanceBeforeReceiver + amountToTransfer,
            "YieldToken Balance of receiver is wrong"
        );

        amountToTransfer = bound(
            amountToTransfer,
            0,
            (7 * principalToken.balanceOf(MOCK_ADDR_2)) / 10
        );
        ptBalanceBeforeSender = principalToken.balanceOf(MOCK_ADDR_2);
        ptBalanceBeforeReceiver = principalToken.balanceOf(MOCK_ADDR_1);
        vm.prank(MOCK_ADDR_2);
        principalToken.transfer(MOCK_ADDR_1, amountToTransfer);
        ptBalanceAfterSender = principalToken.balanceOf(MOCK_ADDR_2);
        ptBalanceAfterReceiver = principalToken.balanceOf(MOCK_ADDR_1);
        assertEq(ptBalanceAfterSender + amountToTransfer, ptBalanceBeforeSender);
        assertEq(ptBalanceAfterReceiver, ptBalanceBeforeReceiver + amountToTransfer);
    }

    function testTransferPTFromFuzz(uint256 amount0, uint256 amount1) public {
        amount0 = bound(amount0, 1e18, 100000e18);
        amount1 = bound(amount1, 1e18, amount0);
        uint256 actualBalance1 = _testDeposit(amount0, MOCK_ADDR_1);
        uint256 expectedBalance1 = amount0;
        assertEq(expectedBalance1, actualBalance1);
        vm.startPrank(MOCK_ADDR_1);
        principalToken.approve(MOCK_ADDR_1, amount1);
        principalToken.transferFrom(MOCK_ADDR_1, MOCK_ADDR_2, amount1);
        vm.stopPrank();
        uint256 expectedBalance2 = amount1;
        uint256 expectedBalance3 = amount0 - amount1;
        uint256 actualBalance2 = principalToken.balanceOf(MOCK_ADDR_2);
        uint256 actualBalance3 = principalToken.balanceOf(MOCK_ADDR_1);
        assertEq(expectedBalance2, actualBalance2);
        assertEq(expectedBalance3, actualBalance3);
    }

    function testYTTransferWhenPTZeroAndZeroOrPositiveYieldFuzz(
        uint256 amountToDeposit,
        uint16 _rate
    ) public {
        amountToDeposit = bound(amountToDeposit, 0, 100e18);
        int256 rate = int256(bound(_rate, 1, 100));
        _testDeposit(amountToDeposit, address(this));

        uint256 amountToTransfer = principalToken.balanceOf(address(this)) / 2;
        uint256 expectedBalance1 = amountToTransfer;
        uint256 expectedBalance2 = principalToken.balanceOf(address(this)) - amountToTransfer;

        principalToken.transfer(MOCK_ADDR_1, amountToTransfer); // transfers amountToTransfer with first argument being receiver
        uint256 actualBalance1 = principalToken.balanceOf(MOCK_ADDR_1);
        uint256 actualBalance2 = principalToken.balanceOf(address(this));
        // checks if balances are accurate after deposit
        assertEq(
            expectedBalance1,
            actualBalance1,
            "After transfer balance is not equal to expected value 1"
        );
        assertEq(
            expectedBalance2,
            actualBalance2,
            "After transfer balance is not equal to expected value 2"
        );

        amountToTransfer = yt.actualBalanceOf(address(this)) / 2;
        expectedBalance1 = amountToTransfer;
        expectedBalance2 = yt.actualBalanceOf(address(this)) - amountToTransfer;

        yt.transfer(MOCK_ADDR_1, amountToTransfer); // transfers amountToTransfer with first argument being receiver
        actualBalance1 = yt.actualBalanceOf(MOCK_ADDR_1);
        actualBalance2 = yt.actualBalanceOf(address(this));
        // checks if balances are accurate after deposit
        assertEq(
            expectedBalance1,
            actualBalance1,
            "After transfer balance is not equal to expected value 3"
        );
        assertEq(
            expectedBalance2,
            actualBalance2,
            "After transfer balance is not equal to expected value 4"
        );

        _increaseRate(rate);

        amountToTransfer = principalToken.balanceOf(address(this));
        expectedBalance1 = amountToTransfer;
        expectedBalance2 = principalToken.balanceOf(address(this)) - amountToTransfer;

        principalToken.transfer(MOCK_ADDR_2, amountToTransfer); // transfers amountToTransfer with first argument being receiver
        actualBalance1 = principalToken.balanceOf(MOCK_ADDR_2);
        actualBalance2 = principalToken.balanceOf(address(this));
        // checks if balances are accurate after deposit
        assertEq(
            expectedBalance1,
            actualBalance1,
            "After transfer balance is not equal to expected value 5"
        );
        assertEq(
            expectedBalance2,
            actualBalance2,
            "After transfer balance is not equal to expected value 6"
        );

        amountToTransfer = yt.actualBalanceOf(address(this));
        expectedBalance1 = amountToTransfer;
        expectedBalance2 = yt.actualBalanceOf(address(this)) - amountToTransfer;

        yt.transfer(MOCK_ADDR_2, amountToTransfer); // transfers amountToTransfer with first argument being receiver
        actualBalance1 = yt.actualBalanceOf(MOCK_ADDR_2);
        actualBalance2 = yt.actualBalanceOf(address(this));
        // checks if balances are accurate after deposit
        assertEq(
            expectedBalance1,
            actualBalance1,
            "After transfer balance is not equal to expected value 7"
        );
        assertEq(
            expectedBalance2,
            actualBalance2,
            "After transfer balance is not equal to expected value 8"
        );
    }

    function testTransferYTFailsFuzz(uint256 amountToDeposit, uint256 amountToTransfer) public {
        amountToDeposit = bound(amountToDeposit, 1e18, 100e18);
        amountToTransfer = bound(amountToTransfer, 1, 100e18);
        uint256 expectedIBT = ibt.convertToShares(amountToDeposit);
        uint256 expected = ibt.convertToAssets(expectedIBT);
        uint256 actual = _testDeposit(amountToDeposit, MOCK_ADDR_1);
        assertEq(expected, actual, "After deposit balance is not equal to expected value"); // checks if balances are accurate after deposit

        amountToTransfer = yt.actualBalanceOf(MOCK_ADDR_1) + amountToTransfer;

        bytes memory revertData = abi.encodeWithSelector(
            bytes4(keccak256("ERC20InsufficientBalance(address,uint256,uint256)")),
            MOCK_ADDR_1,
            yt.actualBalanceOf(MOCK_ADDR_1),
            amountToTransfer
        );
        vm.expectRevert(revertData);
        vm.prank(MOCK_ADDR_1);
        yt.transfer(MOCK_ADDR_2, amountToTransfer);
    }

    /**
     * @dev Fuzz tests burning of yt tokens in various yield conditions. In particular, burning should update user's yield only if there have been some positive yield.
     */
    function testBurnFuzz(uint256 amountToDeposit, uint256 amountToBurn, uint16 _rate) public {
        UserDataBeforeAfter memory userData;
        amountToDeposit = bound(amountToDeposit, 0, 1000e18);
        int256 rate = int256(bound(_rate, 0, 99));
        _testDeposit(amountToDeposit, address(this));

        // only negative yield
        _increaseRate(-1 * rate);

        userData.userYTBalanceBefore = yt.actualBalanceOf(address(this));
        uint256 yieldOfUserInIBTBefore = principalToken.getCurrentYieldOfUserInIBT(address(this));
        amountToBurn = bound(amountToBurn, 0, userData.userYTBalanceBefore / 2);

        yt.burn(amountToBurn);

        userData.userYTBalanceAfter = yt.actualBalanceOf(address(this));
        uint256 yieldOfUserInIBTAfter = principalToken.getCurrentYieldOfUserInIBT(address(this));

        assertEq(
            userData.userYTBalanceBefore,
            userData.userYTBalanceAfter + amountToBurn,
            "YieldToken Balance after burn is not equal to expected value"
        );
        assertEq(
            yieldOfUserInIBTBefore,
            yieldOfUserInIBTAfter,
            "yield of user in IBT after burn is not equal to expected value"
        );

        (, uint256 oldIBTRate) = _getPTAndIBTRates();

        userData.userYTBalanceBefore = yt.actualBalanceOf(address(this));
        yieldOfUserInIBTBefore = principalToken.getCurrentYieldOfUserInIBT(address(this));
        amountToBurn = bound(amountToBurn, 0, userData.userYTBalanceBefore / 2);

        // only positive yield
        _increaseRate(rate * 4);
        (uint256 newPTRate, uint256 newIBTRate) = _getPTAndIBTRates();

        yt.burn(amountToBurn);

        userData.userYTBalanceAfter = yt.actualBalanceOf(address(this));
        yieldOfUserInIBTAfter = principalToken.getCurrentYieldOfUserInIBT(address(this));

        assertEq(
            userData.userYTBalanceBefore,
            userData.userYTBalanceAfter + amountToBurn,
            "Balance after burn is not equal to expected value"
        );
        assertApproxEqAbs(
            yieldOfUserInIBTBefore +
                _convertToSharesWithRate(
                    _convertToAssetsWithRate(
                        _convertToSharesWithRate(
                            _convertToAssetsWithRate(
                                userData.userYTBalanceBefore,
                                newPTRate,
                                false,
                                true,
                                Math.Rounding.Floor
                            ),
                            oldIBTRate,
                            true,
                            true,
                            Math.Rounding.Floor
                        ),
                        (newIBTRate - oldIBTRate),
                        true,
                        true,
                        Math.Rounding.Floor
                    ),
                    newIBTRate,
                    true,
                    false,
                    Math.Rounding.Floor
                ),
            yieldOfUserInIBTAfter,
            1000,
            "yield of user in IBT after burn is not equal to expected value"
        );

        // both negative and positive yield variations
        oldIBTRate = newIBTRate;
        uint256 oldPTRate = newPTRate;
        _increaseRate((-1 * rate) / 4);
        // another user deposits (updating pt rate)
        amountToDeposit = bound(amountToDeposit, 0, 1e18);
        _testDeposit(amountToDeposit, MOCK_ADDR_1);

        userData.userYTBalanceBefore = yt.actualBalanceOf(address(this));
        yieldOfUserInIBTBefore = principalToken.getCurrentYieldOfUserInIBT(address(this));
        amountToBurn = bound(amountToBurn, 0, userData.userYTBalanceBefore / 2);

        _increaseRate((3 * rate) / 4);
        (newPTRate, newIBTRate) = _getPTAndIBTRates();

        uint256 IBTLostThroughPTAsCollateralPerYT = _convertToSharesWithRate(
            _convertToAssetsWithRate(
                yt.actualBalanceOf(address(this)),
                (oldPTRate - newPTRate),
                false,
                true,
                Math.Rounding.Floor
            ),
            newIBTRate,
            true,
            false,
            Math.Rounding.Floor
        );
        uint256 IBTAddedInPositiveYield;
        uint256 _ibtRate;
        if (newIBTRate >= oldIBTRate) {
            _ibtRate = newIBTRate - oldIBTRate;
        } else {
            _ibtRate = oldIBTRate - newIBTRate;
        }
        IBTAddedInPositiveYield =
            IBTLostThroughPTAsCollateralPerYT +
            _convertToSharesWithRate(
                _convertToAssetsWithRate(
                    _convertToSharesWithRate(
                        _convertToAssetsWithRate(
                            yt.actualBalanceOf(address(this)),
                            oldPTRate,
                            false,
                            true,
                            Math.Rounding.Floor
                        ),
                        oldIBTRate,
                        true,
                        true,
                        Math.Rounding.Floor
                    ),
                    _ibtRate,
                    true,
                    true,
                    Math.Rounding.Floor
                ),
                newIBTRate,
                true,
                false,
                Math.Rounding.Floor
            );

        yt.burn(amountToBurn);

        userData.userYTBalanceAfter = yt.actualBalanceOf(address(this));
        yieldOfUserInIBTAfter = principalToken.getCurrentYieldOfUserInIBT(address(this));

        assertEq(
            userData.userYTBalanceBefore,
            userData.userYTBalanceAfter + amountToBurn,
            "Balance after burn is not equal to expected value"
        );
        assertApproxEqAbs(
            yieldOfUserInIBTBefore + IBTAddedInPositiveYield,
            yieldOfUserInIBTAfter,
            1000,
            "yield of user in IBT after burn is not equal to expected value"
        );
    }

    /**
     * @dev Fuzz tests burnWithoutUpdate of YT in various yield conditions.
     * As opposed to the normal burn, calling burnWithoutUpdate of some YT amount should not update user yield
     * and hence erase the user yield generated for this amount since last update.
     */
    function testBurnWithoutUpdateFuzz(
        uint256 amountToDeposit,
        uint256 amountToBurn,
        uint16 _rate
    ) public {
        amountToDeposit = bound(amountToDeposit, 0, 1000e18);
        int256 rate = int256(bound(_rate, 0, 99));

        _testDeposit(amountToDeposit, address(this));

        uint256 ytBalanceBefore = yt.actualBalanceOf(address(this));
        amountToBurn = bound(amountToBurn, 0, ytBalanceBefore / 2);
        uint256 yieldOfUserInIBTBefore = principalToken.getCurrentYieldOfUserInIBT(address(this));

        // only negative yield
        _increaseRate(-1 * rate);

        vm.prank(address(principalToken));
        yt.burnWithoutUpdate(address(this), amountToBurn);

        uint256 ytBalanceAfter = yt.actualBalanceOf(address(this));
        uint256 yieldOfUserInIBTAfter = principalToken.getCurrentYieldOfUserInIBT(address(this));

        assertEq(
            ytBalanceBefore,
            ytBalanceAfter + amountToBurn,
            "YieldToken Balance after burn is not equal to expected value"
        );
        assertEq(yieldOfUserInIBTBefore, 0, "Yield of user is 0 after only negative yield");
        assertEq(
            yieldOfUserInIBTBefore,
            yieldOfUserInIBTAfter,
            "Yield of user is same before and after negative yield is generated"
        );

        // only positive yield
        _increaseRate(rate + 1);

        ytBalanceBefore = yt.actualBalanceOf(address(this));
        amountToBurn = bound(amountToBurn, 0, ytBalanceBefore / 2);
        yieldOfUserInIBTBefore = principalToken.getCurrentYieldOfUserInIBT(address(this));

        vm.prank(address(principalToken));
        yt.burnWithoutUpdate(address(this), amountToBurn);

        ytBalanceAfter = yt.actualBalanceOf(address(this));
        yieldOfUserInIBTAfter = principalToken.getCurrentYieldOfUserInIBT(address(this));

        assertEq(
            ytBalanceBefore,
            ytBalanceAfter + amountToBurn,
            "Balance after burn is not equal to expected value"
        );
        // the yield of the user hasn't been updated so the yt burn without update would simply decrease the user yield
        if (ytBalanceBefore != 0) {
            assertApproxEqAbs(
                yieldOfUserInIBTBefore.mulDiv(ytBalanceAfter, ytBalanceBefore),
                yieldOfUserInIBTAfter,
                1,
                "yield of user in IBT after burn is not equal to expected value"
            );
        }

        // both negative and positive yield variations
        _increaseRate((-1 * rate) / 4);
        // another deposit (updating pt rate)
        amountToDeposit = bound(amountToDeposit, 0, 1e18);
        _testDeposit(amountToDeposit, MOCK_ADDR_1);

        _increaseRate((3 * rate) / 4);

        ytBalanceBefore = yt.actualBalanceOf(address(this));
        amountToBurn = bound(amountToBurn, 0, ytBalanceBefore / 2);
        yieldOfUserInIBTBefore = principalToken.getCurrentYieldOfUserInIBT(address(this));

        vm.prank(address(principalToken));
        yt.burnWithoutUpdate(address(this), amountToBurn);

        ytBalanceAfter = yt.actualBalanceOf(address(this));
        yieldOfUserInIBTAfter = principalToken.getCurrentYieldOfUserInIBT(address(this));

        assertEq(
            ytBalanceBefore,
            ytBalanceAfter + amountToBurn,
            "Balance after burn is not equal to expected value"
        );
        if (ytBalanceBefore != 0) {
            assertApproxEqAbs(
                yieldOfUserInIBTBefore.mulDiv(ytBalanceAfter, ytBalanceBefore),
                yieldOfUserInIBTAfter,
                ibt.convertToShares(100), // because of safety bound in last else of _computeYield
                "yield of user in IBT after burn is not equal to expected value"
            );
        }
    }

    /**==DEPOSIT FUZZ TEST==**/
    function testDepositFuzz(uint256 amountToDeposit) public {
        amountToDeposit = bound(amountToDeposit, 1e18, 100000e18);
        _testDeposit(amountToDeposit, MOCK_ADDR_1);
    }

    function testDeposit1Fuzz(uint256 amountToDeposit, uint16 _rate) public {
        amountToDeposit = bound(amountToDeposit, 1, 1000e18);
        int256 rate = int256(bound(_rate, 0, 100));
        _testDeposit(amountToDeposit, MOCK_ADDR_1);
        _increaseRate(rate);
        _testDeposit(amountToDeposit, MOCK_ADDR_1);
    }

    function testDeposit2Fuzz(uint256 amountToDeposit, uint16 _rate) public {
        amountToDeposit = bound(amountToDeposit, 100000, 1000e18);
        int256 rate = int256(bound(_rate, 0, 99));
        _testDeposit(amountToDeposit, MOCK_ADDR_1);

        _increaseRate(-1 * rate);

        _testDeposit(amountToDeposit, MOCK_ADDR_1);

        _increaseRate(-1 * rate);

        _testDeposit(amountToDeposit, address(this));

        _testDeposit(amountToDeposit * 2, MOCK_ADDR_1);
    }

    /**==DEPOSIT WITH IBT FUZZ TEST==**/
    function testMultipleDepositIBTFuzzRates(uint256 amountOfIbtToDeposit, uint16 _rate) public {
        amountOfIbtToDeposit = bound(amountOfIbtToDeposit, 0, 1000e18);
        int256 rate = int256(bound(_rate, 0, 199));

        uint256 ptBalanceUserBefore = principalToken.balanceOf(testUser);
        uint256 ytBalanceUserBefore = yt.actualBalanceOf(testUser);
        _prepareForDepositIBT(testUser, amountOfIbtToDeposit);

        uint256 ptMintedByFuture1 = _testDepositIBT(amountOfIbtToDeposit, testUser);

        _increaseRate(100 - rate);

        _prepareForDepositIBT(testUser, amountOfIbtToDeposit);
        uint256 ptMintedByFuture2 = _testDepositIBT(amountOfIbtToDeposit, testUser);

        _increaseRate(-1 * (100 - rate) + 1);

        _prepareForDepositIBT(testUser, amountOfIbtToDeposit);
        uint256 ptMintedByFuture3 = _testDepositIBT(amountOfIbtToDeposit, testUser);

        assertApproxEqAbs(
            principalToken.balanceOf(testUser),
            ptBalanceUserBefore + ptMintedByFuture1 + ptMintedByFuture2 + ptMintedByFuture3,
            1000,
            "After deposit with IBT, PT balance is not equal to expected value"
        );

        assertApproxEqAbs(
            yt.actualBalanceOf(testUser),
            ytBalanceUserBefore + ptMintedByFuture1 + ptMintedByFuture2 + ptMintedByFuture3,
            1000,
            "After deposit with IBT, YieldToken balance is not equal to expected value"
        );
    }

    function testDepositIBTFuzz(uint256 amountOfIbtToDeposit) public {
        amountOfIbtToDeposit = bound(amountOfIbtToDeposit, 1, 1000e18);
        _prepareForDepositIBT(MOCK_ADDR_1, amountOfIbtToDeposit);

        vm.startPrank(MOCK_ADDR_1);
        ibt.approve(address(principalToken), amountOfIbtToDeposit);
        principalToken.depositIBT(amountOfIbtToDeposit, MOCK_ADDR_1);
        vm.stopPrank();

        uint256 ptBalance = principalToken.balanceOf(MOCK_ADDR_1);
        uint256 ytBalance = yt.actualBalanceOf(MOCK_ADDR_1);

        // checks if PT balance is equal to deposited amount since rate = 1
        assertApproxEqAbs(
            ptBalance,
            amountOfIbtToDeposit,
            1000,
            "After Deposit PT balance is not equal to expected value"
        );

        // checks if YieldToken balance is equal to deposited amount since rate = 1
        assertApproxEqAbs(
            ytBalance,
            amountOfIbtToDeposit,
            1000,
            "After Deposit YieldToken balance is not equal to expected value"
        );

        // check IBT balance of PT contract
        uint256 ibtBalance = ibt.balanceOf(address(principalToken));
        assertApproxEqAbs(
            ibtBalance,
            amountOfIbtToDeposit,
            1000,
            "After Deposit IBT balance of vualt is not equal to expected value"
        );
    }

    function testDepositIBT1Fuzz(uint256 amountOfIbtToDeposit, uint16 _rate) public {
        amountOfIbtToDeposit = bound(amountOfIbtToDeposit, 0, 100e18);
        int256 rate = int256(bound(_rate, 0, 199));
        _prepareForDepositIBT(MOCK_ADDR_1, amountOfIbtToDeposit);
        _testDepositIBT(amountOfIbtToDeposit, MOCK_ADDR_1);

        _increaseRate(100 - rate);

        _prepareForDepositIBT(MOCK_ADDR_1, amountOfIbtToDeposit);
        _testDepositIBT(amountOfIbtToDeposit, MOCK_ADDR_1);
    }

    function testDepositIBT2Fuzz(uint256 amountOfIbtToDeposit, uint16 _rate) public {
        amountOfIbtToDeposit = bound(amountOfIbtToDeposit, 1e4, 100e18);
        int256 rate = int256(bound(_rate, 0, 99));
        _prepareForDepositIBT(MOCK_ADDR_1, amountOfIbtToDeposit);
        _testDepositIBT(amountOfIbtToDeposit, MOCK_ADDR_1);

        _increaseRate(-1 * rate);

        _prepareForDepositIBT(MOCK_ADDR_1, amountOfIbtToDeposit);

        (ptRate, ibtRate) = _getPTAndIBTRates();
        _testDepositIBT(amountOfIbtToDeposit, MOCK_ADDR_1);

        _increaseRate(-1 * rate);

        _prepareForDepositIBT(MOCK_ADDR_1, amountOfIbtToDeposit);
        (ptRate, ibtRate) = _getPTAndIBTRates();
        _testDepositIBT(amountOfIbtToDeposit, MOCK_ADDR_1);
    }

    // Test Multiple functions fuzzing

    function testMultipleFunctions1Fuzz(
        uint256 amountToDeposit1,
        uint256 amountToDeposit2,
        uint16 _rate1,
        uint16 _rate2
    ) public {
        amountToDeposit1 = bound(amountToDeposit1, 0, 100e18);
        amountToDeposit2 = bound(amountToDeposit2, 0, 10e18);
        int256 rate1 = int256(bound(_rate1, 0, 100));
        int256 rate2 = int256(bound(_rate2, 5, 80));
        UserRate memory user1;
        UserRate memory user2;
        UserRate memory user3;
        UserRate memory user4;
        UserRate memory user5;

        _testDeposit(amountToDeposit1 / 2, MOCK_ADDR_1);
        user1.oldPTRate = ptRate;
        user1.oldIBTRate = ibtRate;

        _prepareForDepositIBT(MOCK_ADDR_2, amountToDeposit2);
        _testDepositIBT(amountToDeposit2, MOCK_ADDR_2);
        user2.oldPTRate = ptRate;
        user2.oldIBTRate = ibtRate;

        _increaseRate(rate1);

        // transfer some pt to user3

        _transferPT(MOCK_ADDR_1, MOCK_ADDR_3, principalToken.balanceOf(MOCK_ADDR_1) / 2);

        _increaseRate(rate2);

        uint256 yieldInIBT = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_1);
        (ptRate, ibtRate) = _getPTAndIBTRates();
        user1 = _testYieldUpdate(MOCK_ADDR_1, user1, ptRate, ibtRate, yieldInIBT);

        yieldInIBT = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_3);
        user3 = _testYieldUpdate(MOCK_ADDR_3, user3, ptRate, ibtRate, yieldInIBT);

        _transferYT(MOCK_ADDR_1, MOCK_ADDR_3, yt.actualBalanceOf(MOCK_ADDR_1) / 2);

        _increaseRate(-1 * (rate1 / 2));

        _testDeposit(amountToDeposit1, MOCK_ADDR_4);
        (ptRate, ibtRate) = _getPTAndIBTRates();
        user4.oldIBTRate = ibtRate;
        user4.oldPTRate = ptRate;

        yieldInIBT = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_3);
        user3 = _testYieldUpdate(MOCK_ADDR_3, user3, ptRate, ibtRate, yieldInIBT);

        uint256 maxWithdraw = principalToken.maxWithdraw(MOCK_ADDR_3);
        _testWithdraw(maxWithdraw, MOCK_ADDR_3, MOCK_ADDR_3);

        _increaseRate(rate2 / 2);

        _testDeposit(amountToDeposit1, MOCK_ADDR_5);
        (ptRate, ibtRate) = _getPTAndIBTRates();
        user5.oldIBTRate = ibtRate;
        user5.oldPTRate = ptRate;

        yieldInIBT = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_1);
        user1 = _testYieldUpdate(MOCK_ADDR_1, user1, ptRate, ibtRate, yieldInIBT);

        maxWithdraw = principalToken.maxWithdraw(MOCK_ADDR_1);
        _testWithdraw(maxWithdraw, MOCK_ADDR_1, MOCK_ADDR_1);

        _increaseTimeToExpiry();
        principalToken.storeRatesAtExpiry();

        yieldInIBT = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_4);
        user4 = _testYieldUpdate(MOCK_ADDR_4, user4, ptRate, ibtRate, yieldInIBT);

        _testRedeemMaxAndClaimYield(MOCK_ADDR_4, MOCK_ADDR_4);

        yieldInIBT = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_2);
        user2 = _testYieldUpdate(MOCK_ADDR_2, user2, ptRate, ibtRate, yieldInIBT);
        yieldInIBT = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_5);
        user5 = _testYieldUpdate(MOCK_ADDR_5, user5, ptRate, ibtRate, yieldInIBT);

        _testRedeem(principalToken.balanceOf(MOCK_ADDR_2), MOCK_ADDR_2);
        _testRedeem(principalToken.balanceOf(MOCK_ADDR_5), MOCK_ADDR_5);
    }

    function testMultipleFunctions2Fuzz(
        uint256 amountToDeposit1,
        uint256 amountToDeposit2,
        uint16 _rate1,
        uint16 _rate2
    ) public {
        amountToDeposit1 = bound(amountToDeposit1, 1e5, 100e18);
        amountToDeposit2 = bound(amountToDeposit2, 1e5, 10e18);
        int256 rate1 = int256(bound(_rate1, 1, 100));
        int256 rate2 = int256(bound(_rate2, 5, 80));
        UserRate memory user1;
        UserRate memory user2;
        UserRate memory user3;
        UserRate memory user4;
        UserRate memory user5;

        _testDeposit(amountToDeposit1 / 2, MOCK_ADDR_1);
        user1.oldPTRate = ptRate;
        user1.oldIBTRate = ibtRate;

        _increaseRate(-1 * (rate1 / 3));

        _testDeposit(amountToDeposit2, MOCK_ADDR_2);
        (ptRate, ibtRate) = _getPTAndIBTRates();
        user2.oldPTRate = ptRate;
        user2.oldIBTRate = ibtRate;

        _increaseRate(rate1);

        _testDeposit(amountToDeposit1 + amountToDeposit2, MOCK_ADDR_3);
        (ptRate, ibtRate) = _getPTAndIBTRates();
        user3.oldPTRate = ptRate;
        user3.oldIBTRate = ibtRate;

        _transferPT(MOCK_ADDR_1, MOCK_ADDR_4, principalToken.balanceOf(MOCK_ADDR_1) / 3);

        _increaseRate(-1 * (rate2 / 3));

        uint256 yieldInIBT = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_1);
        (ptRate, ibtRate) = _getPTAndIBTRates();
        user1 = _testYieldUpdate(MOCK_ADDR_1, user1, ptRate, ibtRate, yieldInIBT);

        yieldInIBT = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_4);
        user4 = _testYieldUpdate(MOCK_ADDR_4, user4, ptRate, ibtRate, yieldInIBT);

        _transferYT(MOCK_ADDR_1, MOCK_ADDR_4, yt.actualBalanceOf(MOCK_ADDR_1) / 2);

        _increaseRate(rate1 + rate2);

        yieldInIBT = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_1);
        (ptRate, ibtRate) = _getPTAndIBTRates();
        user1 = _testYieldUpdate(MOCK_ADDR_1, user1, ptRate, ibtRate, yieldInIBT);

        uint256 maxWithdraw = principalToken.maxWithdraw(MOCK_ADDR_1);
        _testWithdraw(maxWithdraw, MOCK_ADDR_1, MOCK_ADDR_1);

        _testDeposit(amountToDeposit1 / 3, MOCK_ADDR_5);
        (ptRate, ibtRate) = _getPTAndIBTRates();
        user5.oldPTRate = ptRate;
        user5.oldIBTRate = ibtRate;

        _increaseRate(-1 * (rate1 / 4));

        yieldInIBT = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_3);
        (ptRate, ibtRate) = _getPTAndIBTRates();
        user3 = _testYieldUpdate(MOCK_ADDR_3, user3, ptRate, ibtRate, yieldInIBT);

        maxWithdraw = principalToken.maxWithdraw(MOCK_ADDR_3);
        _testWithdraw(maxWithdraw, MOCK_ADDR_3, MOCK_ADDR_3);

        _increaseTimeToExpiry();
        principalToken.storeRatesAtExpiry();

        yieldInIBT = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_4);
        user4 = _testYieldUpdate(MOCK_ADDR_4, user4, ptRate, ibtRate, yieldInIBT);

        _testRedeemMaxAndClaimYield(MOCK_ADDR_4, MOCK_ADDR_4);

        yieldInIBT = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_2);
        user2 = _testYieldUpdate(MOCK_ADDR_2, user2, ptRate, ibtRate, yieldInIBT);
        yieldInIBT = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_5);
        user5 = _testYieldUpdate(MOCK_ADDR_5, user5, ptRate, ibtRate, yieldInIBT);

        _testRedeem(principalToken.balanceOf(MOCK_ADDR_2), MOCK_ADDR_2);
        _testRedeem(principalToken.balanceOf(MOCK_ADDR_5), MOCK_ADDR_5);
    }

    function testMultipleFunctions3Fuzz(
        uint256 amountToDeposit1,
        uint256 amountToDeposit2,
        uint16 _rate1,
        uint16 _rate2
    ) public {
        amountToDeposit1 = bound(amountToDeposit1, 1e5, 100e18);
        amountToDeposit2 = bound(amountToDeposit2, 1e5, 10e18);
        int256 rate1 = int256(bound(_rate1, 10, 100));
        int256 rate2 = int256(bound(_rate2, 5, 80));

        _increaseRate(rate1 + rate2);

        UserRate memory user1;
        UserRate memory user2;
        UserRate memory user3;
        UserRate memory user4;
        UserRate memory user5;

        _testDeposit(amountToDeposit1, MOCK_ADDR_1);
        (ptRate, ibtRate) = _getPTAndIBTRates();
        user1.oldPTRate = ptRate;
        user1.oldIBTRate = ibtRate;

        _increaseRate(-1 * (rate1 / 2));

        _testDeposit(amountToDeposit2, MOCK_ADDR_2);
        (ptRate, ibtRate) = _getPTAndIBTRates();
        user2.oldPTRate = ptRate;
        user2.oldIBTRate = ibtRate;

        _increaseRate(rate2);

        uint256 yieldInIBT = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_1);
        (ptRate, ibtRate) = _getPTAndIBTRates();
        user1 = _testYieldUpdate(MOCK_ADDR_1, user1, ptRate, ibtRate, yieldInIBT);

        _claimYield(MOCK_ADDR_1);
        user1.oldYieldOfUserInIBT = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_1);

        _testDeposit(amountToDeposit1 / 2, MOCK_ADDR_3);
        user3.oldPTRate = ptRate;
        user3.oldIBTRate = ibtRate;

        _increaseRate(-1 * (rate1 / 5));

        yieldInIBT = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_1);
        (ptRate, ibtRate) = _getPTAndIBTRates();
        user1 = _testYieldUpdate(MOCK_ADDR_1, user1, ptRate, ibtRate, yieldInIBT);
        yieldInIBT = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_2);
        user2 = _testYieldUpdate(MOCK_ADDR_2, user2, ptRate, ibtRate, yieldInIBT);

        _claimYield(MOCK_ADDR_1);
        _claimYield(MOCK_ADDR_2);
        user1.oldYieldOfUserInIBT = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_1);
        user2.oldYieldOfUserInIBT = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_2);

        _increaseRate(-1 * (rate2 / 4));

        _testDeposit(2 * (amountToDeposit1 + amountToDeposit2), MOCK_ADDR_4);
        _testDeposit(2 * (amountToDeposit1 + amountToDeposit2), MOCK_ADDR_5);
        (ptRate, ibtRate) = _getPTAndIBTRates();
        user4.oldPTRate = ptRate;
        user4.oldIBTRate = ibtRate;
        user5.oldPTRate = ptRate;
        user5.oldIBTRate = ibtRate;

        _transferYT(MOCK_ADDR_4, MOCK_ADDR_5, yt.actualBalanceOf(MOCK_ADDR_4) / 2);

        _increaseRate(rate1);

        yieldInIBT = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_1);
        (ptRate, ibtRate) = _getPTAndIBTRates();
        user1 = _testYieldUpdate(MOCK_ADDR_1, user1, ptRate, ibtRate, yieldInIBT);

        uint256 maxWithdraw = principalToken.maxWithdraw(MOCK_ADDR_1);
        _testWithdraw(maxWithdraw, MOCK_ADDR_1, MOCK_ADDR_1);

        yieldInIBT = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_3);
        user3 = _testYieldUpdate(MOCK_ADDR_3, user3, ptRate, ibtRate, yieldInIBT);

        maxWithdraw = principalToken.maxWithdraw(MOCK_ADDR_3);
        _testWithdraw(maxWithdraw, MOCK_ADDR_3, MOCK_ADDR_3);

        _increaseTimeToExpiry();
        principalToken.storeRatesAtExpiry();

        yieldInIBT = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_4);
        user4 = _testYieldUpdate(MOCK_ADDR_4, user4, ptRate, ibtRate, yieldInIBT);

        _testRedeemMaxAndClaimYield(MOCK_ADDR_4, MOCK_ADDR_4);

        yieldInIBT = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_2);
        user2 = _testYieldUpdate(MOCK_ADDR_2, user2, ptRate, ibtRate, yieldInIBT);
        yieldInIBT = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_5);
        user5 = _testYieldUpdate(MOCK_ADDR_5, user5, ptRate, ibtRate, yieldInIBT);

        _testRedeem(principalToken.balanceOf(MOCK_ADDR_2), MOCK_ADDR_2);
        _testRedeem(principalToken.balanceOf(MOCK_ADDR_5), MOCK_ADDR_5);
    }

    function testMultipleFunctions4Fuzz(
        uint256 amountToDeposit1,
        uint256 amountToDeposit2,
        uint16 _rate1,
        uint16 _rate2
    ) public {
        amountToDeposit1 = bound(amountToDeposit1, 1e5, 100e18);
        amountToDeposit2 = bound(amountToDeposit2, 1e5, 10e18);
        int256 rate1 = int256(bound(_rate1, 10, 100));
        int256 rate2 = int256(bound(_rate2, 5, 80));

        _increaseRate(-1 * ((rate1 + rate2) / 2));

        _increaseRate((rate1 + rate2) * 2);

        UserRate memory user1;
        UserRate memory user2;
        UserRate memory user3;
        UserRate memory user4;
        UserRate memory user5;
        _testDeposit(amountToDeposit1, MOCK_ADDR_1);
        (ptRate, ibtRate) = _getPTAndIBTRates();
        user1.oldPTRate = ptRate;
        user1.oldIBTRate = ibtRate;

        _increaseRate(-1 * (rate2 / 2));

        _testDeposit(amountToDeposit2, MOCK_ADDR_2);
        (ptRate, ibtRate) = _getPTAndIBTRates();
        user2.oldPTRate = ptRate;
        user2.oldIBTRate = ibtRate;

        _increaseRate(rate2);

        uint256 yieldInIBT = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_1);
        (ptRate, ibtRate) = _getPTAndIBTRates();
        user1 = _testYieldUpdate(MOCK_ADDR_1, user1, ptRate, ibtRate, yieldInIBT);

        _transferYT(MOCK_ADDR_1, MOCK_ADDR_3, yt.actualBalanceOf(MOCK_ADDR_1) / 2);

        _testDeposit(amountToDeposit1 / 2, MOCK_ADDR_3);
        (ptRate, ibtRate) = _getPTAndIBTRates();
        user3.oldPTRate = ptRate;
        user3.oldIBTRate = ibtRate;

        _increaseRate(rate1 / 2);

        yieldInIBT = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_1);
        (ptRate, ibtRate) = _getPTAndIBTRates();
        user1 = _testYieldUpdate(MOCK_ADDR_1, user1, ptRate, ibtRate, yieldInIBT);
        yieldInIBT = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_2);
        user2 = _testYieldUpdate(MOCK_ADDR_2, user2, ptRate, ibtRate, yieldInIBT);

        _claimYield(MOCK_ADDR_1);
        _claimYield(MOCK_ADDR_2);
        user1.oldYieldOfUserInIBT = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_1);
        user2.oldYieldOfUserInIBT = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_2);

        _testDeposit(amountToDeposit1 + amountToDeposit2, MOCK_ADDR_4);
        _testDeposit(amountToDeposit1 + amountToDeposit2, MOCK_ADDR_5);
        (ptRate, ibtRate) = _getPTAndIBTRates();
        user4.oldPTRate = ptRate;
        user4.oldIBTRate = ibtRate;
        user5.oldPTRate = ptRate;
        user5.oldIBTRate = ibtRate;

        _increaseRate(-1 * (rate2 / 3));

        _transferPT(MOCK_ADDR_5, MOCK_ADDR_4, principalToken.balanceOf(MOCK_ADDR_5));

        yieldInIBT = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_1);
        (ptRate, ibtRate) = _getPTAndIBTRates();
        user1 = _testYieldUpdate(MOCK_ADDR_1, user1, ptRate, ibtRate, yieldInIBT);
        yieldInIBT = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_2);
        user2 = _testYieldUpdate(MOCK_ADDR_2, user2, ptRate, ibtRate, yieldInIBT);

        uint256 maxWithdraw = principalToken.maxWithdraw(MOCK_ADDR_1);
        _testWithdraw(maxWithdraw, MOCK_ADDR_1, MOCK_ADDR_1);

        maxWithdraw = principalToken.maxWithdraw(MOCK_ADDR_2);
        _testWithdraw(maxWithdraw, MOCK_ADDR_2, MOCK_ADDR_2);

        _increaseRate(-1 * (rate2));

        _increaseTimeToExpiry();
        principalToken.storeRatesAtExpiry();

        yieldInIBT = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_3);
        user3 = _testYieldUpdate(MOCK_ADDR_3, user3, ptRate, ibtRate, yieldInIBT);
        (ptRate, ibtRate) = _getPTAndIBTRates();

        _testRedeemMaxAndClaimYield(MOCK_ADDR_2, MOCK_ADDR_3);

        yieldInIBT = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_4);
        user4 = _testYieldUpdate(MOCK_ADDR_4, user4, ptRate, ibtRate, yieldInIBT);
        yieldInIBT = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_5);
        user5 = _testYieldUpdate(MOCK_ADDR_5, user5, ptRate, ibtRate, yieldInIBT);

        _testRedeem(principalToken.balanceOf(MOCK_ADDR_4), MOCK_ADDR_4);
        _testRedeem(principalToken.balanceOf(MOCK_ADDR_5), MOCK_ADDR_5);
    }

    /**===Redeem Fuzz Test==**/

    function testPreviewRedeemFuzz(uint256 amountToDeposit, uint256 amountToRedeem) public {
        amountToDeposit = bound(amountToDeposit, 1, 100_000e18);
        amountToRedeem = bound(amountToRedeem, 0, amountToDeposit);

        underlying.mint(address(this), amountToDeposit);
        underlying.approve(address(principalToken), amountToDeposit);
        principalToken.deposit(amountToDeposit, address(this));

        uint256 previewRedeem = principalToken.previewRedeem(amountToRedeem);

        _increaseTimeToExpiry();
        assertEq(
            previewRedeem,
            principalToken.previewRedeem(amountToRedeem),
            "PreviewRedeem is wrong after storeRatesAtExpiry"
        );

        principalToken.storeRatesAtExpiry();
        assertEq(
            previewRedeem,
            principalToken.previewRedeem(amountToRedeem),
            "PreviewRedeem is wrong after storeRatesAtExpiry"
        );

        // increase time
        vm.warp(block.timestamp + 10000);

        assertEq(
            previewRedeem,
            principalToken.previewRedeem(amountToRedeem),
            "PreviewRedeem is wrong after increasing time"
        );

        // assuming 0 tokenization fee
        uint256 expected = ibt.previewRedeem(
            _convertPTSharesToIBTsWithRates(
                amountToRedeem,
                principalToken.getPTRate(),
                principalToken.getIBTRate(),
                false
            )
        );
        assertEq(expected, previewRedeem, "PreviewRedeem is not equal to expected value");
    }

    function testPreviewRedeemFuzz2(uint256 amount, uint16 _rate) public {
        amount = bound(amount, 0, 100000e18);
        int256 rate = int256(bound(_rate, 1, 99));
        _increaseTimeToExpiry();
        _increaseRate(-1 * rate);
        principalToken.storeRatesAtExpiry();
        uint256 ptRateAtExpiry = principalToken.getPTRate();
        uint256 ibtRateAtExpiry = principalToken.getIBTRate();
        uint256 ptInIBTAtExpiry = _convertPTSharesToIBTsWithRates(
            amount,
            ptRateAtExpiry,
            ibtRateAtExpiry,
            false
        );
        uint256 assets1 = ibt.previewRedeem(ptInIBTAtExpiry);
        vm.warp(block.timestamp + 10000);
        _increaseRate(rate);
        uint256 assets2 = ibt.previewRedeem(ptInIBTAtExpiry);
        vm.warp(block.timestamp + 10000);
        _increaseRate(-1 * rate);
        uint256 assets3 = ibt.previewRedeem(ptInIBTAtExpiry);
        _increaseRate(-1 * rate);
        bytes memory revertData = abi.encodeWithSignature("RatesAtExpiryAlreadyStored()");
        vm.expectRevert(revertData);
        principalToken.storeRatesAtExpiry();
        uint256 assets4 = ibt.previewRedeem(ptInIBTAtExpiry);

        uint256 actualAssetsRedeemed = principalToken.previewRedeem(amount);
        assertApproxEqAbs(
            actualAssetsRedeemed,
            assets4,
            1000,
            "Preview redeem amount is not equal to expected assets4 value"
        );
        if (amount > 10000) {
            assertGt(
                assets2,
                assets1,
                "assets2 should be greater than assets1 as there have been positive yield between both"
            );
            assertGt(
                assets1,
                assets3,
                "assets1 should be greater than assets3 as there have been same positive then negative yield between both"
            );
            assertGt(
                assets3,
                assets4,
                "assets3 should be greater than assets4 as there have been negative yield between both"
            );
        }
    }

    function testRedeemTrivialFuzz(uint256 amount) public {
        amount = bound(amount, 0, 100000e18);
        uint256 expected = _testDeposit(amount, MOCK_ADDR_1);
        _increaseTimeToExpiry();
        principalToken.storeRatesAtExpiry();
        uint256 userPTBalanceBefore = principalToken.balanceOf(MOCK_ADDR_1);
        uint256 mockUnderlyingBalanceBefore = underlying.balanceOf(MOCK_ADDR_2);
        vm.prank(MOCK_ADDR_1);
        uint256 actual = principalToken.redeem(amount, MOCK_ADDR_2, MOCK_ADDR_1);
        assertTrue(expected == actual, "Redeem's return value is wrong");
        assertTrue(
            userPTBalanceBefore == principalToken.balanceOf(MOCK_ADDR_1) + actual,
            "User balance after redeem is wrong"
        );
        assertTrue(
            expected + mockUnderlyingBalanceBefore == underlying.balanceOf(MOCK_ADDR_2),
            "Mock balance after redeem is wrong"
        );
    }

    function testRedeemFailFuzz(uint256 amountToDeposit, uint256 amountToRedeem) public {
        amountToDeposit = bound(amountToDeposit, 1, 100_000e18);
        amountToRedeem = bound(amountToRedeem, amountToDeposit + 1, 200_000e18);

        _testDeposit(amountToDeposit, MOCK_ADDR_1);
        bytes memory revertData = abi.encodeWithSignature("UnauthorizedCaller()");
        vm.expectRevert(revertData);
        principalToken.redeem(amountToDeposit, MOCK_ADDR_2, MOCK_ADDR_1);
        vm.prank(MOCK_ADDR_1);
        revertData = abi.encodeWithSignature("UnsufficientBalance()");
        vm.expectRevert(revertData);
        principalToken.redeem(amountToRedeem, MOCK_ADDR_2, MOCK_ADDR_1);
    }

    function testRedeemFuzz(uint256 amountToDeposit) public {
        amountToDeposit = bound(amountToDeposit, 1e18, 1_000_000e18);
        _testDeposit(amountToDeposit, address(this));

        _testWithdraw(amountToDeposit / 100, MOCK_ADDR_1, address(this));
    }

    function testRedeem1Fuzz(uint256 amountToDeposit, uint16 _rate) public {
        amountToDeposit = bound(amountToDeposit, 1, 10000e18);
        int256 rate = int256(bound(_rate, 0, 100));
        uint256 receivedShares = _testDeposit(amountToDeposit, address(this));

        _increaseRate(rate);

        yt.transfer(MOCK_ADDR_1, receivedShares);
        principalToken.transfer(MOCK_ADDR_1, receivedShares);

        _increaseRate(2 * rate);

        _testRedeemMaxAndClaimYield(address(this), address(this));
        _testRedeemMaxAndClaimYield(MOCK_ADDR_1, MOCK_ADDR_1);
    }

    function testRedeem2Fuzz(uint256 amountToDeposit, uint16 _rate) public {
        amountToDeposit = bound(amountToDeposit, 1, 1_000_000e18);
        int256 rate = int256(bound(_rate, 0, 50));

        uint256 receivedShares = _testDeposit(amountToDeposit, address(this));

        _increaseRate(rate);

        yt.transfer(MOCK_ADDR_1, receivedShares);
        principalToken.transfer(MOCK_ADDR_1, receivedShares);

        _testDeposit(amountToDeposit / 2, MOCK_ADDR_2);

        _increaseRate(2 * rate);

        vm.startPrank(MOCK_ADDR_2);
        yt.transfer(address(this), amountToDeposit / 4);
        principalToken.transfer(address(this), amountToDeposit / 4);
        vm.stopPrank();

        _testRedeemMaxAndClaimYield(address(this), address(this));
        _testRedeemMaxAndClaimYield(MOCK_ADDR_1, MOCK_ADDR_1);
        _testRedeemMaxAndClaimYield(MOCK_ADDR_2, MOCK_ADDR_2);
    }

    function testRedeem3Fuzz(uint256 amountToDeposit, uint16 _rate1, uint16 _rate2) public {
        amountToDeposit = bound(amountToDeposit, 1, 1_000_000e18);
        int256 rate1 = int256(bound(_rate1, 0, 50));
        int256 rate2 = int256(bound(_rate2, 0, 99));

        _testDeposit(amountToDeposit, address(this));

        _increaseRate(-1 * rate1);

        uint256 amount = yt.actualBalanceOf(address(this)) / 2;
        yt.transfer(MOCK_ADDR_1, amount);
        principalToken.transfer(MOCK_ADDR_1, amount);

        _testDeposit(amountToDeposit * 5, MOCK_ADDR_2);

        _increaseRate(-1 * rate2);

        vm.startPrank(MOCK_ADDR_2);
        amount = yt.actualBalanceOf(MOCK_ADDR_2) / 2;
        yt.transfer(address(this), amount);
        principalToken.transfer(address(this), amount);
        vm.stopPrank();

        _testDeposit((amountToDeposit * 2) / 5, MOCK_ADDR_1);

        _increaseRate(rate2);

        _testRedeemMaxAndClaimYield(address(this), address(this));
        _testRedeemMaxAndClaimYield(MOCK_ADDR_1, MOCK_ADDR_1);
        _testRedeemMaxAndClaimYield(MOCK_ADDR_2, MOCK_ADDR_2);
    }

    function testRedeem4Fuzz(
        uint256 amountToDeposit,
        uint16 _rate1,
        uint16 _rate2,
        uint16 _rate3
    ) public {
        amountToDeposit = bound(amountToDeposit, 1e18, 100e18);
        int256 rate1 = int256(bound(_rate1, 40, 80));
        int256 rate2 = int256(bound(_rate2, 80, 100));
        int256 rate3 = int256(bound(_rate3, 1, 40));

        _testDeposit(amountToDeposit, address(this));

        _increaseRate(-1 * rate1);

        _testDeposit(5 * amountToDeposit, address(this));
        _testDeposit(2 * amountToDeposit, MOCK_ADDR_1);

        vm.startPrank(MOCK_ADDR_1);
        uint256 amount = yt.actualBalanceOf(MOCK_ADDR_1) / 2;
        yt.transfer(address(this), amount);
        principalToken.transfer(address(this), amount);
        vm.stopPrank();

        _testRedeem(principalToken.maxRedeem(address(this)) / 2, address(this));
        _testRedeemMaxAndClaimYield(MOCK_ADDR_1, MOCK_ADDR_1);

        _testDeposit(amountToDeposit * 2, address(this));

        _increaseRate(rate2);

        _testDeposit(amountToDeposit / 2, MOCK_ADDR_1);
        _testDeposit(amountToDeposit / 2, MOCK_ADDR_2);

        _increaseRate(rate3);

        _testRedeemMaxAndClaimYield(address(this), address(this));
        _testRedeemMaxAndClaimYield(MOCK_ADDR_1, MOCK_ADDR_1);
        _testRedeemMaxAndClaimYield(MOCK_ADDR_2, MOCK_ADDR_2);
    }

    function testRedeem5Fuzz(uint256 amountToDeposit, uint16 _rate) public {
        amountToDeposit = bound(amountToDeposit, 0, 100e18);
        int256 rate = int256(bound(_rate, 0, 99));

        _testDeposit(amountToDeposit, address(this));

        // decrease rate, increase time
        _increaseRate(-1 * rate);
        _increaseTimeToExpiry();

        _testRedeemMaxAndClaimYield(address(this), address(this));
    }

    function testRedeem6Fuzz(uint256 amountToDeposit, uint16 _rate) public {
        amountToDeposit = bound(amountToDeposit, 1e18, 100e18);
        int256 rate = int256(bound(_rate, 0, 99));
        _testDeposit(amountToDeposit, address(this));
        _testDeposit(amountToDeposit, MOCK_ADDR_1);
        _testDeposit(amountToDeposit, MOCK_ADDR_2);
        _testDeposit(amountToDeposit, MOCK_ADDR_3);
        _testDeposit(amountToDeposit, MOCK_ADDR_4);
        _testDeposit(amountToDeposit, MOCK_ADDR_5);

        _increaseRate(-1 * rate);
        _increaseTimeToExpiry();

        _testRedeemMaxAndClaimYield(address(this), address(this));
        _testRedeemMaxAndClaimYield(MOCK_ADDR_1, MOCK_ADDR_1);
        _testRedeemMaxAndClaimYield(MOCK_ADDR_2, MOCK_ADDR_2);
        _testRedeemMaxAndClaimYield(MOCK_ADDR_3, MOCK_ADDR_3);
        _testRedeemMaxAndClaimYield(MOCK_ADDR_4, MOCK_ADDR_4);
        _testRedeemMaxAndClaimYield(MOCK_ADDR_5, MOCK_ADDR_5);
    }

    function testRedeem7Fuzz(uint256 amountToDeposit, uint16 _rate1, uint16 _rate2) public {
        amountToDeposit = bound(amountToDeposit, 1e18, 100e18);
        int256 rate1 = int256(bound(_rate1, 0, 99));
        int256 rate2 = int256(bound(_rate2, 50, 100));
        _testDeposit(amountToDeposit, address(this));
        _testDeposit(amountToDeposit, MOCK_ADDR_1);
        _testDeposit(amountToDeposit, MOCK_ADDR_2);
        _testDeposit(amountToDeposit, MOCK_ADDR_3);

        _increaseRate(-1 * rate1);

        _testRedeemMaxAndClaimYield(MOCK_ADDR_1, MOCK_ADDR_1);

        _increaseRate(rate2);

        _increaseTimeToExpiry();

        _testRedeemMaxAndClaimYield(address(this), address(this));
        _testRedeemMaxAndClaimYield(MOCK_ADDR_2, MOCK_ADDR_2);
        _testRedeemMaxAndClaimYield(MOCK_ADDR_3, MOCK_ADDR_3);
    }

    function testRedeem8Fuzz(uint256 amountToDeposit, uint16 _rate) public {
        amountToDeposit = bound(amountToDeposit, 1e18, 100e18);
        int256 rate = int256(bound(_rate, 1, 100));
        _testDeposit(amountToDeposit, address(this));

        _increaseRate(rate);

        yt.transfer(MOCK_ADDR_1, yt.actualBalanceOf(address(this)));
        principalToken.transfer(MOCK_ADDR_1, principalToken.balanceOf(address(this)));
        principalToken.claimYield(address(this));

        _testRedeemMaxAndClaimYield(MOCK_ADDR_1, address(this));
    }

    function testRedeem9Fuzz(uint256 amountToDeposit, uint16 _rate1, uint16 _rate2) public {
        amountToDeposit = bound(amountToDeposit, 1e18, 100e18);
        int256 rate1 = int256(bound(_rate1, 1, 100));
        int256 rate2 = int256(bound(_rate2, 1, 99));

        _testDeposit(amountToDeposit, address(this));
        _testDeposit(amountToDeposit, MOCK_ADDR_1);

        _increaseRate(rate1);

        principalToken.claimYield(address(this));

        _increaseRate(-1 * rate2);

        _testRedeemMaxAndClaimYield(address(this), address(this));
    }

    function testRedeem10Fuzz(uint256 amountToDeposit, uint16 _rate) public {
        amountToDeposit = bound(amountToDeposit, 1e3, 100000e18);
        int256 rate = int256(bound(_rate, 1, 500));

        uint256 receivedShares1 = _testDeposit(amountToDeposit, MOCK_ADDR_1);
        _testDeposit(amountToDeposit, MOCK_ADDR_2);

        // user1 redeems all shares before any yield has been generated
        _testRedeem(receivedShares1, MOCK_ADDR_1);

        _increaseRate(rate);

        uint256 underlyingBalanceBeforeUser2 = underlying.balanceOf(MOCK_ADDR_2);

        // user2 claims yield
        uint256 expectedYield = _amountMinusFee(
            (amountToDeposit * uint256(rate)) / 100,
            registry.getYieldFee()
        );
        vm.prank(MOCK_ADDR_2);
        uint256 actualYield = principalToken.claimYield(MOCK_ADDR_2);
        assertApproxEqAbs(
            expectedYield,
            actualYield,
            10,
            "Claimed yield is not equal to expected value"
        );

        uint256 underlyingBalanceAfterUser2 = underlying.balanceOf(MOCK_ADDR_2);
        assertEq(
            underlyingBalanceBeforeUser2 + actualYield,
            underlyingBalanceAfterUser2,
            "After claiming yield, asset balance for user2 is wrong"
        );
    }

    function testRedeem11Fuzz(uint256 amountToDeposit, uint16 _rate) public {
        amountToDeposit = bound(amountToDeposit, 1e3, 100000e18);
        int256 rate = int256(bound(_rate, 1, 500));

        _testDeposit(amountToDeposit, MOCK_ADDR_2);

        // user1 deposits then redeems all shares before any yield has been generated
        uint256 receivedShares1 = _testDeposit(amountToDeposit, MOCK_ADDR_1);
        _testRedeem(receivedShares1, MOCK_ADDR_1);

        _increaseRate(rate);

        uint256 underlyingBalanceBeforeUser2 = underlying.balanceOf(MOCK_ADDR_2);

        // user2 claims yield
        uint256 expectedYield = _amountMinusFee(
            (amountToDeposit * uint256(rate)) / 100,
            registry.getYieldFee()
        );
        vm.prank(MOCK_ADDR_2);
        uint256 actualYield = principalToken.claimYield(MOCK_ADDR_2);
        assertApproxEqAbs(
            expectedYield,
            actualYield,
            10,
            "Claimed yield is not equal to expected value"
        );

        uint256 underlyingBalanceAfterUser2 = underlying.balanceOf(MOCK_ADDR_2);
        assertEq(
            underlyingBalanceBeforeUser2 + actualYield,
            underlyingBalanceAfterUser2,
            "After claiming yield, asset balance for user2 is wrong"
        );
    }

    function testRedeem12Fuzz(
        uint256 amountToDeposit,
        uint16 _rate1,
        uint16 _rate2,
        uint16 _rate3
    ) public {
        amountToDeposit = bound(amountToDeposit, 1e3, 100000e18);
        int256 rate1 = int256(bound(_rate1, 1, 50));
        int256 rate2 = int256(bound(_rate2, 1, 50));
        int256 rate3 = int256(bound(_rate3, 100, 200));

        _increaseRate(rate1);

        uint256 shares1 = _testDeposit(amountToDeposit, MOCK_ADDR_1);
        uint256 shares2 = _testDeposit(amountToDeposit, MOCK_ADDR_2);
        uint256 shares3 = _testDeposit(amountToDeposit, MOCK_ADDR_3);

        _increaseTimeToExpiry();
        principalToken.storeRatesAtExpiry();

        uint256 ptRateAtExpiry = principalToken.getPTRate();
        uint256 ibtRateAtExpiry = principalToken.getIBTRate();
        uint256 ptInIBTAtExpiry1 = _convertPTSharesToIBTsWithRates(
            shares1,
            ptRateAtExpiry,
            ibtRateAtExpiry,
            false
        );
        uint256 ptInIBTAtExpiry2 = _convertPTSharesToIBTsWithRates(
            shares2,
            ptRateAtExpiry,
            ibtRateAtExpiry,
            false
        );
        uint256 ptInIBTAtExpiry3 = _convertPTSharesToIBTsWithRates(
            shares3,
            ptRateAtExpiry,
            ibtRateAtExpiry,
            false
        );

        vm.startPrank(MOCK_ADDR_1);
        bytes memory revertData = abi.encodeWithSignature("UnsufficientBalance()");
        vm.expectRevert(revertData);
        principalToken.redeem(shares1 + 1, MOCK_ADDR_1, MOCK_ADDR_1);
        uint256 assets1 = principalToken.redeem(shares1, MOCK_ADDR_1, MOCK_ADDR_1);
        vm.stopPrank();

        assertApproxEqAbs(
            assets1,
            ibt.previewRedeem(ptInIBTAtExpiry1),
            1000,
            "Redeem for user 1 went wrong"
        );

        _increaseRate(-1 * rate2);
        _increaseTimeToExpiry();

        vm.prank(MOCK_ADDR_2);
        uint256 assets2 = principalToken.redeem(shares2, MOCK_ADDR_2, MOCK_ADDR_2);
        assertApproxEqAbs(
            assets2,
            ibt.previewRedeem(ptInIBTAtExpiry2),
            1000,
            "Redeem for user 2 went wrong"
        );
        assertGt(
            assets1,
            assets2,
            "There is supposed to have been negative yield between both redeems"
        );

        _increaseRate(rate3);
        _increaseTimeToExpiry();

        vm.prank(MOCK_ADDR_3);
        uint256 assets3 = principalToken.redeem(shares3, MOCK_ADDR_3, MOCK_ADDR_3);
        assertApproxEqAbs(
            assets3,
            ibt.previewRedeem(ptInIBTAtExpiry3),
            1000,
            "Redeem for user 3 went wrong"
        );
        assertGt(
            assets3,
            assets2,
            "There is supposed to have been positive yield between both redeems"
        );
    }

    function testRedeem13Fuzz(uint256 amountToDeposit, uint16 _rate) public {
        amountToDeposit = bound(amountToDeposit, 0, 1000e18);
        int256 rate = int256(bound(_rate, 0, 199));

        uint256 shares1 = _testDeposit(amountToDeposit, MOCK_ADDR_1);
        uint256 shares2 = _testDeposit(amountToDeposit, MOCK_ADDR_2);

        _increaseRate(100 - rate);

        uint256 shares3 = _testDeposit(amountToDeposit, MOCK_ADDR_3);

        _increaseTimeToExpiry();

        principalToken.storeRatesAtExpiry();
        uint256 ptRateAtExpiry = principalToken.getPTRate();
        uint256 ibtRateAtExpiry = principalToken.getIBTRate();
        uint256 ptInIBTAtExpiry1 = _convertPTSharesToIBTsWithRates(
            shares1,
            ptRateAtExpiry,
            ibtRateAtExpiry,
            false
        );
        uint256 ptInIBTAtExpiry2 = _convertPTSharesToIBTsWithRates(
            shares2,
            ptRateAtExpiry,
            ibtRateAtExpiry,
            false
        );
        uint256 ptInIBTAtExpiry3 = _convertPTSharesToIBTsWithRates(
            shares3,
            ptRateAtExpiry,
            ibtRateAtExpiry,
            false
        );

        vm.startPrank(MOCK_ADDR_1);
        // test that redeem reverts when trying to redeem more than PT balance
        bytes memory revertData = abi.encodeWithSignature("UnsufficientBalance()");
        vm.expectRevert(revertData);
        principalToken.redeem(shares1 + 1, MOCK_ADDR_1, MOCK_ADDR_1);
        uint256 assets1 = principalToken.redeem(shares1, MOCK_ADDR_1, MOCK_ADDR_1);
        vm.stopPrank();

        assertApproxEqAbs(
            assets1,
            ibt.previewRedeem(ptInIBTAtExpiry1),
            1000,
            "Redeem for user 1 went wrong"
        );

        _increaseRate(100 - rate);
        _increaseTimeToExpiry();

        vm.prank(MOCK_ADDR_2);
        uint256 assets2 = principalToken.redeem(shares2, MOCK_ADDR_2, MOCK_ADDR_2);
        assertApproxEqAbs(
            assets2,
            ibt.previewRedeem(ptInIBTAtExpiry2),
            1000,
            "Redeem for user 2 went wrong"
        );

        _increaseRate(300 - rate);
        _increaseTimeToExpiry();

        vm.prank(MOCK_ADDR_3);
        uint256 assets3 = principalToken.redeem(shares3, MOCK_ADDR_3, MOCK_ADDR_3);
        assertApproxEqAbs(
            assets3,
            ibt.previewRedeem(ptInIBTAtExpiry3),
            1000,
            "Redeem for user 3 went wrong"
        );
        if (amountToDeposit > 1000 && rate > 0) {
            if (rate > 100) {
                assertGt(assets1, assets2, "there have been negative yield between both redeems");
            } else if (rate < 100) {
                assertGt(assets2, assets1, "there have been positive yield between both redeems");
            } else {
                assertEq(assets2, assets1, "there have been no yield between both redeems");
            }
            assertGt(assets3, assets2, "there have been positive yield between both redeems");
        }
    }

    function testClaimYieldWhenYieldZeroFuzz(uint256 amountToDeposit) public {
        amountToDeposit = bound(amountToDeposit, 1e18, 1000e18);
        uint256 expectedIBT = ibt.convertToShares(amountToDeposit);
        uint256 expected = ibt.convertToAssets(expectedIBT);
        uint256 actual = _testDeposit(amountToDeposit, address(this));
        assertEq(expected, actual, "After deposit balance is not equal to expected value");

        uint256 underlyingBalanceBefore = underlying.balanceOf(address(this));
        principalToken.claimYield(address(this));
        uint256 underlyingBalanceAfter = underlying.balanceOf(address(this));
        assertEq(
            underlyingBalanceBefore,
            underlyingBalanceAfter,
            "Wrong underlying balance when no yield to transfer"
        );
    }

    function testClaimYieldWhenYieldNegativeFuzz(uint256 amountToDeposit, uint16 _rate) public {
        amountToDeposit = bound(amountToDeposit, 1e18, 1000e18);
        int256 rate = int256(bound(_rate, 1, 99));
        uint256 expectedIBT = ibt.convertToShares(amountToDeposit);
        uint256 expected = ibt.convertToAssets(expectedIBT);
        uint256 actual = _testDeposit(amountToDeposit, address(this));
        assertEq(expected, actual, "After deposit balance is not equal to expected value"); // checks if balances are accurate after deposit

        _increaseRate(-1 * rate);

        uint256 underlyingBalanceBefore = underlying.balanceOf(address(this));
        principalToken.claimYield(address(this));
        uint256 underlyingBalanceAfter = underlying.balanceOf(address(this));
        assertEq(
            underlyingBalanceBefore,
            underlyingBalanceAfter,
            "Wrong underlying balance when no yield to transfer"
        );
    }

    function testClaimYield100NYFuzz(uint256 amountToDeposit, uint16 _rate1) public {
        amountToDeposit = bound(amountToDeposit, 1e18, 100e18);
        int256 rate1 = int256(bound(_rate1, 1, 100));
        _testDeposit(amountToDeposit, address(this));

        _increaseRate(rate1);

        principalToken.claimYield(address(this));

        _increaseRate(-100);

        vm.expectRevert();
        principalToken.claimYield(address(this));
    }

    function testMaxRedeemFuzz(uint256 amountToDeposit) public {
        amountToDeposit = bound(amountToDeposit, 1e18, 1000e18);
        uint256 expected1 = _testDeposit(amountToDeposit, address(this));
        uint256 actual = principalToken.maxRedeem(address(this));
        assertEq(expected1, actual, "Max redeem balance is not equal to expected value");
        _increaseTimeToExpiry();
        assertEq(expected1, actual, "Max redeem balance is not equal to expected value");
    }

    function testWithdrawFailFuzz(uint256 amountToDeposit) public {
        amountToDeposit = bound(amountToDeposit, 1e18, 100e18);

        _testDeposit(amountToDeposit, address(this));

        bytes memory revertData = abi.encodeWithSignature("UnauthorizedCaller()");
        vm.expectRevert(revertData);
        vm.prank(MOCK_ADDR_1);
        principalToken.withdraw(amountToDeposit, MOCK_ADDR_1, address(this));

        revertData = abi.encodeWithSignature("UnsufficientBalance()");
        vm.expectRevert(revertData);
        principalToken.withdraw(amountToDeposit * 10, MOCK_ADDR_1, address(this));
    }

    function testClaimFees2Fuzz(uint256 amount, uint16 _rate) public {
        uint256 assetsToDeposit = bound(amount, 0, 100e18);
        int256 rate = int256(bound(_rate, 0, 1000));

        _testDeposit(assetsToDeposit, address(this));

        _increaseRate(rate);

        (, ibtRate) = _getPTAndIBTRates();
        uint256 netUserYieldInUnderlying = ibt.previewRedeem(
            principalToken.getCurrentYieldOfUserInIBT(address(this))
        );
        uint256 underlyingBalanceBefore = underlying.balanceOf(address(this));

        principalToken.claimYield(address(this));
        assertApproxEqAbs(
            underlyingBalanceBefore + netUserYieldInUnderlying,
            underlying.balanceOf(address(this)),
            1000,
            "After withdraw balance is not equal to expected value"
        );
        vm.prank(feeCollector);
        uint256 actualFees = principalToken.claimFees();
        uint256 feeCollectorBalance = underlying.balanceOf(feeCollector);
        assertEq(actualFees, feeCollectorBalance);
    }

    function testPreviewWithdrawWithNoYieldFuzz(uint256 amount) public {
        amount = bound(amount, 0, 100_000e18);
        vm.prank(testUser);
        underlying.approve(address(principalToken), amount);
        if (principalToken.previewDeposit(amount) == 0) {
            vm.expectRevert();
        }
        principalToken.deposit(amount, testUser);
        assertEq(
            principalToken.previewWithdraw(amount),
            amount, // since no yield is generated
            "Withdraw preview is not equal to expected value"
        );
    }

    /**
     * @dev create a situation where user has some yield since last deposit.
     * Then previewWithdraw is different than before the yield was generated (smaller).
     */
    function testPreviewWithdrawFuzz(uint256 amount, uint16 _rate) public {
        amount = bound(amount, 0, 10000e18);
        int256 rate = int256(bound(_rate, 0, 199));

        _testDeposit(amount, MOCK_ADDR_1);
        uint256 expectedShares = _convertToSharesWithRate(
            amount,
            ptRate,
            false,
            false,
            Math.Rounding.Ceil
        );

        // no rate changes for now so should not take into account no yield
        vm.prank(MOCK_ADDR_1);
        uint256 previewShares1 = principalToken.previewWithdraw(amount);
        assertApproxEqAbs(previewShares1, expectedShares, 1000, "Preview withdraw is wrong");

        // generate some yield context
        _increaseRate(100 - rate);
        // deposits with another user to update PT and IBT rates
        _testDeposit(amount, MOCK_ADDR_2);
        _increaseRate(100 - rate);
        // deposits with another user to update PT and IBT rates
        _testDeposit(amount, MOCK_ADDR_2);
        _increaseRate(175 - rate);

        // there have been some rate change so some yield should be taken into account
        vm.prank(MOCK_ADDR_1);
        uint256 previewShares2 = principalToken.previewWithdraw(amount);
        (ptRate, ) = _getPTAndIBTRates();
        uint256 userYieldInIBT = principalToken.getCurrentYieldOfUserInIBT(MOCK_ADDR_1);
        uint256 expectedShares2 = _convertToSharesWithRate(
            amount,
            ptRate,
            false,
            false,
            Math.Rounding.Ceil
        );
        assertApproxEqAbs(
            previewShares2,
            expectedShares2,
            1000,
            "Preview withdraw amount after yield has been generated is not equal to expected value"
        );

        if (rate > 175) {
            // only negative yield scenario
            assertEq(userYieldInIBT, 0, "Only negative yield should imply no user yield");
        }

        _increaseRate(100 - rate);
        // deposits with another user to update PT and IBT rates
        _testDeposit(amount, MOCK_ADDR_2);
        _increaseRate(100 - rate);
        // deposits with another user to update PT and IBT rates
        _testDeposit(amount, MOCK_ADDR_2);
        _increaseRate(175 - rate);

        vm.prank(MOCK_ADDR_1);
        previewShares1 = principalToken.previewWithdraw(amount);
        // maxWithdraw before or after expiry should be the same
        uint256 maxWithdraw1 = principalToken.maxWithdraw(MOCK_ADDR_1);
        // increase time to after principalToken's expiry
        _increaseTimeToExpiry();

        uint256 maxWithdraw2 = principalToken.maxWithdraw(MOCK_ADDR_1);

        assertEq(maxWithdraw2, maxWithdraw1, "maxWithdraw is wrong");
    }

    function testMaxWithdrawFuzz(uint256 amount) public {
        amount = bound(amount, 0, 100_000_000e18);
        _testDeposit(amount, MOCK_ADDR_1);

        assertEq(
            principalToken.maxWithdraw(MOCK_ADDR_1),
            _amountMinusFee(amount, registry.getTokenizationFee()),
            "Max withdraw amount is not equal to expected value"
        );

        _increaseTimeToExpiry();

        assertEq(
            principalToken.maxWithdraw(MOCK_ADDR_1),
            _amountMinusFee(amount, registry.getTokenizationFee()),
            "Max withdraw amount is not equal to expected value"
        );
    }

    function testStoreAndGetRatesAfterExpiryFuzz(uint16 _rate) public {
        int256 rate = int256(bound(_rate, 0, 199));
        _increaseRate(100 - rate);

        bytes memory revertData = abi.encodeWithSignature("PTNotExpired()");
        vm.expectRevert(revertData);
        principalToken.storeRatesAtExpiry();

        _increaseTimeToExpiry();
        principalToken.storeRatesAtExpiry();
        uint256 ibtRateAtExpiry = principalToken.getIBTRate();
        uint256 ptRateAtExpiry = principalToken.getPTRate();
        assertEq(
            ibtRateAtExpiry,
            principalToken.getIBTRate(),
            "Getter for IBT rate at expiry is wrong"
        );
        assertEq(
            ptRateAtExpiry,
            principalToken.getPTRate(),
            "Getter for PT rate at expiry is wrong"
        );

        _increaseRate(100 - rate);

        revertData = abi.encodeWithSignature("RatesAtExpiryAlreadyStored()");
        vm.expectRevert(revertData);
        principalToken.storeRatesAtExpiry();

        uint256 actualIbtRate = ibt.previewRedeem(IBT_UNIT); // should be impacted by rate change
        uint256 actualPTRate = principalToken.convertToUnderlying(IBT_UNIT); // should be impacted by rate change
        assertEq(ibtRateAtExpiry, principalToken.getIBTRate(), "Stored IBT rate should not change");
        assertEq(ptRateAtExpiry, principalToken.getPTRate(), "Stored PT rate should not change");
        if (rate == 100) {
            assertEq(
                actualIbtRate,
                ibtRateAtExpiry.fromRay(18),
                "IBT rates at and after expiry should be equal"
            );
            assertEq(
                actualPTRate,
                ptRateAtExpiry.fromRay(18),
                "PT rates at and after expiry should be equal"
            );
        } else {
            assertNotEq(
                actualIbtRate,
                ibtRateAtExpiry.fromRay(18),
                "IBT rates at and after expiry shouldn't be equal"
            );
            assertNotEq(
                actualPTRate,
                ptRateAtExpiry.fromRay(18),
                "PT actual conversion to underlying at and after expiry shouldn't be equal"
            );
        }

        _increaseTimeToExpiry();
        _increaseRate(-100);

        actualIbtRate = ibt.previewRedeem(IBT_UNIT); // should be impacted by rate change
        actualPTRate = principalToken.convertToUnderlying(IBT_UNIT); // should be impacted by rate change
        assertEq(ibtRateAtExpiry, principalToken.getIBTRate(), "Stored IBT rate should not change");
        assertEq(ptRateAtExpiry, principalToken.getPTRate(), "Stored PT rate should not change");
        assertNotEq(
            actualIbtRate,
            ibtRateAtExpiry.fromRay(18),
            "IBT rates at and after expiry shouldn't be equal"
        );
        assertNotEq(
            actualPTRate,
            ptRateAtExpiry.fromRay(18),
            "PT actual conversion to underlying at and after expiry shouldn't be equal"
        );
    }

    /**
     * @dev Internal function for deposit and balance checks for ibt, underlying, pt and yt
     */
    function _testDeposit(uint256 amount, address receiver) internal returns (uint256 shares) {
        DepositWithdrawRedeemData memory data;
        underlying.approve(address(principalToken), amount);
        data.expectedIBT = ibt.convertToShares(amount);
        data.totalAssetsBefore = principalToken.totalAssets();
        data.underlyingBalanceBefore = underlying.balanceOf(address(this));
        data.ibtBalPTContractBefore = ibt.balanceOf(address(principalToken));
        data.ptBalanceBefore = principalToken.balanceOf(receiver);
        data.ytBalanceBefore = yt.actualBalanceOf(receiver);
        data.preview = principalToken.previewDeposit(amount);
        if (data.preview == 0) {
            vm.expectRevert();
        } else {
            (uint256 _ptRate, uint256 _ibtRate) = _getPTAndIBTRates();
            assertApproxEqAbs(
                data.preview,
                _convertIBTsToPTSharesWithRates(
                    _amountMinusFee(ibt.previewDeposit(amount), registry.getTokenizationFee()),
                    _ptRate,
                    _ibtRate,
                    false
                ),
                1000,
                "Value of previewDeposit is not equal to expected value"
            );
        }
        shares = principalToken.deposit(amount, receiver);
        data.totalAssetsAfter = principalToken.totalAssets();
        data.underlyingBalanceAfter = underlying.balanceOf(address(this));
        data.ibtBalPTContractAfter = ibt.balanceOf(address(principalToken));
        data.ptBalanceAfter = principalToken.balanceOf(receiver);
        data.ytBalanceAfter = yt.actualBalanceOf(receiver);

        assertApproxEqAbs(
            data.preview,
            shares,
            1000,
            "Deposit returned shares are not as expected by previewDeposit"
        );
        if (data.preview != 0) {
            assertApproxEqAbs(
                data.totalAssetsAfter,
                data.totalAssetsBefore + amount,
                1000,
                "After deposit totalAssets is not equal to expected value 1"
            );
            assertApproxEqAbs(
                data.underlyingBalanceBefore,
                data.underlyingBalanceAfter + amount,
                1000,
                "After deposit balance is not equal to expected value 2"
            );
            assertApproxEqAbs(
                data.ibtBalPTContractAfter,
                data.ibtBalPTContractBefore + data.expectedIBT,
                1000,
                "After deposit balance is not equal to expected value 3"
            );
            assertApproxEqAbs(
                data.ptBalanceAfter,
                data.ptBalanceBefore + shares,
                1000,
                "After deposit balance is not equal to expected value 4"
            );
            assertApproxEqAbs(
                data.ytBalanceAfter,
                data.ytBalanceBefore + shares,
                1000,
                "After deposit balance is not equal to expected value 5"
            );
        } else {
            assertEq(
                data.totalAssetsAfter,
                data.totalAssetsBefore,
                "After deposit totalAssets is not equal to expected value 1"
            );
            assertEq(
                data.underlyingBalanceBefore,
                data.underlyingBalanceAfter,
                "After deposit balance is not equal to expected value 2"
            );
            assertEq(
                data.ibtBalPTContractAfter,
                data.ibtBalPTContractBefore,
                "After deposit balance is not equal to expected value 3"
            );
            assertEq(
                data.ptBalanceAfter,
                data.ptBalanceBefore,
                "After deposit balance is not equal to expected value 4"
            );
            assertEq(
                data.ytBalanceAfter,
                data.ytBalanceBefore,
                "After deposit balance is not equal to expected value 5"
            );
        }
    }

    function _testDepositIBT(uint256 amount, address user) internal returns (uint256 shares) {
        DepositWithdrawRedeemData memory data;
        data.ibtBalPTContractBefore = ibt.balanceOf(address(principalToken));
        data.ibtBalanceBefore = ibt.balanceOf(user);
        data.ptBalanceBefore = principalToken.balanceOf(user);
        data.ytBalanceBefore = yt.actualBalanceOf(user);
        vm.startPrank(user);
        ibt.approve(address(principalToken), amount);
        data.preview = principalToken.previewDepositIBT(amount);
        if (data.preview == 0) {
            vm.expectRevert();
        } else {
            (uint256 _ptRate, uint256 _ibtRate) = _getPTAndIBTRates();
            assertApproxEqAbs(
                data.preview,
                _convertIBTsToPTSharesWithRates(
                    _amountMinusFee(amount, registry.getTokenizationFee()),
                    _ptRate,
                    _ibtRate,
                    false
                ),
                1000,
                "Value of previewDeposit is not equal to expected value"
            );
        }
        shares = principalToken.depositIBT(amount, user);
        data.ibtBalPTContractAfter = ibt.balanceOf(address(principalToken));
        data.ibtBalanceAfter = ibt.balanceOf(user);
        data.ptBalanceAfter = principalToken.balanceOf(user);
        data.ytBalanceAfter = yt.actualBalanceOf(user);
        assertApproxEqAbs(
            data.preview,
            shares,
            1000,
            "Deposit returned shares are not as expected by previewDeposit"
        );
        assertApproxEqAbs(
            data.ibtBalanceBefore,
            data.ibtBalanceAfter + amount,
            1000,
            "After deposit balance is not equal to expected value 1"
        );
        assertApproxEqAbs(
            data.ibtBalPTContractAfter,
            data.ibtBalPTContractBefore + amount,
            1000,
            "After deposit balance is not equal to expected value 2"
        );
        assertApproxEqAbs(
            data.ptBalanceAfter,
            data.ptBalanceBefore + shares,
            1000,
            "After deposit balance is not equal to expected value 3"
        );
        assertApproxEqAbs(
            data.ytBalanceAfter,
            data.ytBalanceBefore + shares,
            1000,
            "After deposit balance is not equal to expected value 4"
        );
        vm.stopPrank();
    }

    function _prepareForDepositIBT(address user, uint256 ibtAmount) internal {
        uint256 underlyingAmount = ibt.convertToAssets(ibtAmount);
        if (ibt.convertToShares(underlyingAmount) != ibtAmount) {
            // e.g. rate decrease and underlying amount was rounded down
            underlyingAmount += 1; // hence round it up instead
            ibtAmount = ibt.convertToShares(underlyingAmount); // and recomputes the actual ibtAmount minted to the user
        }
        uint256 ibtBalanceOfUserBefore = ibt.balanceOf(user);
        underlying.mint(user, underlyingAmount);
        vm.startPrank(user);
        underlying.approve(address(ibt), underlyingAmount);
        ibt.deposit(underlyingAmount, user);
        assertApproxEqAbs(
            ibt.balanceOf(user),
            ibtBalanceOfUserBefore + ibtAmount,
            1000,
            "ibt amount minted to user is not correct"
        );
        vm.stopPrank();
    }

    /**
     * @dev Internal function for withdraw and balance checks for ibt, underlying, pt and yt
     */
    function _testWithdraw(uint256 amount, address receiver, address owner) internal {
        DepositWithdrawRedeemData memory data;
        data.totalAssetsBefore = principalToken.totalAssets();
        data.underlyingBalanceBefore = underlying.balanceOf(receiver);
        data.ibtBalPTContractBefore = ibt.balanceOf(address(principalToken));
        data.ptBalanceBefore = principalToken.balanceOf(owner);
        data.ytBalanceBefore = yt.actualBalanceOf(owner);
        data.expectedIBT = ibt.convertToShares(amount);
        vm.prank(owner);
        uint256 shares = principalToken.withdraw(amount, receiver, owner);
        data.totalAssetsAfter = principalToken.totalAssets();
        data.underlyingBalanceAfter = underlying.balanceOf(receiver);
        data.ibtBalPTContractAfter = ibt.balanceOf(address(principalToken));
        data.ptBalanceAfter = principalToken.balanceOf(owner);
        data.ytBalanceAfter = yt.actualBalanceOf(owner);
        // assertions
        assertApproxEqAbs(
            data.totalAssetsBefore,
            data.totalAssetsAfter + amount,
            1000,
            "After withdraw, totalAssets is wrong"
        );
        assertApproxEqAbs(
            data.underlyingBalanceAfter,
            data.underlyingBalanceBefore + amount,
            1000,
            "After withdraw, underlying balance of receiver is wrong"
        );
        assertLe(data.underlyingBalanceAfter, data.underlyingBalanceBefore + amount);

        assertApproxEqAbs(
            data.ibtBalPTContractBefore,
            data.ibtBalPTContractAfter + data.expectedIBT,
            1000,
            "After withdraw, IBT balance of PT contract is wrong"
        );
        assertGe(
            data.ibtBalPTContractBefore,
            data.ibtBalPTContractAfter + data.expectedIBT,
            "Too much IBTs have been burned"
        );

        assertApproxEqAbs(
            data.ptBalanceBefore,
            data.ptBalanceAfter + shares,
            1000,
            "After withdraw, PT balance is wrong"
        );
        assertGe(
            data.ptBalanceBefore,
            data.ptBalanceAfter + shares,
            "not all shares have been burned"
        );
        assertApproxEqAbs(
            data.ytBalanceBefore,
            data.ytBalanceAfter + shares,
            1000,
            "After withdraw, YT balance is wrong"
        );
        assertGe(
            data.ytBalanceBefore,
            data.ytBalanceAfter + shares,
            "not all shares have been burned"
        );
    }

    /**
     * @dev Internal function for max redeem + claimYield
     * @param receiver address of the assets receiver
     * @param owner address of the user redeeming shares
     */
    function _testRedeemMaxAndClaimYield(address receiver, address owner) internal {
        DepositWithdrawRedeemData memory data;

        data.totalAssetsBefore = principalToken.totalAssets();

        data.underlyingBalanceBefore = underlying.balanceOf(receiver);
        data.ptBalanceBefore = principalToken.balanceOf(owner);
        data.ytBalanceBefore = yt.actualBalanceOf(owner);
        data.ibtBalPTContractBefore = ibt.balanceOf(address(principalToken));

        uint256 previewYieldIBT = principalToken.getCurrentYieldOfUserInIBT(owner);
        data.maxRedeem = principalToken.maxRedeem(owner);
        uint256 expectedAssets = principalToken.previewRedeem(data.maxRedeem) +
            IERC4626(ibt).previewRedeem(previewYieldIBT);
        uint256 expectedAssetsInIBT = principalToken.previewRedeemForIBT(data.maxRedeem) +
            previewYieldIBT;

        if (expectedAssets > 0) {
            vm.startPrank(owner);
            uint256 assets = principalToken.redeem(data.maxRedeem, receiver, owner);
            assets += principalToken.claimYield(receiver);
            vm.stopPrank();

            data.totalAssetsAfter = principalToken.totalAssets();
            data.underlyingBalanceAfter = underlying.balanceOf(receiver);
            data.ptBalanceAfter = principalToken.balanceOf(owner);
            data.ytBalanceAfter = yt.actualBalanceOf(owner);
            data.ibtBalPTContractAfter = ibt.balanceOf(address(principalToken));

            assertApproxEqAbs(
                assets,
                expectedAssets,
                100,
                "After max redeem + claimYield, balance is not equal to expected value"
            );

            assertGe(
                assets,
                expectedAssets,
                "After max redeem + claimYield, the user received more assets than expected"
            );

            assertApproxEqAbs(
                data.totalAssetsBefore,
                data.totalAssetsAfter + expectedAssets,
                100,
                "After max redeem + claimYield, totalAssets is wrong"
            );

            assertEq(
                data.underlyingBalanceBefore + assets,
                data.underlyingBalanceAfter,
                "After max redeem + claimYield, underlying balance of receiver is wrong"
            );
            assertEq(
                data.ptBalanceBefore,
                data.ptBalanceAfter + data.maxRedeem,
                "After max redeem, PT balance of owner is wrong"
            );

            if (block.timestamp < principalToken.maturity()) {
                assertEq(data.ytBalanceAfter, 0, "After max redeem, YT balance of owner is wrong");
            } else {
                assertEq(
                    data.ytBalanceBefore,
                    data.ytBalanceAfter,
                    "After max redeem, YT balance of owner is wrong"
                );
            }

            assertApproxEqAbs(
                data.ibtBalPTContractBefore,
                data.ibtBalPTContractAfter + expectedAssetsInIBT,
                1000,
                "After max redeem + claimYield, IBT balance of PT contract is wrong"
            );
            assertGe(
                data.ibtBalPTContractBefore,
                data.ibtBalPTContractAfter + expectedAssetsInIBT,
                "More IBTs than expected have been burned"
            );
        }
    }

    function _testRedeem(uint256 shares, address user) internal {
        DepositWithdrawRedeemData memory data;

        data.totalAssetsBefore = principalToken.totalAssets();
        data.underlyingBalanceBefore = underlying.balanceOf(user);
        data.ptBalanceBefore = principalToken.balanceOf(user);
        data.ytBalanceBefore = yt.actualBalanceOf(user);
        data.ibtBalPTContractBefore = ibt.balanceOf(address(principalToken));

        uint256 expectedAssets = principalToken.previewRedeem(shares);
        uint256 expectedAssetsInIBT = ibt.convertToShares(expectedAssets);

        if (expectedAssets > 0) {
            vm.startPrank(user);
            uint256 assets = principalToken.redeem(shares, user, user);
            vm.stopPrank();

            data.totalAssetsAfter = principalToken.totalAssets();
            data.underlyingBalanceAfter = underlying.balanceOf(user);
            data.ptBalanceAfter = principalToken.balanceOf(user);
            data.ytBalanceAfter = yt.actualBalanceOf(user);
            data.ibtBalPTContractAfter = ibt.balanceOf(address(principalToken));

            assertApproxEqAbs(
                assets,
                expectedAssets,
                100,
                "After redeem, balance is not equal to expected value"
            );

            assertGe(
                assets,
                expectedAssets,
                "After redeem, the user received more assets than expected"
            );

            assertApproxEqAbs(
                data.totalAssetsBefore,
                data.totalAssetsAfter + expectedAssets,
                100,
                "After redeem, totalAssets is wrong"
            );

            assertEq(
                data.underlyingBalanceBefore + assets,
                data.underlyingBalanceAfter,
                "After redeem, underlying balance of user is wrong"
            );
            assertEq(
                data.ptBalanceBefore,
                data.ptBalanceAfter + shares,
                "After redeem, PT balance of owner is wrong"
            );

            if (block.timestamp < principalToken.maturity()) {
                assertEq(
                    data.ytBalanceBefore,
                    data.ytBalanceAfter + shares,
                    "After redeem, YT balance of owner is wrong"
                );
            } else {
                assertEq(
                    data.ytBalanceAfter,
                    data.ytBalanceBefore,
                    "After redeem, YT balance of owner is wrong"
                );
            }

            assertApproxEqAbs(
                data.ibtBalPTContractBefore,
                data.ibtBalPTContractAfter + expectedAssetsInIBT,
                1000,
                "After redeem, IBT balance of PT contract is wrong"
            );
            assertGe(
                data.ibtBalPTContractBefore,
                data.ibtBalPTContractAfter + expectedAssetsInIBT,
                "More IBTs than expected have been burned"
            );
        }
    }

    function _transferPT(address from, address to, uint256 amount) internal {
        uint256 senderPTBalanceBefore = principalToken.balanceOf(from);
        uint256 receiverPTBalanceBefore = principalToken.balanceOf(to);
        require(
            amount <= senderPTBalanceBefore,
            "Transfer amount exceeds the pt balance of sender"
        );
        vm.prank(from);
        principalToken.transfer(to, amount);
        uint256 senderPTBalanceAfter = principalToken.balanceOf(from);
        uint256 receiverPTBalanceAfter = principalToken.balanceOf(to);
        assertApproxEqAbs(
            senderPTBalanceBefore,
            senderPTBalanceAfter + amount,
            1000,
            "Balance after transfer does not match the expected value"
        );
        assertApproxEqAbs(
            receiverPTBalanceAfter,
            receiverPTBalanceBefore + amount,
            1000,
            "Balance after transfer does not match the expected value"
        );
    }

    function _transferYT(address from, address to, uint256 amount) internal {
        uint256 senderYTBalanceBefore = yt.actualBalanceOf(from);
        uint256 receiverYTBalanceBefore = yt.actualBalanceOf(to);
        require(
            amount <= senderYTBalanceBefore,
            "Transfer amount exceeds the yt balance of sender"
        );
        vm.prank(from);
        yt.transfer(to, amount);
        uint256 senderYTBalanceAfter = yt.actualBalanceOf(from);
        uint256 receiverYTBalanceAfter = yt.actualBalanceOf(to);
        assertApproxEqAbs(
            senderYTBalanceBefore,
            senderYTBalanceAfter + amount,
            1000,
            "Balance after transfer does not match the expected value"
        );
        assertApproxEqAbs(
            receiverYTBalanceAfter,
            receiverYTBalanceBefore + amount,
            1000,
            "Balance after transfer does not match the expected value"
        );
    }

    function _claimYield(address user) internal {
        uint256 ibtBalPTContractBefore = ibt.balanceOf(address(principalToken));
        uint256 assetBalanceBefore = underlying.balanceOf(user);
        uint256 unclaimedFeesBefore = principalToken.getUnclaimedFeesInIBT();
        uint256 userYield = principalToken.getCurrentYieldOfUserInIBT(user);
        vm.prank(user);
        uint256 assets = principalToken.claimYield(user);
        uint256 ibtBalPTContractAfter = ibt.balanceOf(address(principalToken));
        uint256 assetBalanceAfter = underlying.balanceOf(user);
        uint256 unclaimedFeesAfter = principalToken.getUnclaimedFeesInIBT();

        assertApproxEqAbs(
            unclaimedFeesAfter,
            unclaimedFeesBefore + userYield.mulDiv(YIELD_FEE, MAX_FEE),
            10000,
            "After claim balance is not equal to expected value 1"
        );

        assertEq(
            ibtBalPTContractBefore,
            ibtBalPTContractAfter + userYield,
            "After claimYield, IBT balance of PT contract is wrong"
        );

        assertApproxEqAbs(
            assetBalanceAfter,
            assetBalanceBefore + assets,
            10000,
            "After claimYield, asset balance of user is wrong"
        );
    }

    function _testYieldUpdate(
        address user,
        UserRate memory data,
        uint256 newPtRate, // in Ray
        uint256 newIbtrate, // in Ray
        uint256 actualYieldInIBT
    ) internal returns (UserRate memory updatedData) {
        uint256 userYTBalanceInRay = yt.actualBalanceOf(user).toRay(18);
        uint256 yieldInUnderlyingRay;
        uint256 underlyingOfYTRay = _convertToAssetsWithRate(
            userYTBalanceInRay,
            data.oldPTRate,
            true,
            true,
            Math.Rounding.Floor
        );
        if (data.oldIBTRate == 0) {
            vm.expectRevert();
        }
        uint256 ibtOfYTInRay = _convertToSharesWithRate(
            underlyingOfYTRay,
            data.oldIBTRate,
            true,
            true,
            Math.Rounding.Floor
        );
        if (newPtRate == data.oldPTRate && newIbtrate == data.oldIBTRate) {
            return data;
        } else if (newPtRate == data.oldPTRate && newIbtrate > data.oldIBTRate) {
            yieldInUnderlyingRay = _convertToAssetsWithRate(
                ibtOfYTInRay,
                (newIbtrate - data.oldIBTRate),
                true,
                true,
                Math.Rounding.Floor
            );
        } else {
            if (data.oldPTRate > newPtRate) {
                if (newIbtrate > data.oldIBTRate) {
                    yieldInUnderlyingRay =
                        _convertToAssetsWithRate(
                            userYTBalanceInRay,
                            (data.oldPTRate - newPtRate),
                            true,
                            true,
                            Math.Rounding.Floor
                        ) +
                        _convertToAssetsWithRate(
                            ibtOfYTInRay,
                            (newIbtrate - data.oldIBTRate),
                            true,
                            true,
                            Math.Rounding.Floor
                        );
                } else {
                    uint256 actualNegativeYieldInUnderlyingRay = _convertToAssetsWithRate(
                        userYTBalanceInRay,
                        (data.oldPTRate - newPtRate),
                        true,
                        true,
                        Math.Rounding.Floor
                    );
                    uint256 expectedNegativeYieldInUnderlyingRay = _convertToAssetsWithRate(
                        ibtOfYTInRay,
                        (data.oldIBTRate - newIbtrate),
                        true,
                        true,
                        Math.Rounding.Floor
                    );
                    yieldInUnderlyingRay = expectedNegativeYieldInUnderlyingRay >
                        actualNegativeYieldInUnderlyingRay
                        ? 0
                        : actualNegativeYieldInUnderlyingRay - expectedNegativeYieldInUnderlyingRay;
                    yieldInUnderlyingRay = yieldInUnderlyingRay < 100 ? 0 : yieldInUnderlyingRay;
                }
            } else {
                return data;
            }
        }
        uint256 yieldInIBT = _convertToSharesWithRate(
            yieldInUnderlyingRay,
            newIbtrate,
            true,
            false,
            Math.Rounding.Floor
        );
        assertApproxEqAbs(
            actualYieldInIBT,
            data.oldYieldOfUserInIBT + yieldInIBT,
            1000,
            "The yield value is not equal to expected value"
        );
        data.oldPTRate = newPtRate;
        data.oldIBTRate = newIbtrate;
        data.oldYieldOfUserInIBT = actualYieldInIBT;
        return data;
    }

    /**
     * @dev Internal function for changing ibt rate with a determined rate as passed
     */
    function _increaseRate(int256 rate) internal {
        int256 currentRate = int256(ibt.convertToAssets(10 ** ibt.decimals()));
        int256 newRate = (currentRate * (rate + 100)) / 100;
        ibt.setPricePerFullShare(uint256(newRate));
    }

    function _increaseTimeToExpiry() internal {
        uint256 time = block.timestamp + principalToken.maturity();
        vm.warp(time);
    }

    function _convertToSharesWithRate(
        uint256 assets,
        uint256 rate,
        bool fromRay,
        bool toRay,
        Math.Rounding rounding
    ) internal view returns (uint256 shares) {
        shares = PrincipalTokenUtil._convertToSharesWithRate(
            fromRay ? assets : assets.toRay(18),
            rate,
            toRay ? IBT_UNIT.toRay(18) : IBT_UNIT,
            rounding
        );
    }

    function _convertToAssetsWithRate(
        uint256 shares,
        uint256 rate,
        bool fromRay,
        bool toRay,
        Math.Rounding rounding
    ) internal view returns (uint256 assets) {
        assets = PrincipalTokenUtil._convertToAssetsWithRate(
            shares,
            rate,
            fromRay ? IBT_UNIT.toRay(18) : IBT_UNIT,
            rounding
        );
        if (!toRay) {
            assets = assets.fromRay(18);
        }
    }

    /**
     * @dev Converts amount of PT shares to amount of IBT with provided rates
     * @param shares amount of shares to convert to IBTs
     * @param _ptRate PT rate
     * @param _ibtRate IBT rate
     * @param roundUp true if result should be rounded up
     * @return ibts resulting amount of IBT
     */
    function _convertPTSharesToIBTsWithRates(
        uint256 shares,
        uint256 _ptRate,
        uint256 _ibtRate,
        bool roundUp
    ) internal pure returns (uint256 ibts) {
        if (_ibtRate == 0) {
            revert();
        }
        ibts = shares.mulDiv(_ptRate, _ibtRate, roundUp ? Math.Rounding.Ceil : Math.Rounding.Floor);
    }

    /**
     * @dev Converts amount of IBT to amount of PT shares with provided rates
     * @param ibts amount of IBT to convert to shares
     * @param _ptRate PT rate
     * @param _ibtRate IBT rate
     * @param roundUp true if result should be rounded up
     * @return shares resulting amount of shares
     */
    function _convertIBTsToPTSharesWithRates(
        uint256 ibts,
        uint256 _ptRate,
        uint256 _ibtRate,
        bool roundUp
    ) internal pure returns (uint256 shares) {
        if (_ptRate == 0) {
            revert();
        }
        shares = ibts.mulDiv(_ibtRate, _ptRate, roundUp ? Math.Rounding.Ceil : Math.Rounding.Floor);
    }

    function _getPTAndIBTRates() internal view returns (uint256, uint256) {
        return (principalToken.getPTRate(), principalToken.getIBTRate());
    }

    function _toRay(uint256 amount, uint256 decimals) internal pure returns (uint256) {
        return RayMath.toRay(amount, decimals);
    }

    function _fromRay(uint256 amount, uint256 decimals) internal pure returns (uint256) {
        return RayMath.fromRay(amount, decimals);
    }

    function _getFee(uint256 amount, uint256 feeRate) internal pure returns (uint256) {
        return amount.mulDiv(feeRate, 1e18);
    }

    function _amountMinusFee(uint256 amount, uint256 feeRate) internal pure returns (uint256) {
        return amount - _getFee(amount, feeRate);
    }
}
