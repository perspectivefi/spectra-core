// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.20;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IPrincipalToken} from "src/interfaces/IPrincipalToken.sol";
import {AggregatorV3Interface} from "src/interfaces/AggregatorV3Interface.sol";

/**
 * @title BaseOracle contract
 * @author Spectra Finance
 * @notice A base oracle implementation
 */
abstract contract BaseOracle is AggregatorV3Interface {
    address public pool;
    address public pt;
    uint256 public maturity;
    address public asset;
    address public ibt;

    constructor(address _pt, address _pool) {
        pool = _pool;
        pt = _pt;
        maturity = IPrincipalToken(_pt).maturity();
        asset = IPrincipalToken(_pt).underlying();
        ibt = IPrincipalToken(_pt).getIBT();
    }

    /* AggregatorV3Interface
     *****************************************************************************************************************/

    /** @dev See {AggregatorV3Interface-version}. */
    function version() external pure virtual returns (uint256) {
        return 1;
    }

    /** @dev See {AggregatorV3Interface-decimals}. */
    function decimals() external view virtual returns (uint8);

    /** @dev See {AggregatorV3Interface-getQuoteAmount}. */
    function _getQuoteAmount() internal view virtual returns (uint256);

    /** @dev See {AggregatorV3Interface-getRoundData}. */
    function getRoundData(
        uint80
    )
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (0, int256(_getQuoteAmount()), 0, 0, 0);
    }

    /** @dev See {AggregatorV3Interface-latestRoundData}. */
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (0, int256(_getQuoteAmount()), 0, 0, 0);
    }
}
