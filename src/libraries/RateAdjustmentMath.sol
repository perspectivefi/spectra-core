// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.20;

import "../interfaces/IRateAdjustmentOracle.sol";
import "openzeppelin-math/Math.sol";
import "./LogExpMath.sol";

library RateAdjustmentMath {
    using Math for uint256;

    uint256 public constant UNIT = 10 ** 18;

    /**
     * @notice Computes the rate of the Principal Token in underlying, given the initial discount in underlying.
     * @notice This rate is used internally in the Curve Pool for price adjustment. The oracle quotes the Principal Token
     * @notice price in unerlying according to P(t,T)=exp(-r(T-t)), where one assumes that the life of the instrument starts
     * @notice at 0, the current timestamp is t, and the expiry is T >= t. Here r represents the instantaneous forward rate.
     * @notice This formula is equivalent to what is given below.
     * @param initialTimestamp Timestamp of deployment of the Principal Token
     * @param currentTimestamp Current timestamp
     * @param expiryTimestamp Expiry Timestamp of the Principal Token
     * @param initialPrice Value of the Principal Token in underlying at the beginning of the term. Uniquely specifies
     * the discount and the initial implied rate.
     * @param futurePTValue Face value of a unit of Principal Token. Can be less than one unit of unerlying if the associated
     * ibt suffered from negative interest rates.
     * @return rate The rate of the PT in underlying at time current_timestamp
     */
    function getAdjustmentFactor(
        uint256 initialTimestamp,
        uint256 currentTimestamp,
        uint256 expiryTimestamp,
        uint256 initialPrice,
        uint256 futurePTValue
    ) internal pure returns (uint256 rate) {
        // The value of an expired bond does not change in further time.
        // The bond is redeemable for its face value.
        if (currentTimestamp > expiryTimestamp) {
            return futurePTValue;
        }

        // P(t,T) = ptRate * init_price ^ ((T-t)/(T-t0))
        uint256 exp = (expiryTimestamp - currentTimestamp).mulDiv(
            UNIT,
            expiryTimestamp - initialTimestamp
        );

        rate = futurePTValue.mulDiv(LogExpMath.pow(initialPrice, exp), UNIT);
    }
}
