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
import "script/09_deployRouter.s.sol";
import "src/mocks/MockERC20.sol";
import "src/mocks/MockIBT2.sol";
import {Math} from "openzeppelin-math/Math.sol";
import {Commands} from "src/router/Commands.sol";
import {Constants} from "src/router/Constants.sol";
import {Roles} from "src/libraries/Roles.sol";
import {IRouter} from "src/interfaces/IRouter.sol";
import {IAccessManager} from "@openzeppelin/contracts/access/manager/IAccessManager.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import "openzeppelin-contracts/proxy/beacon/UpgradeableBeacon.sol";

contract ContractRouterKyberswapTest is Test {
    error KyberRouterNotSet();
    using Math for uint256;

    uint256 public fork;
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    address public other = 0x0000000000000000000000000000000000011111;

    address accessManager;
    address router;

    address scriptAdmin;
    address testUser;

    address WETH;
    address stETH;
    address kyberRouter;
    address registry;
    MockERC20 public underlying;
    MockIBT2 public ibt;
    PrincipalToken public principalToken;
    Factory public factory;
    address public curveFactoryAddress = 0x90f584A7AfA70ECa0cf073082Ab0Ec95e5EfE38a;
    UpgradeableBeacon public principalTokenBeacon;
    UpgradeableBeacon public ytBeacon;
    YieldToken public yt;
    uint256 public constant DURATION = 15724800; // 182 days
    uint256 public IBT_UNIT;

    function setUp() public {
        // fixing the block timestamp for having a valid Kyberswap route calldata
        fork = vm.createFork(MAINNET_RPC_URL, 21786822);
        vm.selectFork(fork);

        scriptAdmin = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;
        testUser = address(this);

        // mainnet addresses
        WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        stETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
        kyberRouter = 0x6131B5fae19EA4f9D964eAc0408E4408b66337b5;

        AccessManagerDeploymentScript accessManagerScript = new AccessManagerDeploymentScript();
        accessManager = accessManagerScript.deployForTest(scriptAdmin);
        // deploy registry
        RegistryScript registryScript = new RegistryScript();
        registry = registryScript.deployForTest(0, 0, 0, address(0xFEE), accessManager);
        vm.prank(scriptAdmin);
        IAccessManager(accessManager).grantRole(Roles.REGISTRY_ROLE, scriptAdmin, 0);

        // deploy router
        RouterScript routerScript = new RouterScript();
        (router, , ) = routerScript.deployForTest(
            registry,
            kyberRouter,
            // address(0),
            accessManager
        );
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = IRouter.setKyberRouter.selector;
        vm.prank(scriptAdmin);
        IAccessManager(accessManager).setTargetFunctionRole(
            address(router),
            selectors,
            Roles.REGISTRY_ROLE
        );

        // deal ETH
        vm.deal(testUser, 1000e18);

        // deal WETH
        deal(WETH, testUser, 1000e18);
        IERC20(WETH).approve(router, 1000e18);
    }

    // -----------------------
    // --- EXECUTION TESTS ---
    // -----------------------

    function testSwapWETH_stETH() public {
        uint256 amountIn = 2e17;

        // fetch targetData + expectedAmountOut off-chain and paste them here
        bytes memory targetData = hex"";
        uint256 expectedAmountOut = 0;

        bytes memory commands = abi.encodePacked(
            bytes1(uint8(Commands.TRANSFER_FROM)),
            bytes1(uint8(Commands.KYBER_SWAP))
        );
        bytes[] memory inputs = new bytes[](2);
        inputs[0] = abi.encode(WETH, amountIn);
        inputs[1] = abi.encode(WETH, amountIn, stETH, expectedAmountOut, targetData);

        uint256 previewRate = IRouter(router).previewRate(commands, inputs);
        uint256 expectedStETH = amountIn.mulDiv(previewRate, 1e27, Math.Rounding.Ceil);

        uint256 wethBalBefore = IERC20(WETH).balanceOf(testUser);
        uint256 stETHBalBefore = IERC20(stETH).balanceOf(router);

        IRouter(router).execute(commands, inputs);

        uint256 wethBalAfter = IERC20(WETH).balanceOf(testUser);
        uint256 stETHBalAfter = IERC20(stETH).balanceOf(router);

        assertEq(wethBalBefore - wethBalAfter, amountIn);
        assertApproxEqRel(expectedStETH, expectedAmountOut, 1e16);
        assertApproxEqRel(stETHBalAfter - stETHBalBefore, expectedAmountOut, 1e16);
    }

    function testSwapETH_stETH() public {
        uint256 amountIn = 2e17;

        // fetch targetData + expectedAmountOut off-chain and paste them here
        bytes memory targetData = hex"";
        uint256 expectedAmountOut = 0;

        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.KYBER_SWAP)));
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(Constants.ETH, amountIn, stETH, expectedAmountOut, targetData);

        uint256 previewRate = IRouter(router).previewRate(commands, inputs);
        uint256 expectedStETH = amountIn.mulDiv(previewRate, 1e27, Math.Rounding.Ceil);

        uint256 ethBalBefore = testUser.balance;
        uint256 stETHBalBefore = IERC20(stETH).balanceOf(router);

        IRouter(router).execute{value: amountIn}(commands, inputs);

        uint256 ethBalAfter = testUser.balance;
        uint256 stETHBalAfter = IERC20(stETH).balanceOf(router);

        assertEq(ethBalBefore - ethBalAfter, amountIn);
        assertApproxEqRel(expectedStETH, expectedAmountOut, 1e16);
        assertApproxEqRel(stETHBalAfter - stETHBalBefore, expectedAmountOut, 1e16);
    }

    function testDisableKyberRouter() public {
        vm.prank(scriptAdmin);
        IRouter(router).setKyberRouter(address(0));
        uint256 amountIn = 2e17;

        // fetch targetData + expectedAmountOut off-chain and paste them here
        bytes memory targetData = hex"";
        uint256 expectedAmountOut = 0;

        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.KYBER_SWAP)));
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(Constants.ETH, amountIn, stETH, expectedAmountOut, targetData);

        vm.expectRevert(KyberRouterNotSet.selector);
        uint256 previewRate = IRouter(router).previewRate(commands, inputs);

        vm.expectRevert(KyberRouterNotSet.selector);
        IRouter(router).execute{value: amountIn}(commands, inputs);
    }

    function testSwapETHDuringFlashLoan() public {
        _deployProtocol();

        address USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        uint256 amountIn = 2e18;
        // fetch targetData + expectedAmountOut off-chain and paste them here
        bytes
            memory targetData = hex"e21fd0e900000000000000000000000000000000000000000000000000000000000000200000000000000000000000000f4a1d7fdf4890be35e71f3e0bbc4a0ec377eca3000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000003a000000000000000000000000000000000000000000000000000000000000005a000000000000000000000000000000000000000000000000000000000000002e0000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000978e3286eb805934215a88694d80b09aded68d900000000000000000000000000000000000000000000000000000000067a4918300000000000000000000000000000000000000000000000000000000000002800000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000004063407a490000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000e00000000000000000000000000f4a1d7fdf4890be35e71f3e0bbc4a0ec377eca300000000000000000000000088e6a0c2ddd26feeb64f039a2c41296fcb3f5640000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb480000000000000000000000000000000000000000000000001bc16d674ec80000000000000000000000000000fff6fbe64b68d618d47c209fe40b0d8ee6e23c910000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000001639000000000000000000000001531fb539000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb480000000000000000000000000000000000000000000000000000000000000160000000000000000000000000000000000000000000000000000000000000018000000000000000000000000000000000000000000000000000000000000001a000000000000000000000000000000000000000000000000000000000000001c0000000000000000000000000978e3286eb805934215a88694d80b09aded68d900000000000000000000000000000000000000000000000001bc16d674ec800000000000000000000000000000000000000000000000000000000000131362319000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001e00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002247b22536f75726365223a2273706563747261222c22416d6f756e74496e555344223a22353639322e34333138373033313234222c22416d6f756e744f7574555344223a22353639332e313232363639363337343537222c22526566657272616c223a22222c22466c616773223a302c22416d6f756e744f7574223a2235363839353534323333222c2254696d657374616d70223a313733383833373230332c22496e74656772697479496e666f223a7b224b65794944223a2231222c225369676e6174757265223a224c735362644d7770572b463571536e716c332f34486154342b43303337655335452b3633456c76545971466c336f4a337146552f454a7668646b6f354576314d573254664a67706479497331316a4e43673630676e71325879546a6944725936376f557250435a70417046544a774c394b5157556c63564b377a72504d5a3147646e587a78684e69324d4b7a4a7a4649655a3036664a7a51316c794c2b664330716c38494638342b656763796f477177663562483048783248316376504c6a436e2b4f4f505478742b38555248424559464a39534d647470466d396c74386f706b6a7761524c355177376b69794b69347a69694e3436663376496f4e72372f32662f335a444d364e75676477442f636b6679636c4e514772547245684263654c5846397361524e55646d3975754a306a6175306356794a4e74496f7a35462f44783874646a594c462f41726c6f507a36576f6b7479413d3d227d7d00000000000000000000000000000000000000000000000000000000";
        uint256 expectedAmountOut = 5689554233;
        bytes memory flashLoanCommands = abi.encodePacked(
            bytes1(uint8(Commands.KYBER_SWAP)),
            bytes1(uint8(Commands.TRANSFER))
        );
        bytes[] memory flashLoanInputs = new bytes[](2);
        flashLoanInputs[0] = abi.encode(
            Constants.ETH,
            amountIn,
            USDC,
            expectedAmountOut,
            targetData
        );
        flashLoanInputs[1] = abi.encode(USDC, testUser, Constants.CONTRACT_BALANCE);
        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.FLASH_LOAN)));
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(
            address(principalToken),
            address(ibt),
            1 ether,
            abi.encode(flashLoanCommands, flashLoanInputs)
        );
        vm.startPrank(testUser);
        uint256 ethBalBefore = testUser.balance;
        uint256 usdcBalBefore = IERC20(USDC).balanceOf(testUser);
        IRouter(router).execute{value: amountIn}(commands, inputs);
        uint256 ethBalAfter = testUser.balance;
        uint256 usdcBalAfter = IERC20(USDC).balanceOf(testUser);

        assertEq(ethBalBefore - ethBalAfter, amountIn);
        assertApproxEqRel(usdcBalAfter - usdcBalBefore, expectedAmountOut, 1e16);
        vm.stopPrank();
    }

    function _deployProtocol() internal {
        // deploy underlying and ibt
        underlying = new MockERC20();
        underlying.initialize("MOCK UNDERLYING", "MUDL"); // deploys underlying mints 100000e18 token to caller
        ibt = new MockIBT2();
        ibt.initialize("MOCK IBT", "MIBT", IERC20Metadata(address(underlying))); // deploys ibt which principalToken holds
        IBT_UNIT = 10 ** ibt.decimals();
        underlying.approve(address(ibt), 10_000_000e18);
        ibt.deposit(10_000_000e18, other);

        // deploy principalToken and yieldToken instances and beacons
        PrincipalTokenInstanceScript principalTokenInstanceScript = new PrincipalTokenInstanceScript();
        YTInstanceScript ytInstanceScript = new YTInstanceScript();
        PrincipalToken principalTokenInstance = PrincipalToken(
            principalTokenInstanceScript.deployForTest(address(registry))
        );
        YieldToken ytInstance = YieldToken(ytInstanceScript.deployForTest());
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

        // deploy factory
        FactoryScript factoryScript = new FactoryScript();
        factory = Factory(
            factoryScript.deployForTest(
                address(registry),
                curveFactoryAddress,
                address(accessManager)
            )
        );

        vm.prank(scriptAdmin);
        IAccessManager(accessManager).grantRole(Roles.ADMIN_ROLE, address(factory), 0);
        vm.prank(scriptAdmin);
        IAccessManager(accessManager).grantRole(Roles.REGISTRY_ROLE, address(factory), 0);

        // deploy principalToken
        PrincipalTokenScript principalTokenScript = new PrincipalTokenScript();
        address principalTokenAddr = principalTokenScript.deployForTest(
            address(factory),
            address(ibt),
            DURATION
        );
        principalToken = PrincipalToken(principalTokenAddr);
        yt = YieldToken(principalToken.getYT());

        // add initial liquidity to curve pool according to initial price
        underlying.mint(testUser, 1_800_000e18);
        underlying.approve(address(ibt), 800_000e18);
        uint256 amountIBT = ibt.deposit(800_000e18, testUser);
        underlying.approve(principalTokenAddr, 1_000_000e18);
        uint256 amountPT = principalToken.deposit(1_000_000e18, testUser);

        vm.startPrank(testUser);
        // remove any leftover balance
        ibt.transfer(other, ibt.balanceOf(testUser));
        underlying.transfer(other, underlying.balanceOf(testUser));
        vm.stopPrank();
    }
}
