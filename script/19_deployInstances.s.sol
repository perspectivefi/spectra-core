// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "forge-std/Script.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";
import "../src/tokens/PrincipalToken.sol";
import "../src/tokens/YieldToken.sol";
import "../src/factory/Factory.sol";
import "../src/proxy/AMBeacon.sol";
import "../src/proxy/AMTransparentUpgradeableProxy.sol";
import "../src/proxy/AMProxyAdmin.sol";

// single script similar to scripts 10, 11 12
contract DeployInstancesScript is Script {
    // params passed as arguments for tests or read in .env otherwise
    address private ibt;
    uint256 private duration;
    uint256 private initialLiquidityInIBT;
    uint256 private minPTShares;

    // addresses returned in tests
    address private factory;
    address private pt;
    address private curvePool;

    bool private forTest;
    string private deploymentNetwork;

    // struct passed as input
    struct TestInputData {
        address _ibt;
        uint256 _duration;
        uint256 _initialLiquidityInIBT;
        uint256 _minPTShares;
    }

    // struct returned as output
    struct ReturnData {
        address _factory;
        address _pt;
        address _curvePool;
    }

    function run() public {
        vm.startBroadcast();

        deploymentNetwork = vm.envString("DEPLOYMENT_NETWORK");
        if (bytes(deploymentNetwork).length == 0) {
            revert("DEPLOYMENT_NETWORK is not set in .env file");
        }

        string memory envVar;

        // --- Deploy Principal Token, Curve Pool (script 07, 08) ---
        if (!forTest) {
            // get IBT from .env
            envVar = string.concat("IBT_ADDR_", deploymentNetwork);
            if (bytes(vm.envString(envVar)).length == 0) {
                revert(string.concat(envVar, " is not set in .env file"));
            }
            ibt = vm.envAddress(envVar);

            envVar = string.concat("FACTORY_ADDR_", deploymentNetwork);
            if (bytes(vm.envString(envVar)).length == 0) {
                revert(string.concat(envVar, " is not set in .env file"));
            }
            factory = vm.envAddress(envVar);

            // get PT duration from .env
            envVar = string.concat("DURATION_", deploymentNetwork);
            if (bytes(vm.envString(envVar)).length == 0) {
                revert(string.concat(envVar, " is not set in .env file"));
            }
            duration = vm.envUint(envVar);

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
        }

        IFactory.CurvePoolParams memory curvePoolParams;
        if (forTest) {
            curvePoolParams.A = 200000000;
            curvePoolParams.gamma = 100000000000000;
            curvePoolParams.mid_fee = 5000000;
            curvePoolParams.out_fee = 45000000;
            curvePoolParams.fee_gamma = 5000000000000000;
            curvePoolParams.allowed_extra_profit = 10000000000;
            curvePoolParams.adjustment_step = 5500000000000;
            curvePoolParams.ma_exp_time = 1200;
            curvePoolParams.initial_price = 1e18;
        } else {
            // get Curve Pool A from .env
            envVar = string.concat("CURVE_POOL_PARAM_A_", deploymentNetwork);
            if (bytes(vm.envString(envVar)).length == 0) {
                revert(string.concat(envVar, " is not set in .env file"));
            }
            curvePoolParams.A = vm.envUint(envVar);
            if (curvePoolParams.A == 0) {
                revert(string.concat(envVar, " cannot be 0"));
            }

            // get Curve Pool gamma from .env
            envVar = string.concat("CURVE_POOL_PARAM_GAMMA_", deploymentNetwork);
            if (bytes(vm.envString(envVar)).length == 0) {
                revert(string.concat(envVar, " is not set in .env file"));
            }
            curvePoolParams.gamma = vm.envUint(envVar);
            if (curvePoolParams.gamma == 0) {
                revert(string.concat(envVar, " cannot be 0"));
            }

            // get Curve Pool mid_fee from .env
            envVar = string.concat("CURVE_POOL_PARAM_MID_FEE_", deploymentNetwork);
            if (bytes(vm.envString(envVar)).length == 0) {
                revert(string.concat(envVar, " is not set in .env file"));
            }
            curvePoolParams.mid_fee = vm.envUint(envVar);
            if (curvePoolParams.mid_fee == 0) {
                revert(string.concat(envVar, " cannot be 0"));
            }

            // get Curve Pool out_fee from .env
            envVar = string.concat("CURVE_POOL_PARAM_OUT_FEE_", deploymentNetwork);
            if (bytes(vm.envString(envVar)).length == 0) {
                revert(string.concat(envVar, " is not set in .env file"));
            }
            curvePoolParams.out_fee = vm.envUint(envVar);
            if (curvePoolParams.out_fee == 0) {
                revert(string.concat(envVar, " cannot be 0"));
            }

            // get Curve Pool fee_gamma from .env
            envVar = string.concat("CURVE_POOL_PARAM_FEE_GAMMA_", deploymentNetwork);
            if (bytes(vm.envString(envVar)).length == 0) {
                revert(string.concat(envVar, " is not set in .env file"));
            }
            curvePoolParams.fee_gamma = vm.envUint(envVar);
            if (curvePoolParams.fee_gamma == 0) {
                revert(string.concat(envVar, " cannot be 0"));
            }

            // get Curve Pool allowed_extra_profit from .env
            envVar = string.concat("CURVE_POOL_PARAM_ALLOWED_EXTRA_PROFIT_", deploymentNetwork);
            if (bytes(vm.envString(envVar)).length == 0) {
                revert(string.concat(envVar, " is not set in .env file"));
            }
            curvePoolParams.allowed_extra_profit = vm.envUint(envVar);
            if (curvePoolParams.allowed_extra_profit == 0) {
                revert(string.concat(envVar, " cannot be 0"));
            }

            // get Curve Pool adjustment_step from .env
            envVar = string.concat("CURVE_POOL_PARAM_ADJUSTMENT_STEP_", deploymentNetwork);
            if (bytes(vm.envString(envVar)).length == 0) {
                revert(string.concat(envVar, " is not set in .env file"));
            }
            curvePoolParams.adjustment_step = vm.envUint(envVar);
            if (curvePoolParams.adjustment_step == 0) {
                revert(string.concat(envVar, " cannot be 0"));
            }

            // get Curve Pool ma_exp_time from .env
            envVar = string.concat("CURVE_POOL_PARAM_MA_EXP_TIME_", deploymentNetwork);
            if (bytes(vm.envString(envVar)).length == 0) {
                revert(string.concat(envVar, " is not set in .env file"));
            }
            curvePoolParams.ma_exp_time = vm.envUint(envVar);
            if (curvePoolParams.ma_exp_time == 0) {
                revert(string.concat(envVar, " cannot be 0"));
            }

            // get Curve Pool initial_price from .env
            envVar = string.concat("CURVE_POOL_PARAM_INITIAL_PRICE_", deploymentNetwork);
            if (bytes(vm.envString(envVar)).length == 0) {
                revert(string.concat(envVar, " is not set in .env file"));
            }
            curvePoolParams.initial_price = vm.envUint(envVar);
            if (curvePoolParams.initial_price == 0) {
                revert(string.concat(envVar, " cannot be 0"));
            }
        }
        console.log("factory: ", factory);
        // console.log("CurvePoolParams", curvePoolParams);
        console.log("duration: ", duration);
        console.log("ibt: ", ibt);
        IERC20(ibt).approve(factory, initialLiquidityInIBT);
        (pt, curvePool) = IFactory(factory).deployAll(
            ibt,
            duration,
            curvePoolParams,
            initialLiquidityInIBT,
            minPTShares
        );
        console.log("PrincipalToken deployed at", pt);
        console.log("YT deployed at", PrincipalToken(pt).getYT());
        console.log("CurvePool deployed at", curvePool);

        vm.stopBroadcast();
    }

    function deployForTest(
        TestInputData memory inputData
    ) public returns (ReturnData memory _returnData) {
        forTest = true;
        ibt = inputData._ibt;
        duration = inputData._duration;
        initialLiquidityInIBT = inputData._initialLiquidityInIBT;
        minPTShares = inputData._minPTShares;
        run();
        forTest = false;
        ibt = address(0);
        duration = 0;
        initialLiquidityInIBT = 0;
        minPTShares = 0;
        _returnData._factory = factory;
        _returnData._pt = pt;
        _returnData._curvePool = curvePool;
        factory = address(0);
        pt = address(0);
        curvePool = address(0);
    }
}
