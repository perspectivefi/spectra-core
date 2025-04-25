// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.20;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {BaseOracleCurveLPT} from "src/spectra-oracles/oracles/BaseOracleCurveLPT.sol";
import {CurveOracleLib} from "src/libraries/CurveOracleLib.sol";

/**
 * @title BaseFeedCurveLPTAsset contract
 * @author Spectra Finance
 * @notice Base contract to implement the AggregatorV3Interface feed for the LPT
 */
abstract contract BaseFeedCurveLPTAssetSNG is BaseOracleCurveLPT {
    constructor(address _pt, address _pool) BaseOracleCurveLPT(_pt, _pool) {}

    /* INTERNAL
     *****************************************************************************************************************/

    function _LPTPrice() internal view override returns (uint256) {
        return CurveOracleLib.getLPTToAssetRateSNG(pool);
    }

    /* AGGREGATORV3INTERFACE
     *****************************************************************************************************************/

    function decimals() external view override returns (uint8) {
        return IERC20Metadata(asset).decimals();
    }
}
