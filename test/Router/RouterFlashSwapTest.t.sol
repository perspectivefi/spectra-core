// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.20;

import "forge-std/Test.sol";

import {RouterBaseTest} from "./RouterBaseTest.t.sol";
import {Commands} from "src/router/Commands.sol";
import {Constants} from "src/router/Constants.sol";
import {IERC20} from "openzeppelin-contracts/interfaces/IERC20.sol";

contract ContractRouterFlashswapTest is RouterBaseTest {
    function setUp() public override {
        super.setUp();

        underlying.mint(testUser, FAUCET_AMOUNT * 4);
        underlying.approve(address(ibt), FAUCET_AMOUNT * 2);
        underlying.approve(address(principalToken), FAUCET_AMOUNT);

        ibt.mint(FAUCET_AMOUNT * 2, testUser);
        principalToken.deposit(FAUCET_AMOUNT, testUser);

        // Burn unnecessary YTs - e.g. make sure we have exactly FAUCET_AMOUNT tokens
        yt.transfer(other, yt.balanceOf(testUser) - FAUCET_AMOUNT);
    }

    function testHasTokens() public {
        assertEq(ibt.balanceOf(testUser), FAUCET_AMOUNT * 2);
        assertEq(underlying.balanceOf(testUser), FAUCET_AMOUNT);
        assertApproxEqAbs(principalToken.balanceOf(testUser), FAUCET_AMOUNT, 10);
        assertApproxEqAbs(yt.balanceOf(testUser), FAUCET_AMOUNT, 10);
    }

    function testHasApproved() public {
        assertEq(ibt.allowance(testUser, address(router)), FAUCET_AMOUNT);
        assertEq(underlying.allowance(testUser, address(router)), FAUCET_AMOUNT);
    }

    // -----------------------
    // --- EXECUTION TESTS ---
    // -----------------------

    function testFlashLoan() public {
        bytes memory flashLoanCommands = abi.encodePacked(bytes1(uint8(Commands.TRANSFER_FROM)));
        bytes[] memory flashLoanInputs = new bytes[](1);
        flashLoanInputs[0] = abi.encode(underlying, FAUCET_AMOUNT);
        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.FLASH_LOAN)));
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(
            address(principalToken),
            address(ibt),
            100 ether,
            abi.encode(flashLoanCommands, flashLoanInputs)
        );

        assertEq(underlying.balanceOf(address(this)), FAUCET_AMOUNT);
        assertEq(underlying.balanceOf(address(router)), 0);
        router.execute(commands, inputs);
        assertEq(underlying.balanceOf(address(this)), 0);
        assertEq(underlying.balanceOf(address(router)), FAUCET_AMOUNT);
    }

    function testFlashSwapIBTToExactYTFuzz(uint256 outputYTAmount) public {
        outputYTAmount = bound(outputYTAmount, 1e12, FAUCET_AMOUNT * 10);

        // * Pre-compute input values
        (uint256 inputIBTAmount, uint256 borrowedIBTAmount) = routerUtil
            .previewFlashSwapIBTToExactYT(address(curvePool), outputYTAmount);

        vm.assume(inputIBTAmount > 1e12 && inputIBTAmount <= FAUCET_AMOUNT);

        // * Prepare inputs
        bytes memory flashLoanCommands = abi.encodePacked(
            bytes1(uint8(Commands.DEPOSIT_IBT_IN_PT)),
            bytes1(uint8(Commands.CURVE_SWAP))
        );
        bytes[] memory flashLoanInputs = new bytes[](2);
        // Tokenize IBT into PrincipalToken:YieldToken
        flashLoanInputs[0] = abi.encode(
            address(principalToken),
            Constants.CONTRACT_BALANCE,
            Constants.ADDRESS_THIS,
            Constants.ADDRESS_THIS,
            0
        );
        // Swap principalToken for IBT
        flashLoanInputs[1] = abi.encode(
            address(curvePool),
            1,
            0,
            Constants.CONTRACT_BALANCE,
            0,
            Constants.ADDRESS_THIS
        );
        bytes memory commands = abi.encodePacked(
            bytes1(uint8(Commands.FLASH_LOAN)),
            bytes1(uint8(Commands.TRANSFER))
        );
        bytes[] memory inputs = new bytes[](2);
        // Borrow IBT
        inputs[0] = abi.encode(
            address(principalToken),
            address(ibt),
            borrowedIBTAmount,
            abi.encode(flashLoanCommands, flashLoanInputs)
        );
        // Send YieldToken
        inputs[1] = abi.encode(yt, address(this), Constants.CONTRACT_BALANCE);

        yt.transfer(address(1), yt.balanceOf(testUser)); // burn YTs
        assertEq(yt.balanceOf(testUser), 0);
        ibt.approve(address(router), inputIBTAmount);
        router.execute(commands, inputs);
        assertEq(yt.balanceOf(address(this)), outputYTAmount);
    }

    function testFlashSwapExactIBTToYTFuzz(uint256 inputIBTAmount) public {
        inputIBTAmount = bound(inputIBTAmount, 1e18, FAUCET_AMOUNT);

        // * Pre-compute input values
        (uint256 outputYTAmount, uint256 borrowedIBTAmount) = routerUtil
            .previewFlashSwapExactIBTToYT(address(curvePool), inputIBTAmount);

        // * Prepare inputs
        bytes memory flashLoanCommands = abi.encodePacked(
            bytes1(uint8(Commands.DEPOSIT_IBT_IN_PT)),
            bytes1(uint8(Commands.CURVE_SWAP))
        );
        bytes[] memory flashLoanInputs = new bytes[](2);
        {
            // Tokenise IBT into principalToken:YieldToken
            flashLoanInputs[0] = abi.encode(
                address(principalToken),
                Constants.CONTRACT_BALANCE,
                Constants.ADDRESS_THIS,
                Constants.ADDRESS_THIS,
                0
            );
            // Swap principalToken for IBT
            flashLoanInputs[1] = abi.encode(
                address(curvePool),
                1,
                0,
                Constants.CONTRACT_BALANCE,
                0,
                Constants.ADDRESS_THIS
            );
        }
        bytes memory commands = abi.encodePacked(
            bytes1(uint8(Commands.FLASH_LOAN)),
            bytes1(uint8(Commands.TRANSFER))
        );
        bytes[] memory inputs = new bytes[](2);
        {
            // Borrow IBT
            inputs[0] = abi.encode(
                address(principalToken),
                address(ibt),
                borrowedIBTAmount,
                abi.encode(flashLoanCommands, flashLoanInputs)
            );
            // Send YieldToken
            inputs[1] = abi.encode(yt, address(this), Constants.CONTRACT_BALANCE);
        }

        yt.transfer(address(1), yt.balanceOf(testUser)); // burn YTs
        assertEq(yt.balanceOf(testUser), 0);
        ibt.approve(address(router), inputIBTAmount);
        uint256 ibtBalBefore = IERC20(ibt).balanceOf(testUser);
        router.execute(commands, inputs);
        assertApproxEqRel(ibtBalBefore - IERC20(ibt).balanceOf(testUser), inputIBTAmount, 1e14);
        assertEq(yt.balanceOf(testUser), outputYTAmount);
    }

    function testFlashSwapExactYTToIBTFuzz(uint256 inputYTAmount) public {
        inputYTAmount = bound(inputYTAmount, 1e15, FAUCET_AMOUNT);

        // * Pre-compute input values
        (uint256 outputIBTAmount, uint256 borrowedIBTAmount) = routerUtil
            .previewFlashSwapExactYTToIBT(address(curvePool), inputYTAmount);

        assertEq(ibt.balanceOf(address(router)), 0);
        assertEq(principalToken.balanceOf(address(router)), 0);
        assertEq(yt.balanceOf(address(router)), 0);

        // * Prepare inputs
        bytes memory flashLoanCommands = abi.encodePacked(
            bytes1(uint8(Commands.CURVE_SWAP)),
            bytes1(uint8(Commands.TRANSFER_FROM)),
            bytes1(uint8(Commands.REDEEM_PT_FOR_IBT))
        );
        bytes[] memory flashLoanInputs = new bytes[](3);
        {
            // Swap IBT for PrincipalToken
            flashLoanInputs[0] = abi.encode(
                address(curvePool),
                0,
                1,
                Constants.CONTRACT_BALANCE,
                0,
                Constants.ADDRESS_THIS
            );
            // Collect input YieldToken
            flashLoanInputs[1] = abi.encode(address(yt), inputYTAmount);
            // Redeem PrincipalToken:YieldToken for IBT
            flashLoanInputs[2] = abi.encode(
                address(principalToken),
                Constants.CONTRACT_BALANCE,
                Constants.ADDRESS_THIS,
                0
            );
        }
        bytes memory commands = abi.encodePacked(
            bytes1(uint8(Commands.FLASH_LOAN)),
            bytes1(uint8(Commands.TRANSFER))
        );
        bytes[] memory inputs = new bytes[](2);
        {
            // Borrow IBT
            inputs[0] = abi.encode(
                address(principalToken),
                address(ibt),
                borrowedIBTAmount,
                abi.encode(flashLoanCommands, flashLoanInputs)
            );
            // Send remaining IBT
            inputs[1] = abi.encode(ibt, other, Constants.CONTRACT_BALANCE);
        }

        uint256 ibtBalanceOtherBefore = ibt.balanceOf(other);
        uint256 ytBalanceBefore = yt.balanceOf(testUser);
        yt.approve(address(router), inputYTAmount);
        router.execute(commands, inputs);
        assertEq(
            ytBalanceBefore - yt.balanceOf(testUser),
            inputYTAmount // amount spent
        );
        assertApproxEqRel(ibt.balanceOf(other) - ibtBalanceOtherBefore, outputIBTAmount, 1e8);
    }
}
