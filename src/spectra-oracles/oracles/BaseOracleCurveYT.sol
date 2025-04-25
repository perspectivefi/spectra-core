// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.20;

import {BaseOracle} from "src/spectra-oracles/oracles/BaseOracle.sol";

/**
 * @title BaseOracleCurveYT contract
 * @author Spectra Finance
 * @notice A base oracle implementation for the YT
 */
abstract contract BaseOracleCurveYT is BaseOracle {
    constructor(address _pt, address _pool) BaseOracle(_pt, _pool) {}

    /* INTERNAL
     *****************************************************************************************************************/

    function _getQuoteAmount() internal view override returns (uint256) {
        return _YTPrice();
    }

    function _YTPrice() internal view virtual returns (uint256);
}
