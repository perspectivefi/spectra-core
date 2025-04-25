// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.20;

import "forge-std/Test.sol";

import "../src/Registry.sol";
import "../script/00_deployAccessManager.s.sol";
import "../script/01_deployRegistry.s.sol";
import "../src/libraries/Roles.sol";

contract ContractRegistry is Test {
    address public scriptAdmin;
    Registry public registry;
    AccessManager public accessManager;
    address feeCollector = 0x0000000000000000000000000000000000000FEE;
    address MOCK_ADDR_1 = 0x0000000000000000000000000000000000000001;
    address MOCK_ADDR_2 = 0x0000000000000000000000000000000000000002;
    address MOCK_ADDR_3 = 0x0000000000000000000000000000000000000003;
    address MOCK_ADDR_4 = 0x0000000000000000000000000000000000000004;

    uint256 MAX_TOKENIZATION_FEE = 1e16;
    uint256 MAX_YIELD_FEE = 5e17;
    uint256 MAX_PT_FLASH_LOAN_FEE = 1e18;

    uint256 public TOKENIZATION_FEE = 1e15;
    uint256 public YIELD_FEE = 0;
    uint256 public PT_FLASH_LOAN_FEE = 0;

    uint256 public FEE_DIVISOR = 1e18;
    uint256 public DURATION = 100000;

    /* Events
     *****************************************************************************************************************/
    event FactoryChange(address indexed previousFactory, address indexed newFactory);
    event RouterChange(address indexed previousRouter, address indexed newRouter);
    event RouterUtilChange(address indexed previousRouterUtil, address indexed newRouterUtil);
    event PTBeaconChange(address indexed previousPtBeacon, address indexed newPtBeacon);
    event YTBeaconChange(address indexed previousYtBeacon, address indexed newYtBeacon);
    event TokenizationFeeChange(uint256 previousTokenizationFee, uint256 newTokenizationFee);
    event YieldFeeChange(uint256 previousYieldFee, uint256 newYieldFee);
    event PTFlashLoanFeeChange(uint256 previousPTFlashLoanFee, uint256 newPtFlashLoanFee);
    event FeeCollectorChange(address indexed previousFeeCollector, address indexed newFeeCollector);
    event FeeReduced(address indexed pt, address indexed user, uint256 reduction);
    event PTAdded(address indexed pt);
    event PTRemoved(address indexed pt);

    function setUp() public {
        // default account for deploying scripts contracts. refer to line 35 of
        // https://github.com/foundry-rs/foundry/blob/master/evm/src/lib.rs for more details
        scriptAdmin = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;
        // Setup Access Manager
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
        accessManager.grantRole(Roles.REGISTRY_ROLE, address(scriptAdmin), 0);
        vm.prank(scriptAdmin);
        accessManager.grantRole(Roles.FEE_SETTER_ROLE, address(scriptAdmin), 0);
    }

    function testSetFactory() public {
        vm.startPrank(scriptAdmin);
        vm.expectEmit(true, true, true, false);
        emit FactoryChange(address(0), MOCK_ADDR_1);
        registry.setFactory(MOCK_ADDR_1);
        vm.stopPrank();
        address expected = MOCK_ADDR_1;
        assertEq(expected, registry.getFactory());
    }

    function testSetRouter() public {
        vm.startPrank(scriptAdmin);
        vm.expectEmit(true, true, true, false);
        emit RouterChange(address(0), MOCK_ADDR_1);
        registry.setRouter(MOCK_ADDR_1);
        vm.stopPrank();
        address expected = MOCK_ADDR_1;
        assertEq(expected, registry.getRouter());
    }

    function testSetRouterUtil() public {
        vm.startPrank(scriptAdmin);
        vm.expectEmit(true, true, true, false);
        emit RouterUtilChange(address(0), MOCK_ADDR_1);
        registry.setRouterUtil(MOCK_ADDR_1);
        vm.stopPrank();
        address expected = MOCK_ADDR_1;
        assertEq(expected, registry.getRouterUtil());
    }

    function testSetPTBeacon() public {
        vm.startPrank(scriptAdmin);
        vm.expectEmit(true, true, true, false);
        emit PTBeaconChange(address(0), MOCK_ADDR_1);
        registry.setPTBeacon(MOCK_ADDR_1);
        vm.stopPrank();
        assertEq(MOCK_ADDR_1, registry.getPTBeacon());
    }

    function testSetYTBeacon() public {
        vm.startPrank(scriptAdmin);
        vm.expectEmit(true, true, true, false);
        emit YTBeaconChange(address(0), MOCK_ADDR_1);
        registry.setYTBeacon(MOCK_ADDR_1);
        vm.stopPrank();
        assertEq(MOCK_ADDR_1, registry.getYTBeacon());
    }

    function testSetTokenizationFee() public {
        vm.startPrank(scriptAdmin);
        vm.expectEmit(true, true, true, false);
        emit TokenizationFeeChange(TOKENIZATION_FEE, TOKENIZATION_FEE + 1);
        registry.setTokenizationFee(TOKENIZATION_FEE + 1);
        vm.stopPrank();
        assertEq(TOKENIZATION_FEE + 1, registry.getTokenizationFee());
    }

    function testSetTokenizationFeeWithValueTooHigh() public {
        vm.startPrank(scriptAdmin);
        bytes memory revertData = abi.encodeWithSignature("FeeGreaterThanMaxValue()");
        vm.expectRevert(revertData);
        registry.setTokenizationFee(MAX_TOKENIZATION_FEE + 1);
        vm.stopPrank();
    }

    function testSetYieldFee() public {
        vm.startPrank(scriptAdmin);
        vm.expectEmit(true, true, true, false);
        emit YieldFeeChange(YIELD_FEE, YIELD_FEE + 1);
        registry.setYieldFee(YIELD_FEE + 1);
        vm.stopPrank();
        assertEq(YIELD_FEE + 1, registry.getYieldFee());
    }

    function testSetYieldFeeWithValueTooHigh() public {
        vm.startPrank(scriptAdmin);
        bytes memory revertData = abi.encodeWithSignature("FeeGreaterThanMaxValue()");
        vm.expectRevert(revertData);
        registry.setYieldFee(MAX_YIELD_FEE + 1);
        vm.stopPrank();
    }

    function testSetPTFlashLoanFee() public {
        vm.startPrank(scriptAdmin);
        vm.expectEmit(true, true, true, false);
        emit PTFlashLoanFeeChange(PT_FLASH_LOAN_FEE, PT_FLASH_LOAN_FEE + 1);
        registry.setPTFlashLoanFee(PT_FLASH_LOAN_FEE + 1);
        vm.stopPrank();
        assertEq(PT_FLASH_LOAN_FEE + 1, registry.getPTFlashLoanFee());
    }

    function testSetPTFlashLoanFeeWithValueTooHigh() public {
        vm.startPrank(scriptAdmin);
        bytes memory revertData = abi.encodeWithSignature("FeeGreaterThanMaxValue()");
        vm.expectRevert(revertData);
        registry.setPTFlashLoanFee(MAX_PT_FLASH_LOAN_FEE + 1);
        vm.stopPrank();
    }

    function testSetFeeCollector() public {
        vm.startPrank(scriptAdmin);
        vm.expectEmit(true, true, true, false);
        emit FeeCollectorChange(feeCollector, MOCK_ADDR_1);
        registry.setFeeCollector(MOCK_ADDR_1);
        vm.stopPrank();
        assertEq(MOCK_ADDR_1, registry.getFeeCollector());
    }

    function testReduceFee() public {
        vm.startPrank(scriptAdmin);
        vm.expectEmit(true, true, true, false);
        emit FeeReduced(address(0xa), address(0xa), 1);
        registry.reduceFee(address(0xa), address(0xa), 1);
        vm.stopPrank();
        assertEq(1, registry.getFeeReduction(address(0xa), address(0xa)));
    }

    function testReduceFeeWithValueTooHigh() public {
        vm.startPrank(scriptAdmin);
        bytes memory revertData = abi.encodeWithSignature("ReductionTooBig()");
        vm.expectRevert(revertData);
        registry.reduceFee(address(0xa), address(0xa), FEE_DIVISOR + 1);
        vm.stopPrank();
    }

    function testSetFactoryWithoutAdmin() public {
        vm.startPrank(MOCK_ADDR_2);
        bytes memory revertData = abi.encodeWithSelector(
            bytes4(keccak256("AccessManagedUnauthorized(address)")),
            MOCK_ADDR_2
        );
        vm.expectRevert(revertData);
        registry.setFactory(MOCK_ADDR_1);
        vm.stopPrank();
    }

    function testSetRouterWithoutAdmin() public {
        vm.prank(MOCK_ADDR_2);
        bytes memory revertData = abi.encodeWithSelector(
            bytes4(keccak256("AccessManagedUnauthorized(address)")),
            MOCK_ADDR_2
        );
        vm.expectRevert(revertData);
        registry.setRouter(MOCK_ADDR_2);
    }

    function testSetPTBeaconWithoutAdmin() public {
        vm.startPrank(MOCK_ADDR_2);
        bytes memory revertData = abi.encodeWithSelector(
            bytes4(keccak256("AccessManagedUnauthorized(address)")),
            MOCK_ADDR_2
        );
        vm.expectRevert(revertData);
        registry.setPTBeacon(MOCK_ADDR_1);
        vm.stopPrank();
    }

    function testSetYTBeaconWithoutAdmin() public {
        vm.startPrank(MOCK_ADDR_2);
        bytes memory revertData = abi.encodeWithSelector(
            bytes4(keccak256("AccessManagedUnauthorized(address)")),
            MOCK_ADDR_2
        );
        vm.expectRevert(revertData);
        registry.setYTBeacon(MOCK_ADDR_1);
        vm.stopPrank();
    }

    function testSetTokenizationFeeWithoutAdmin() public {
        vm.startPrank(MOCK_ADDR_2);
        bytes memory revertData = abi.encodeWithSelector(
            bytes4(keccak256("AccessManagedUnauthorized(address)")),
            MOCK_ADDR_2
        );
        vm.expectRevert(revertData);
        registry.setTokenizationFee(TOKENIZATION_FEE + 1);
        vm.stopPrank();
    }

    function testSetYieldFeeWithoutAdmin() public {
        vm.startPrank(MOCK_ADDR_2);
        bytes memory revertData = abi.encodeWithSelector(
            bytes4(keccak256("AccessManagedUnauthorized(address)")),
            MOCK_ADDR_2
        );
        vm.expectRevert(revertData);
        registry.setYieldFee(YIELD_FEE + 1);
        vm.stopPrank();
    }

    function testSetPTFlashLoanFeeWithoutAdmin() public {
        vm.startPrank(MOCK_ADDR_2);
        bytes memory revertData = abi.encodeWithSelector(
            bytes4(keccak256("AccessManagedUnauthorized(address)")),
            MOCK_ADDR_2
        );
        vm.expectRevert(revertData);
        registry.setPTFlashLoanFee(PT_FLASH_LOAN_FEE + 1);
        vm.stopPrank();
    }

    function testSetFeeCollectorWithoutAdmin() public {
        vm.startPrank(MOCK_ADDR_2);
        bytes memory revertData = abi.encodeWithSelector(
            bytes4(keccak256("AccessManagedUnauthorized(address)")),
            MOCK_ADDR_2
        );
        vm.expectRevert(revertData);
        registry.setFeeCollector(MOCK_ADDR_1);
        vm.stopPrank();
    }

    function testReduceFeeWithoutAdmin() public {
        vm.startPrank(MOCK_ADDR_2);
        bytes memory revertData = abi.encodeWithSelector(
            bytes4(keccak256("AccessManagedUnauthorized(address)")),
            MOCK_ADDR_2
        );
        vm.expectRevert(revertData);
        registry.reduceFee(address(0xa), address(0xa), 1);
        vm.stopPrank();
    }

    function testPrincipalTokenCountAtInit() public {
        assertTrue(registry.pTCount() == 0);
    }

    function testAddPrincipalTokenAsOwner() public {
        vm.startPrank(scriptAdmin);
        vm.expectEmit(true, true, true, true);
        emit PTAdded(MOCK_ADDR_2);
        registry.addPT(MOCK_ADDR_2);
        vm.stopPrank();

        assertEq(MOCK_ADDR_2, registry.getPTAt(0));
        assertEq(1, registry.pTCount());
        assertEq(true, registry.isRegisteredPT(MOCK_ADDR_2));
        assertEq(false, registry.isRegisteredPT(MOCK_ADDR_3));
    }

    function testAddPrincipalTokenAsFactory() public {
        vm.startPrank(scriptAdmin);
        accessManager.grantRole(Roles.REGISTRY_ROLE, address(MOCK_ADDR_1), 0);
        vm.stopPrank();

        vm.startPrank(MOCK_ADDR_1);
        vm.expectEmit(true, true, true, true);
        emit PTAdded(MOCK_ADDR_2);
        // add pt as factory
        registry.addPT(MOCK_ADDR_2);
        vm.stopPrank();

        assertEq(MOCK_ADDR_2, registry.getPTAt(0));
        assertEq(1, registry.pTCount());
        assertEq(true, registry.isRegisteredPT(MOCK_ADDR_2));
        assertEq(false, registry.isRegisteredPT(MOCK_ADDR_3));
    }

    function testPrincipalTokenAt() public {
        vm.startPrank(scriptAdmin);
        registry.addPT(MOCK_ADDR_3);
        registry.addPT(MOCK_ADDR_2);
        assertEq(MOCK_ADDR_3, registry.getPTAt(0));
        assertEq(MOCK_ADDR_2, registry.getPTAt(1));
        vm.stopPrank();
    }

    function testAddAlreadyAddedPrincipalToken() public {
        vm.startPrank(scriptAdmin);
        registry.addPT(MOCK_ADDR_2);

        bytes memory revertData = abi.encodeWithSignature("PTListUpdateFailed()");
        vm.expectRevert(revertData);
        // attempting to add already present PT
        registry.addPT(MOCK_ADDR_2);
        vm.stopPrank();
    }

    function testAddPrincipalTokenWithoutAdminOrFactory() public {
        vm.startPrank(MOCK_ADDR_1);
        bytes memory revertData = abi.encodeWithSelector(
            bytes4(keccak256("AccessManagedUnauthorized(address)")),
            MOCK_ADDR_1
        );
        vm.expectRevert(revertData);
        registry.addPT(MOCK_ADDR_2);
    }

    function testRemovePrincipalToken() public {
        vm.startPrank(scriptAdmin);
        registry.addPT(MOCK_ADDR_2);
        vm.expectEmit(true, true, true, true);
        emit PTRemoved(MOCK_ADDR_2);
        registry.removePT(MOCK_ADDR_2);
        vm.stopPrank();

        assertEq(0, registry.pTCount());
        assertEq(false, registry.isRegisteredPT(MOCK_ADDR_2));
    }

    function testRemoveMissingPrincipalToken() public {
        vm.startPrank(scriptAdmin);
        registry.addPT(MOCK_ADDR_2);
        registry.removePT(MOCK_ADDR_2);
        bytes memory revertData = abi.encodeWithSignature("PTListUpdateFailed()");
        vm.expectRevert(revertData);
        // attempting to remove missing address
        registry.removePT(MOCK_ADDR_2);
        vm.stopPrank();
    }

    function testRemovePrincipalTokenWithoutAdmin() public {
        vm.prank(scriptAdmin);
        registry.addPT(MOCK_ADDR_2);
        vm.startPrank(MOCK_ADDR_1);
        bytes memory revertData = abi.encodeWithSelector(
            bytes4(keccak256("AccessManagedUnauthorized(address)")),
            MOCK_ADDR_1
        );
        vm.expectRevert(revertData);
        registry.removePT(MOCK_ADDR_2);
    }
}
