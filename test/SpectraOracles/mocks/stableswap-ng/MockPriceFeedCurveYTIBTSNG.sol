// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.20;

import {BaseFeedCurveYTIBTSNG} from "src/spectra-oracles/chainlinkFeeds/stableswap-ng/BaseFeedCurveYTIBT.sol";

/// @dev Mock Curve YT price feed that gives the YT price in a provided IBT/PT Curve Pool in IBT
contract MockPriceFeedCurveYTIBTSNG is BaseFeedCurveYTIBTSNG {
    string public constant description = "IBT/PT Curve Pool Oracle: YT price in IBT";

    /* CONSTRUCTOR
     *****************************************************************************************************************/
    /**
     * @notice Constructor for a Mock Price Feed of a Curve Pool (in IBT)
     */
    constructor(address _pt, address _pool) BaseFeedCurveYTIBTSNG(_pt, _pool) {}
}
