// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../../../src/libraries/RateAdjustmentMath.sol";
import "../../../src/libraries/LogExpMath.sol";
import "openzeppelin-math/Math.sol";

contract RateAdjustmentMathTest is Test {
    using Math for uint256;

    // constants
    uint256 private constant YEAR = 365 * 24 * 3600;
    uint256 private constant UNIT = 10 ** 18;
    uint256 private constant IMPLIED_RATE_PRECISION = 10 ** 14; // @dev allow 1 bps quote mistake

    // errors
    error PTExpired();

    /**
     * @notice the rate oracle reports initial price at beginning of the term
     * @param initial_price initial price of the pt
     */
    function testInitialValue(uint256 initial_price) public {
        initial_price = bound(initial_price, 5 * 10 ** 15, UNIT - 1);
        uint256 initial_timestamp = 0;
        uint256 current_timestamp = 0;
        uint256 expiry_timestamp = YEAR;

        uint256 value = RateAdjustmentMath.getAdjustmentFactor(
            initial_timestamp,
            current_timestamp,
            expiry_timestamp,
            initial_price,
            UNIT
        );

        assertApproxEqAbs(value, initial_price, 10, "incorrect maturity value");
    }

    /**
     * @notice the rate oracle reports unit price at beginning of the term
     * @param initial_price initial price of the pt
     */
    function testExpiryValue(uint256 initial_price) public {
        initial_price = bound(initial_price, 5 * 10 ** 15, UNIT - 1);
        uint256 initial_timestamp = 0;
        uint256 current_timestamp = YEAR;
        uint256 expiry_timestamp = YEAR;

        uint256 value = RateAdjustmentMath.getAdjustmentFactor(
            initial_timestamp,
            current_timestamp,
            expiry_timestamp,
            initial_price,
            UNIT
        );

        assertApproxEqAbs(value, UNIT, 1, "incorrect maturity value");
    }

    /**
     * @notice test to verify that the implied rate reported is correct
     */
    function testImpliedRateSimple() public {
        uint256 initial_timestamp = 0;
        uint256 current_timestamp = YEAR / 2;
        uint256 expiry_timestamp = YEAR;
        uint256 target_rate = 2 * 10 ** 18;
        uint256 initial_price = 5 * 10 ** 17;
        uint256 value = RateAdjustmentMath.getAdjustmentFactor(
            initial_timestamp,
            current_timestamp,
            expiry_timestamp,
            initial_price,
            UNIT
        );

        assertApproxEqAbs(
            _implied_rate(value, current_timestamp, expiry_timestamp),
            target_rate,
            100
        );
    }

    /**
     * @notice the rate oracle maintains the implied rate constant when no trades occur
     * @param initial_price initial price of the pt
     * @param current_timestamp current moment in the term
     * @param expiry_timestamp expiry of the pt
     */
    function testImpliedRateConstantNoTrade(
        uint256 initial_price,
        uint256 current_timestamp,
        uint256 expiry_timestamp
    ) public {
        uint256 initial_timestamp = 0;

        expiry_timestamp = bound(expiry_timestamp, YEAR / 12, 4 * YEAR);
        current_timestamp = bound(current_timestamp, initial_timestamp, expiry_timestamp - 1);
        initial_price = bound(initial_price, 5 * 10 ** 15, UNIT - 1);

        uint256 implied_rate = _implied_rate(initial_price, 0, expiry_timestamp);
        uint256 value = RateAdjustmentMath.getAdjustmentFactor(
            initial_timestamp,
            current_timestamp,
            expiry_timestamp,
            initial_price,
            UNIT
        );

        assertApproxEqRel(
            _implied_rate(value, current_timestamp, expiry_timestamp),
            implied_rate,
            IMPLIED_RATE_PRECISION
        );
    }

    /**
     * @notice calculates the implied rate given the exchange rate
     * @param price Current price of PT in IBT
     * @param current_timestamp Current timestamp
     * @param expiry Expiry timestamp of the PT
     */
    function _implied_rate(
        uint256 price,
        uint256 current_timestamp,
        uint256 expiry
    ) private pure returns (uint256) {
        if (current_timestamp >= expiry) {
            revert PTExpired();
        }
        uint256 exp = YEAR.mulDiv(UNIT, expiry - current_timestamp);
        return LogExpMath.pow(UNIT.mulDiv(UNIT, price), exp);
    }
}
