// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.20;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "src/spectra-oracles/oracles/BaseOracleCurvePT.sol";
import {CurveOracleLib} from "src/libraries/CurveOracleLib.sol";

/**
 * @title BaseFeedCurvePTIBT contract
 * @author Spectra Finance
 * @notice Base contract to implement the AggregatorV3Interface feed for the PT
 */
abstract contract BaseFeedCurvePTIBT is BaseOracleCurvePT {
    constructor(address _pt, address _pool) BaseOracleCurvePT(_pt, _pool) {}

    /* INTERNAL
     *****************************************************************************************************************/

    function _PTPrice() internal view override returns (uint256) {
        return CurveOracleLib.getPTToIBTRate(pool);
    }

    /* AGGREGATORV3INTERFACE
     *****************************************************************************************************************/

    function decimals() external view override returns (uint8) {
        return IERC20Metadata(ibt).decimals();
    }
}
