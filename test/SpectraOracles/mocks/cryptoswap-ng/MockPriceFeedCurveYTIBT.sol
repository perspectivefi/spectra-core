// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.20;

import {AggregatorV3Interface} from "src/interfaces/AggregatorV3Interface.sol";
import {BaseFeedCurveYTIBT} from "src/spectra-oracles/chainlinkFeeds/cryptoswap-ng/BaseFeedCurveYTIBT.sol";

/// @dev Mock Curve YT price feed that gives the YT price in a provided IBT/PT Curve Pool in IBT
contract MockPriceFeedCurveYTIBT is BaseFeedCurveYTIBT {
    string public constant description = "IBT/PT Curve Pool Oracle: YT price in IBT";

    /* CONSTRUCTOR
     *****************************************************************************************************************/
    /**
     * @notice Constructor for a Mock Price Feed of a Curve Pool (in IBT)
     */
    constructor(address _pt, address _pool) BaseFeedCurveYTIBT(_pt, _pool) {}
}
