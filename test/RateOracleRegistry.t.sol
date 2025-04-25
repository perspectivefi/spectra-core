// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.20;

import "forge-std/Test.sol";

import "../src/RateOracleRegistry.sol";
import "../../script/00_deployAccessManager.s.sol";
import "../../script/22_deployRateOracleRegistry.s.sol";
import "../src/libraries/Roles.sol";

contract ContractRateOracleRegistry is Test {
    struct CurvePoolDeploymentData {
        address[2] coins;
        uint256 A;
        uint256 fee;
        uint256 fee_mul;
        uint256 ma_exp_time;
        uint256 initial_price;
    }
    address public scriptAdmin;
    RateOracleRegistry public rateOracleRegistry;
    AccessManager public accessManager;
    address MOCK_ADDR_1 = 0x0000000000000000000000000000000000000001;
    address MOCK_ADDR_2 = 0x0000000000000000000000000000000000000002;
    address MOCK_ADDR_3 = 0x0000000000000000000000000000000000000003;
    address MOCK_ADDR_4 = 0x0000000000000000000000000000000000000004;

    uint256 public DURATION = 100000;

    /* Errors
     *****************************************************************************************************************/
    error AddressError();
    error PTRateOracleMismatch();
    error AccessManagedUnauthorized(address sender);

    /* Events
     *****************************************************************************************************************/
    event FactorySNGChange(address indexed previousFactorySNG, address indexed newFactorySNG);
    event RateOracleBeaconChange(
        address indexed previousRateOracleBeacon,
        address indexed newRateOracleBeacon
    );
    event RateOracleAdded(address indexed pt, address indexed rateOracle);
    event RateOracleRemoved(address indexed pt, address indexed rateOracle);

    function setUp() public {
        // default account for deploying scripts contracts. refer to line 35 of
        // https://github.com/foundry-rs/foundry/blob/master/evm/src/lib.rs for more details
        scriptAdmin = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;
        // Setup Access Manager
        AccessManagerDeploymentScript accessManagerScript = new AccessManagerDeploymentScript();
        accessManager = AccessManager(accessManagerScript.deployForTest(scriptAdmin));
        RateOracleRegistryScript registryScript = new RateOracleRegistryScript();
        rateOracleRegistry = RateOracleRegistry(
            registryScript.deployForTest(address(accessManager))
        );
        vm.prank(scriptAdmin);
        accessManager.grantRole(Roles.REGISTRY_ROLE, address(scriptAdmin), 0);
    }

    function testSetFactorySNG() public {
        vm.startPrank(scriptAdmin);
        vm.expectEmit(true, true, true, false);
        emit FactorySNGChange(rateOracleRegistry.getFactorySNG(), MOCK_ADDR_1);
        rateOracleRegistry.setFactorySNG(MOCK_ADDR_1);
        vm.stopPrank();
        address expected = MOCK_ADDR_1;
        assertEq(expected, rateOracleRegistry.getFactorySNG());
    }

    function testSetRateOracleBeacon() public {
        vm.startPrank(scriptAdmin);
        vm.expectEmit(true, true, true, false);
        emit RateOracleBeaconChange(rateOracleRegistry.getRateOracleBeacon(), MOCK_ADDR_1);
        rateOracleRegistry.setRateOracleBeacon(MOCK_ADDR_1);
        vm.stopPrank();
        address expected = MOCK_ADDR_1;
        assertEq(expected, rateOracleRegistry.getRateOracleBeacon());
    }

    function testAddRateOracle() public {
        vm.startPrank(scriptAdmin);
        vm.expectEmit(true, true, true, false);
        address rate_oracle = MOCK_ADDR_1;
        address pt = MOCK_ADDR_2;
        emit RateOracleAdded(pt, rate_oracle);
        rateOracleRegistry.addRateOracle(pt, rate_oracle);
        vm.stopPrank();
        address expected = MOCK_ADDR_1;
        assertEq(expected, rateOracleRegistry.getRateOracle(pt));
    }

    function testRemoveRateOracle() public {
        vm.startPrank(scriptAdmin);
        address rate_oracle = MOCK_ADDR_1;
        address pt = MOCK_ADDR_2;
        rateOracleRegistry.addRateOracle(pt, rate_oracle);
        vm.expectEmit(true, true, true, false);
        emit RateOracleRemoved(pt, rate_oracle);
        rateOracleRegistry.removeRateOracle(pt, rate_oracle);
        address expected = address(0);
        assertEq(expected, rateOracleRegistry.getRateOracle(pt));
        vm.stopPrank();
    }

    function testRemoveOracleWithPTMismatch() public {
        vm.startPrank(scriptAdmin);
        address rate_oracle = MOCK_ADDR_1;
        address pt = MOCK_ADDR_2;
        rateOracleRegistry.addRateOracle(pt, rate_oracle);
        vm.expectRevert(PTRateOracleMismatch.selector);
        rateOracleRegistry.removeRateOracle(MOCK_ADDR_3, rate_oracle);
    }

    function testAddRateOracleRevertsWithZeroAddress() public {
        vm.startPrank(scriptAdmin);
        vm.expectRevert(AddressError.selector);
        rateOracleRegistry.addRateOracle(address(0), address(0));
        address rate_oracle = MOCK_ADDR_1;
        address pt = MOCK_ADDR_2;

        vm.expectRevert(AddressError.selector);
        rateOracleRegistry.addRateOracle(pt, address(0));

        vm.expectRevert(AddressError.selector);
        rateOracleRegistry.addRateOracle(address(0), rate_oracle);
    }

    function testSetRateOracleBeaconNoAdmin() public {
        vm.startPrank(MOCK_ADDR_1);

        address rateOracleBeacon = MOCK_ADDR_2;
        bytes memory revertData = abi.encodeWithSelector(
            bytes4(keccak256("AccessManagedUnauthorized(address)")),
            MOCK_ADDR_1
        );
        vm.expectRevert(revertData);
        rateOracleRegistry.setRateOracleBeacon(rateOracleBeacon);
    }

    function testAddRateOracleNoAdmin() public {
        vm.startPrank(MOCK_ADDR_1);

        address pt = MOCK_ADDR_2;
        address rate_oracle = MOCK_ADDR_3;
        bytes memory revertData = abi.encodeWithSelector(
            bytes4(keccak256("AccessManagedUnauthorized(address)")),
            MOCK_ADDR_1
        );
        vm.expectRevert(revertData);
        rateOracleRegistry.addRateOracle(pt, rate_oracle);
    }

    function testRemoveRateOracleNoAdmin() public {
        vm.startPrank(MOCK_ADDR_1);

        address pt = MOCK_ADDR_2;
        address rate_oracle = MOCK_ADDR_3;
        bytes memory revertData = abi.encodeWithSelector(
            bytes4(keccak256("AccessManagedUnauthorized(address)")),
            MOCK_ADDR_1
        );
        vm.expectRevert(revertData);
        rateOracleRegistry.removeRateOracle(pt, rate_oracle);
    }

    function testSetFactorySNGNoAdmin() public {
        vm.startPrank(MOCK_ADDR_1);

        address newFactorySNG = MOCK_ADDR_2;
        bytes memory revertData = abi.encodeWithSelector(
            bytes4(keccak256("AccessManagedUnauthorized(address)")),
            MOCK_ADDR_1
        );
        vm.expectRevert(revertData);
        rateOracleRegistry.setFactorySNG(newFactorySNG);
    }
}
