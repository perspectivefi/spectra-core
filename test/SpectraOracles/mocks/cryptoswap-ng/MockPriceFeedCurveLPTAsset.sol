// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.20;

import {AggregatorV3Interface} from "src/interfaces/AggregatorV3Interface.sol";
import {BaseFeedCurveLPTAsset} from "src/spectra-oracles/chainlinkFeeds/cryptoswap-ng/BaseFeedCurveLPTAsset.sol";

/// @dev Mock Curve PT price feed that gives the LPT price in a provided IBT/PT Curve Pool in asset
contract MockPriceFeedCurveLPTAsset is BaseFeedCurveLPTAsset {
    string public constant description = "IBT/PT Curve Pool Oracle: LPT price in asset";

    /* CONSTRUCTOR
     *****************************************************************************************************************/
    /**
     * @notice Constructor for a Mock Price Feed of a Curve Pool (in asset)
     */
    constructor(address _pt, address _pool) BaseFeedCurveLPTAsset(_pt, _pool) {}
}
