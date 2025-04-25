// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.20;

import "../interfaces/IRateAdjustmentOracle.sol";
import "../interfaces/IPrincipalToken.sol";
import "../interfaces/IStableSwapNG.sol";
import "../libraries/RateAdjustmentMath.sol";
import "../libraries/RayMath.sol";
import "openzeppelin-math/Math.sol";
import "openzeppelin-contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";

contract RateAdjustmentOracle is AccessManagedUpgradeable, IRateAdjustmentOracle {
    using Math for uint256;
    using RayMath for uint256;

    // state
    address private curvePoolAddress;
    uint256 private startTime;
    uint256 private expiry;
    uint256 private initialPrice;

    // constants
    uint64 private constant POST_INIT_ID = 2;
    uint256 private constant ORACLE_DECIMALS = 18;

    /* EVENTS
     *****************************************************************************************************************/

    event InitialPriceChanged(
        uint256 indexed _previousInitialPrice,
        uint256 indexed _newInitialPrice
    );

    /* CONSTRUCTOR
     *****************************************************************************************************************/
    constructor() {
        _disableInitializers();
    }

    /* INITIALIZERS
     *****************************************************************************************************************/

    /** @dev See {IRateAdjustmentOracle-initialize}. */
    function initialize(address _initialAuthority) external initializer {
        if (_initialAuthority == address(0)) {
            revert AddressError();
        }
        __AccessManaged_init(_initialAuthority);
    }

    /** @dev See {IRateAdjustmentOracle-post_initialize}. */
    function post_initialize(
        uint256 _initialTimestamp,
        uint256 _expiry,
        uint256 _initialPrice,
        address _curvePoolAddress
    ) external override restricted reinitializer(POST_INIT_ID) {
        if (_curvePoolAddress == address(0)) {
            revert AddressError();
        }

        curvePoolAddress = _curvePoolAddress;
        startTime = _initialTimestamp;
        expiry = _expiry;
        initialPrice = _initialPrice;
    }

    /* FUNCTIONS
     *****************************************************************************************************************/

    /** @dev See {IRateAdjustmentOracle-value}. */
    function value() external view returns (uint256 rate) {
        if (curvePoolAddress == address(0)) {
            revert AddressesNotSet();
        }

        uint256 futurePTValue = IPrincipalToken(IStableSwapNG(curvePoolAddress).coins(1))
            .getPTRate()
            .fromRay(ORACLE_DECIMALS);

        // Get the adjustment factor
        rate = RateAdjustmentMath.getAdjustmentFactor(
            startTime,
            block.timestamp,
            expiry,
            initialPrice,
            futurePTValue
        );
    }

    /** @dev See {IRateAdjustmentOracle-setInitialPrice}. */
    function setInitialPrice(uint256 _newInitialPrice) external override restricted {
        emit InitialPriceChanged(initialPrice, _newInitialPrice);
        initialPrice = _newInitialPrice;
    }

    /** @dev See {IRateAdjustmentOracle-getInitialPrice}. */
    function getInitialPrice() external view returns (uint256) {
        return initialPrice;
    }

    /** @dev See {IRateAdjustmentOracle-getCurvePoolAddress}. */
    function getCurvePoolAddress() external view returns (address) {
        return curvePoolAddress;
    }

    /** @dev See {IRateAdjustmentOracle-getStartTime}. */
    function getStartTime() external view returns (uint256) {
        return startTime;
    }

    /** @dev See {IRateAdjustmentOracle-getExpiry}. */
    function getExpiry() external view returns (uint256) {
        return expiry;
    }
}
