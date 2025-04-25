// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/factory/Factory.sol";

import "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

// script to deploy a Curve Pool
contract CurvePoolScript is Script {
    address private testRes;
    address private factory;
    address private pt;
    address private ibt;
    IFactory.CurvePoolParams private curvePoolParams;
    uint256 private initialLiquidityInIBT;
    uint256 private minPTShares;
    bool private forTest;

    function run() public {
        vm.startBroadcast();
        string memory deploymentNetwork = vm.envString("DEPLOYMENT_NETWORK");
        if (bytes(deploymentNetwork).length == 0) {
            revert("DEPLOYMENT_NETWORK is not set in .env file");
        }
        if (forTest) {
            IERC20(ibt).approve(factory, initialLiquidityInIBT);
            address curvePool = IFactory(factory).deployCurvePool(
                pt,
                curvePoolParams,
                initialLiquidityInIBT,
                minPTShares
            );

            console.log("Curve pool deployed deployed at", curvePool);
            testRes = curvePool;
        } else {
            IFactory.CurvePoolParams memory data;

            // get factory from .env
            string memory envVar = string.concat("FACTORY_ADDR_", deploymentNetwork);
            if (bytes(vm.envString(envVar)).length == 0) {
                revert(string.concat(envVar, " is not set in .env file"));
            }
            factory = vm.envAddress(envVar);

            // get IBT from .env
            envVar = string.concat("IBT_ADDR_", deploymentNetwork);
            if (bytes(vm.envString(envVar)).length == 0) {
                revert(string.concat(envVar, " is not set in .env file"));
            }
            ibt = vm.envAddress(envVar);

            // get PT beacon proxy from .env
            envVar = string.concat("PT_BEACON_PROXY_ADDR_", deploymentNetwork);
            if (bytes(vm.envString(envVar)).length == 0) {
                revert(string.concat(envVar, " is not set in .env file"));
            }
            pt = vm.envAddress(envVar);

            // get Curve Pool A from .env
            envVar = string.concat("CURVE_POOL_PARAM_A_", deploymentNetwork);
            if (bytes(vm.envString(envVar)).length == 0) {
                revert(string.concat(envVar, " is not set in .env file"));
            }
            data.A = vm.envUint(envVar);
            if (data.A == 0) {
                revert(string.concat(envVar, " cannot be 0"));
            }

            // get Curve Pool gamma from .env
            envVar = string.concat("CURVE_POOL_PARAM_GAMMA_", deploymentNetwork);
            if (bytes(vm.envString(envVar)).length == 0) {
                revert(string.concat(envVar, " is not set in .env file"));
            }
            data.gamma = vm.envUint(envVar);
            if (data.gamma == 0) {
                revert(string.concat(envVar, " cannot be 0"));
            }

            // get Curve Pool mid_fee from .env
            envVar = string.concat("CURVE_POOL_PARAM_MID_FEE_", deploymentNetwork);
            if (bytes(vm.envString(envVar)).length == 0) {
                revert(string.concat(envVar, " is not set in .env file"));
            }
            data.mid_fee = vm.envUint(envVar);
            if (data.mid_fee == 0) {
                revert(string.concat(envVar, " cannot be 0"));
            }

            // get Curve Pool out_fee from .env
            envVar = string.concat("CURVE_POOL_PARAM_OUT_FEE_", deploymentNetwork);
            if (bytes(vm.envString(envVar)).length == 0) {
                revert(string.concat(envVar, " is not set in .env file"));
            }
            data.out_fee = vm.envUint(envVar);
            if (data.out_fee == 0) {
                revert(string.concat(envVar, " cannot be 0"));
            }

            // get Curve Pool fee_gamma from .env
            envVar = string.concat("CURVE_POOL_PARAM_FEE_GAMMA_", deploymentNetwork);
            if (bytes(vm.envString(envVar)).length == 0) {
                revert(string.concat(envVar, " is not set in .env file"));
            }
            data.fee_gamma = vm.envUint(envVar);
            if (data.fee_gamma == 0) {
                revert(string.concat(envVar, " cannot be 0"));
            }

            // get Curve Pool allowed_extra_profit from .env
            envVar = string.concat("CURVE_POOL_PARAM_ALLOWED_EXTRA_PROFIT_", deploymentNetwork);
            if (bytes(vm.envString(envVar)).length == 0) {
                revert(string.concat(envVar, " is not set in .env file"));
            }
            data.allowed_extra_profit = vm.envUint(envVar);
            if (data.allowed_extra_profit == 0) {
                revert(string.concat(envVar, " cannot be 0"));
            }

            // get Curve Pool adjustment_step from .env
            envVar = string.concat("CURVE_POOL_PARAM_ADJUSTMENT_STEP_", deploymentNetwork);
            if (bytes(vm.envString(envVar)).length == 0) {
                revert(string.concat(envVar, " is not set in .env file"));
            }
            data.adjustment_step = vm.envUint(envVar);
            if (data.adjustment_step == 0) {
                revert(string.concat(envVar, " cannot be 0"));
            }

            // get Curve Pool ma_exp_time from .env
            envVar = string.concat("CURVE_POOL_PARAM_MA_EXP_TIME_", deploymentNetwork);
            if (bytes(vm.envString(envVar)).length == 0) {
                revert(string.concat(envVar, " is not set in .env file"));
            }
            data.ma_exp_time = vm.envUint(envVar);
            if (data.ma_exp_time == 0) {
                revert(string.concat(envVar, " cannot be 0"));
            }

            // get Curve Pool initial_price from .env
            envVar = string.concat("CURVE_POOL_PARAM_INITIAL_PRICE_", deploymentNetwork);
            if (bytes(vm.envString(envVar)).length == 0) {
                revert(string.concat(envVar, " is not set in .env file"));
            }
            data.initial_price = vm.envUint(envVar);
            if (data.initial_price == 0) {
                revert(string.concat(envVar, " cannot be 0"));
            }

            // get initial liquidity in IBT from .env
            envVar = string.concat("INITIAL_LIQUIDITY_IBT_", deploymentNetwork);
            if (bytes(vm.envString(envVar)).length == 0) {
                revert(string.concat(envVar, " is not set in .env file"));
            }
            initialLiquidityInIBT = vm.envUint(envVar);

            // get minimum allowed shares from deposit in PT from .env
            envVar = string.concat("MIN_PT_SHARES_", deploymentNetwork);
            if (bytes(vm.envString(envVar)).length == 0) {
                revert(string.concat(envVar, " is not set in .env file"));
            }
            minPTShares = vm.envUint(envVar);
            IERC20(ibt).approve(factory, initialLiquidityInIBT);
            address curvePool = IFactory(factory).deployCurvePool(
                pt,
                data,
                initialLiquidityInIBT,
                minPTShares
            );
            console.log("Curve pool deployed deployed at", curvePool);
        }
        vm.stopBroadcast();
    }

    function deployForTest(
        address _factory,
        address _ibt,
        address _pt,
        IFactory.CurvePoolParams memory _curvePoolData,
        uint256 _initialLiquidityInIBT,
        uint256 _minPTShares
    ) public returns (address _testRes) {
        forTest = true;
        factory = _factory;
        ibt = _ibt;
        pt = _pt;
        curvePoolParams = _curvePoolData;
        initialLiquidityInIBT = _initialLiquidityInIBT;
        minPTShares = _minPTShares;
        run();
        forTest = false;
        _testRes = testRes;
        testRes = address(0);
        factory = address(0);
        ibt = address(0);
        pt = address(0);
        curvePoolParams = IFactory.CurvePoolParams(0, 0, 0, 0, 0, 0, 0, 0, 0);
        initialLiquidityInIBT = 0;
        minPTShares = 0;
    }
}
