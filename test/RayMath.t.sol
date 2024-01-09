// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "../src/libraries/RayMath.sol";
import "openzeppelin-math/Math.sol";

contract RayMathHarness {
    using RayMath for uint256;

    function toRay(uint256 a, uint256 decimals) public pure returns (uint256 b) {
        return RayMath.toRay(a, decimals);
    }

    function fromRay(uint256 a, uint256 decimals) public pure returns (uint256 b) {
        return RayMath.fromRay(a, decimals);
    }

    function fromRay(uint256 a, uint256 decimals, bool roundUp) public pure returns (uint256 b) {
        return RayMath.fromRay(a, decimals, roundUp);
    }
}

error TestError();

contract RayMathTest is Test {
    uint256 private constant MIN_DECIMALS = 6;
    uint256 private constant MAX_DECIMALS = 18;
    uint256 private constant RAY_UNIT = 1e27;
    RayMathHarness private wadRayUtil;

    function setUp() public {
        wadRayUtil = new RayMathHarness();
    }

    function testToRayFuzz(uint256 a, uint256 decimals) public {
        decimals = bound(decimals, MIN_DECIMALS, MAX_DECIMALS);
        (bool overflow, uint256 result) = Math.tryDiv(2 ** 256 - 1, 10 ** (27 - decimals));
        if (!overflow) {
            revert TestError();
        }
        a = bound(a, 0, result);
        uint256 aWad = wadRayUtil.toRay(a, uint256(decimals));
        uint256 expected;
        (overflow, expected) = Math.tryDiv(aWad, 10 ** (27 - decimals));
        assertEq(expected, a);

        uint256 anyFromWad = wadRayUtil.fromRay(aWad, uint256(decimals));
        assertEq(anyFromWad, a);
    }

    function testToRayOverflowFuzz(uint256 a, uint256 decimals) public {
        decimals = bound(decimals, MIN_DECIMALS, MAX_DECIMALS);
        (bool overflow, uint256 result) = Math.tryDiv(2 ** 256 - 1, 10 ** (27 - decimals));
        if (!overflow) {
            revert TestError();
        }
        a = bound(a, result + 1, 2 ** 256 - 1);
        vm.expectRevert();
        wadRayUtil.toRay(a, uint256(decimals));
    }

    function testToRayCompute() public {
        uint256 decimals = 18;
        uint256 a = 1000000000000000000;
        uint256 aWad = wadRayUtil.toRay(a, decimals);
        assertEq(aWad, 1000000000000000000000000000);
    }

    function testfromRayWithRounding() public {
        uint256 decimals = 18;
        uint256 a = 1;
        uint256 aWad = wadRayUtil.fromRay(a, decimals, true);
        assertEq(aWad, 1);
        a = 100000000;
        aWad = wadRayUtil.fromRay(a, decimals, true);
        assertEq(aWad, 1);
        a = 7000000000;
        aWad = wadRayUtil.fromRay(a, decimals, true);
        assertEq(aWad, 7);
        a = 7000000001;
        aWad = wadRayUtil.fromRay(a, decimals, true);
        assertEq(aWad, 8);
        a = 7999999999;
        aWad = wadRayUtil.fromRay(a, decimals, true);
        assertEq(aWad, 8);
        a = 7999999999;
        aWad = wadRayUtil.fromRay(a, decimals, false);
        assertEq(aWad, 7);
        aWad = wadRayUtil.fromRay(a, decimals);
        assertEq(aWad, 7);
    }

    function testFuzzFromRay(uint256 a, uint256 decimals, bool roundUp) public {
        // Still test solidity against yul
        decimals = bound(decimals, MIN_DECIMALS, MAX_DECIMALS);

        uint256 expected = computeExpected(a, decimals, roundUp);
        uint256 result = wadRayUtil.fromRay(a, decimals, roundUp);

        assertEq(result, expected, "Mismatch between expected and actual results");
    }

    function computeExpected(
        uint256 a,
        uint256 decimals,
        bool roundUp
    ) internal pure returns (uint256) {
        uint256 decimalsRatio = 10 ** (27 - decimals);
        uint256 rawResult = a / decimalsRatio;
        if (roundUp && a % decimalsRatio != 0) {
            rawResult += 1;
        }
        return rawResult;
    }

    function testDoubleRoundingScenarioFuzz(
        uint256 decimals,
        uint256 a,
        uint256 b,
        uint256 c
    ) public {
        vm.assume(c != 0);
        decimals = bound(decimals, MIN_DECIMALS, MAX_DECIMALS);
        a = bound(a, 0, 499999999999999999999999999);
        b = bound(b, 0, 499999999999999999999999999);

        uint256 resultWithoutRoundUp = wadRayUtil.fromRay(Math.mulDiv(a, b, c), decimals);
        uint256 resultWithRoundUp = wadRayUtil.fromRay(
            Math.mulDiv(a, b, c, Math.Rounding.Ceil),
            decimals,
            true
        );

        // Check the absolute difference
        uint256 difference = resultWithRoundUp > resultWithoutRoundUp
            ? resultWithRoundUp - resultWithoutRoundUp
            : resultWithoutRoundUp - resultWithRoundUp;

        assertTrue(difference < 2, "Unwanted double rounding detected");
    }
}
