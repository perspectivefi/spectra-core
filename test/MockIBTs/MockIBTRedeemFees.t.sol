// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "./MockIBTCustomFeesPropertyChecks.t.sol";
import "../../src/mocks/MockIBTCustomRedeemFeesThreshold.sol";

contract MockIBTRedeemFeesTests is MockIBTFees {
    function testDepositInIBTFuzz(uint8 _underlyingDecimals, uint8 _ibtDecimals) public {
        uint8 underlyingDecimals = uint8(
            bound(uint256(_underlyingDecimals), uint256(MIN_DECIMALS), uint256(MAX_DECIMALS))
        );
        uint8 ibtDecimals = uint8(
            bound(uint256(_ibtDecimals), uint256(underlyingDecimals), uint256(MAX_DECIMALS))
        );

        IBT_UNIT = 10 ** ibtDecimals;
        ASSET_UNIT = 10 ** underlyingDecimals;
        _deployProtocol(
            underlyingDecimals,
            ibtDecimals,
            TOKENIZATION_FEE,
            YIELD_FEE,
            PT_FLASH_LOAN_FEE,
            IBT_UNIT, // threshold
            IBT_UNIT / 10, // lowFee
            IBT_UNIT / 20 // highFee
        );

        MockUnderlyingCustomDecimals(_underlying_).approve(ibt, 2 * ASSET_UNIT);
        MockIBTCustomFeesThreshold(ibt).deposit(2 * ASSET_UNIT, address(this));
        uint256 rate1 = MockIBTCustomFeesThreshold(ibt).previewRedeem(IBT_UNIT);
        uint256 rate2 = MockIBTCustomFeesThreshold(ibt).previewRedeem(2 * IBT_UNIT);
        assertLt(rate1, Math.mulDiv(rate2, 1, 2), "redeem is linear");
    }

    function _deployProtocol(
        uint8 _underlyingDecimals,
        uint8 _ibtDecimals,
        uint256 _tokenizationFee,
        uint256 _yieldFee,
        uint256 _ptFlashLoanFee,
        uint256 _threshold,
        uint256 _lowFee,
        uint256 _highFee
    ) internal override {
        _underlying_ = address(new MockUnderlyingCustomDecimals());
        MockUnderlyingCustomDecimals(_underlying_).initialize(
            "MOCK UNDERLYING",
            "MUDL",
            _underlyingDecimals
        );

        ibt = address(
            new MockIBTCustomFeesThreshold(
                "MOCK IBT",
                "MIBT",
                IERC20(_underlying_),
                _ibtDecimals,
                0, // rateChange
                _threshold,
                _lowFee,
                _highFee
            )
        );

        MockUnderlyingCustomDecimals(_underlying_).mint(address(this), ASSET_UNIT);
        MockUnderlyingCustomDecimals(_underlying_).approve(ibt, ASSET_UNIT);
        MockIBTCustomFeesThreshold(ibt).deposit(ASSET_UNIT, address(this));

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
