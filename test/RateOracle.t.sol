// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.20;

import "forge-std/Test.sol";

import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockIBT.sol";
import "../src/oracle/RateOracle.sol";
import "../script/00_deployAccessManager.s.sol";
import "../script/01_deployRegistry.s.sol";
import "../script/02_deployPrincipalTokenInstance.s.sol";
import "../script/03_deployYTInstance.s.sol";
import "../script/04_deployPrincipalTokenBeacon.s.sol";
import "../script/05_deployYTBeacon.s.sol";
import "../script/06_deployFactory.s.sol";
import "../script/07_deployPrincipalToken.s.sol";
import "../src/libraries/Roles.sol";
import "openzeppelin-contracts/proxy/beacon/UpgradeableBeacon.sol";

contract ContractRateOracle is Test {
    PrincipalToken public principalToken;
    Factory public factory;
    AccessManager public accessManager;
    MockERC20 public underlying;
    MockIBT public ibt;
    UpgradeableBeacon public principalTokenBeacon;
    UpgradeableBeacon public ytBeacon;
    RateOracle public rateOracle;
    YieldToken public yt;
    Registry public registry;
    address feeCollector = 0x0000000000000000000000000000000000000FEE;
    address MOCK_ADDR_1 = 0x0000000000000000000000000000000000000001;
    uint256 public TOKENIZATION_FEE = 1e15;
    uint256 public YIELD_FEE = 0;
    uint256 public PT_FLASH_LOAN_FEE = 0;
    uint256 EXPIRY = block.timestamp + 1 days * 365;
    uint256 public IBT_UNIT;
    address public admin;
    address public scriptAdmin;

    uint256 public day1 = 1 days;
    uint256 public day2 = 2 * day1 + 10 * 1 hours;
    uint256 public stillday2 = day2 + 13 * 1 hours + 59 * 1 minutes + 59 * 1 seconds;
    uint256 public day3 = stillday2 + 1 days;
    uint256 public day4 = day3 + 1 seconds;
    uint256 public day5 = day4 + 1 days + 23 hours + 59 minutes + 59 seconds;
    // Events
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
        yt = YieldToken(principalToken.getYT());
        rateOracle = new RateOracle();
    }

    function _increaseRate(int128 percentage) internal {
        int128 currentRate = int128(uint128(ibt.convertToAssets(10 ** ibt.decimals())));
        int128 newRate = (currentRate * (percentage + 100)) / 100;
        ibt.setPricePerFullShare(uint256(uint128(newRate)));
    }

    function testRateOracle() public {
        // here timestamp 0 represents 1st Jan. 1970 00:00 UTC GMT
        // rate should be 1:1 initially
        address ibtContractAddress = address(IERC4626(principalToken.getIBT()));
        uint256 rate = rateOracle.pokeRate(ibtContractAddress);

        assert(rateOracle.getRateOfVaultOnDate(ibtContractAddress, 0) == 1e18);
        assert(rate == rateOracle.getRateOfVaultOnDate(ibtContractAddress, 0));
        assert(rateOracle.getLastPokedDateOfVault(ibtContractAddress) == 0);
        // poking on the same day
        // increase time by less than a day
        vm.warp(12 * 1 hours);
        rate = rateOracle.pokeRate(ibtContractAddress);
        assert(rateOracle.getRateOfVaultOnDate(ibtContractAddress, 0) == 1e18);
        assert(rate == rateOracle.getRateOfVaultOnDate(ibtContractAddress, 0));
        assert(rateOracle.getLastPokedDateOfVault(ibtContractAddress) == 0);

        // increase time (to day1)
        vm.warp(day1);
        // increase rate by 25% (should now be 1IBT:1.25Underlying)
        _increaseRate(25);
        rate = rateOracle.pokeRate(ibtContractAddress);
        assert(rateOracle.getRateOfVaultOnDate(ibtContractAddress, 1) == 1.25 * 1e18);
        assert(rate == rateOracle.getRateOfVaultOnDate(ibtContractAddress, 1));
        assert(rateOracle.getLastPokedDateOfVault(ibtContractAddress) == 1);

        // increase time (to day2)
        vm.warp(day2);
        // increase rate by 100% (should now be 1IBT:2.5Underlying)
        _increaseRate(100);
        rate = rateOracle.pokeRate(ibtContractAddress);
        assert(rateOracle.getRateOfVaultOnDate(ibtContractAddress, 2) == 2.5 * 1e18);
        assert(rate == rateOracle.getRateOfVaultOnDate(ibtContractAddress, 2));
        assert(rateOracle.getLastPokedDateOfVault(ibtContractAddress) == 2);

        // increase time (but still day 2)
        vm.warp(stillday2);
        // decrease rate by 75% (should now be 1IBT:0.625Underlying)
        _increaseRate(-75);
        rate = rateOracle.pokeRate(ibtContractAddress);
        assert(rateOracle.getRateOfVaultOnDate(ibtContractAddress, 3) == 0);
        assert(rate == rateOracle.getRateOfVaultOnDate(ibtContractAddress, 2));
        assert(rateOracle.getLastPokedDateOfVault(ibtContractAddress) == 2);

        // increase time (to day3)
        vm.warp(day3);
        rate = rateOracle.pokeRate(ibtContractAddress);
        // rate should have remained the same (should now be 1IBT:0.625Underlying)
        assert(rateOracle.getRateOfVaultOnDate(ibtContractAddress, 3) == 0.625 * 1e18);
        assert(rate == rateOracle.getRateOfVaultOnDate(ibtContractAddress, 3));
        assert(rateOracle.getLastPokedDateOfVault(ibtContractAddress) == 3);

        // increase time (to day4)
        vm.warp(day4);
        // increase rate by 20% (should now be 1IBT:0.75Underlying)
        _increaseRate(20);
        rate = rateOracle.pokeRate(ibtContractAddress);
        assert(rateOracle.getRateOfVaultOnDate(ibtContractAddress, 4) == 0.75 * 1e18);
        assert(rate == rateOracle.getRateOfVaultOnDate(ibtContractAddress, 4));
        assert(rateOracle.getLastPokedDateOfVault(ibtContractAddress) == 4);

        // increase time (to day5)
        vm.warp(day5);
        // increase rate by 40% (should now be 1IBT:1.05Underlying)
        _increaseRate(40);
        rate = rateOracle.pokeRate(ibtContractAddress);
        assert(rateOracle.getRateOfVaultOnDate(ibtContractAddress, 5) == 1.05 * 1e18);
        assert(rate == rateOracle.getRateOfVaultOnDate(ibtContractAddress, 5));
        assert(rateOracle.getLastPokedDateOfVault(ibtContractAddress) == 5);
    }
}
