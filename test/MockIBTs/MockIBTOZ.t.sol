// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "./MockIBTCustomFeesPropertyChecks.t.sol";
import "../../src/mocks/MockIBTCustomDecimals.sol";

contract MockIBTRedeemFeesTests is MockIBTFees {
    function _deployProtocol(
        uint8 _underlyingDecimals,
        uint8 _ibtDecimals,
        uint256 _tokenizationFee,
        uint256 _yieldFee,
        uint256 _ptFlashLoanFee,
        uint256 /* _threshold */,
        uint256 /*_lowFee */,
        uint256 /*_highFee */
    ) internal override {
        _underlying_ = address(new MockUnderlyingCustomDecimals());
        MockUnderlyingCustomDecimals(_underlying_).initialize(
            "MOCK UNDERLYING",
            "MUDL",
            _underlyingDecimals
        );

        ibt = address(
            new MockIBTCustomDecimals("MOCK IBT", "MIBT", IERC20(_underlying_), _ibtDecimals)
        );

        MockUnderlyingCustomDecimals(_underlying_).mint(address(this), ASSET_UNIT);
        MockUnderlyingCustomDecimals(_underlying_).approve(ibt, ASSET_UNIT);
        MockIBTCustomDecimals(ibt).deposit(ASSET_UNIT, address(this));

        DeployAllScript.TestInputData memory inputData;
        inputData._ibt = ibt;
        inputData._duration = DURATION;
        inputData._curveFactoryAddress = curveFactoryAddress;
        inputData._deployer = scriptAdmin;
        inputData._tokenizationFee = _tokenizationFee;
        inputData._yieldFee = _yieldFee;
        inputData._ptFlashLoanFee = _ptFlashLoanFee;
        inputData._feeCollector = feeCollector;
        inputData._initialLiquidityInIBT = 0;
        inputData._minPTShares = 0;

        DeployAllScript.ReturnData memory returnData;
        returnData = deployAllScript.deployForTest(inputData);
        _pt_ = returnData._pt;
        _yt_ = IPrincipalToken(_pt_).getYT();

        MockUnderlyingCustomDecimals(_underlying_).mint(
            address(this),
            100_000_000_000_000 * ASSET_UNIT
        );
        // Mint assets to another user to seed tokens with a different user (address(1)) in some tests
        MockUnderlyingCustomDecimals(_underlying_).mint(
            address(1),
            100_000_000_000_000 * ASSET_UNIT
        );
    }
}
