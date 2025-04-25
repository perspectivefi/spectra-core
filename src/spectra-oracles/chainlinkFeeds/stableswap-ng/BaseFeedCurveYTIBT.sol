// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.20;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {CurveOracleLib} from "src/libraries/CurveOracleLib.sol";
import {BaseOracleCurveYT} from "src/spectra-oracles/oracles/BaseOracleCurveYT.sol";

/**
 * @title BaseFeedCurveYTIBT contract
 * @author Spectra Finance
 * @notice Base contract to implement the AggregatorV3Interface feed for the YT price expressed in IBT
 */
abstract contract BaseFeedCurveYTIBTSNG is BaseOracleCurveYT {
    constructor(address _pt, address _pool) BaseOracleCurveYT(_pt, _pool) {}

    /* INTERNAL
     *****************************************************************************************************************/

    function _YTPrice() internal view override returns (uint256) {
        return CurveOracleLib.getYTToIBTRateSNG(pool);
    }

    /* AGGREGATORV3INTERFACE
     *****************************************************************************************************************/

    function decimals() external view override returns (uint8) {
        return IERC20Metadata(ibt).decimals();
    }
}
