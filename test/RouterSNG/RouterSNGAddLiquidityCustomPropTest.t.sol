// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.20;

import "forge-std/Test.sol";

import "src/libraries/CurvePoolUtil.sol";

import {RouterSNGBaseTest} from "./RouterSNGBaseTest.t.sol";
import {Commands} from "src/router/Commands.sol";
import {Constants} from "src/router/Constants.sol";
import {IStableSwapNG} from "src/interfaces/IStableSwapNG.sol";

contract ContractRouterLiquidityTest is RouterSNGBaseTest {
    using Math for uint256;

    uint256 private constant MIN_PROP = 1e17;
    uint256 private constant MAX_PROP = 1e19;

    address MOCK_ADDR_1 = 0x0000000000000000000000000000000000000001;

    function setUp() public override {
        super.setUp();
    }

    function testCustomLiquiditySplit(
        uint256 underlyingAmount,
        uint256 prop,
        uint8 underlying_decimals,
        uint8 ibt_decimals
    ) public {
        // deploy protocol with custom decimals
        underlying_decimals = uint8(bound(underlying_decimals, MIN_DECIMALS, MAX_DECIMALS));
        ibt_decimals = uint8(bound(ibt_decimals, underlying_decimals, MAX_DECIMALS));
        super.deployProtocol(underlying_decimals, ibt_decimals, address(factory), curvePoolParams);

        // define the fuzz
        underlyingAmount = bound(underlyingAmount, 1 * UNDERLYING_UNIT, 100_000 * UNDERLYING_UNIT);
        prop = bound(prop, MIN_PROP, MAX_PROP);

        // Preview deposit into the ibt
        uint256 shares = ibt.previewDeposit(underlyingAmount);

        // calculate amount of ibts to tokenize
        uint256 ibtsToTokenize = CurvePoolUtil.calcIBTsToTokenizeForCurvePoolCustomProp(
            shares,
            prop,
            address(principalToken)
        );

        uint256 ptShares = principalToken.previewDepositIBT(ibtsToTokenize);

        assertApproxEqRel(
            uint256(shares - ibtsToTokenize).mulDiv(1 ether, ptShares),
            prop,
            1e15,
            "Deposit not made in proportion"
        );
    }

    function testAddLiquidityCustomPropsInit(
        uint8 underlying_decimals,
        uint8 ibt_decimals,
        uint256 prop,
        uint256 underlyingAmount
    ) public {
        // deploy the protocol with new decimals
        underlying_decimals = uint8(bound(underlying_decimals, MIN_DECIMALS, MAX_DECIMALS));
        ibt_decimals = uint8(bound(ibt_decimals, underlying_decimals, MAX_DECIMALS));
        super.deployProtocol(underlying_decimals, ibt_decimals, address(factory), curvePoolParams);

        // Remove all liquidity before testing
        vm.prank(address(this));
        uint256[] memory minAmounts = new uint256[](2);
        curvePool.remove_liquidity(IERC20(address(curvePool)).totalSupply(), minAmounts);

        // Define the amounts
        underlyingAmount = bound(underlyingAmount, 1 * UNDERLYING_UNIT, 100_000 * UNDERLYING_UNIT);
        prop = bound(prop, MIN_PROP, MAX_PROP);

        // mint underlying to the mock user
        underlying.mint(MOCK_ADDR_1, underlyingAmount);

        // deposit the underlying into the ibt
        vm.startPrank(MOCK_ADDR_1);
        underlying.approve(address(ibt), underlyingAmount);
        uint256 shares = ibt.deposit(underlyingAmount, MOCK_ADDR_1);

        // build the commands
        (bytes memory commands, bytes[] memory inputs) = _buildRouterAddLiqCustomExec(
            address(curvePool),
            shares,
            prop,
            1,
            MOCK_ADDR_1
        );

        // execute the commands
        ibt.approve(address(router), shares);
        router.execute(commands, inputs);

        uint256 balances_ibt = curvePool.balances(0);
        uint256 balances_pt = curvePool.balances(1);

        assertApproxEqRel(
            balances_ibt.mulDiv(CurvePoolUtil.CURVE_UNIT, balances_pt),
            prop,
            1e15,
            "Deposit not made in proportion"
        );
    }

    function _buildRouterAddLiqCustomExec(
        address curvePool,
        uint256 ibts,
        uint256 prop,
        uint256 minMintAmount,
        address receiver
    ) internal view returns (bytes memory commands, bytes[] memory inputs) {
        address ibt = ICurvePool(curvePool).coins(0);
        commands = abi.encodePacked(
            bytes1(uint8(Commands.TRANSFER_FROM)),
            bytes1(uint8(Commands.CURVE_SPLIT_IBT_LIQUIDITY_CUSTOM_PROP_SNG)),
            bytes1(uint8(Commands.CURVE_ADD_LIQUIDITY_SNG))
        );
        inputs = new bytes[](3);
        inputs[0] = abi.encode(ibt, ibts);
        inputs[1] = abi.encode(
            curvePool,
            Constants.CONTRACT_BALANCE,
            prop,
            Constants.ADDRESS_THIS,
            receiver,
            0
        );
        uint256[] memory amounts_for_input = new uint256[](2);
        amounts_for_input[0] = Constants.CONTRACT_BALANCE;
        amounts_for_input[1] = Constants.CONTRACT_BALANCE;
        inputs[2] = abi.encode(curvePool, amounts_for_input, minMintAmount, receiver);
        return (commands, inputs);
    }
}
