// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";

import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";

import {LiquidationHelperCommon} from "./LiquidationHelperCommon.sol";

/*
    FOUNDRY_PROFILE=core-test forge test -vv --ffi --mc LiquidationHelper1TokenTest
*/
contract LiquidationHelper2TokensTest is LiquidationHelperCommon {
    uint256 constant LIQUIDATION_UNDERESTIMATION = 2;

    function setUp() public {
        vm.label(BORROWER, "BORROWER");
        siloConfig = _setUpLocalFixture();

        _depositForBorrow(DEBT + COLLATERAL, makeAddr("depositor"));
        _depositCollateral(COLLATERAL, BORROWER, TWO_ASSETS);
        _borrow(DEBT, BORROWER, TWO_ASSETS);

        ISiloConfig.ConfigData memory collateralConfig = siloConfig.getConfig(address(silo0));

        assertEq(collateralConfig.liquidationFee, 0.05e18, "liquidationFee");

        liquidationData.user = BORROWER;
        liquidationData.hook = partialLiquidation;
        liquidationData.collateralAsset = address(token0);

        _flashLoanFrom = silo1;
        _debtAsset = address(token1);
    }

    /*
    FOUNDRY_PROFILE=core-test forge test --ffi --mt test_executeLiquidation_2_tokens -vvv
    */
    function test_executeLiquidation_2_tokens(uint64 _addTimestamp) public {
        vm.warp(block.timestamp + _addTimestamp);

        (uint256 collateralToLiquidate, uint256 debtToRepay,) = partialLiquidation.maxLiquidation(BORROWER);

        emit log_named_decimal_uint("collateralToLiquidate", collateralToLiquidate, 18);
        emit log_named_decimal_uint("          debtToRepay", debtToRepay, 18);
        vm.assume(debtToRepay != 0);

        uint256 flashFee = silo1.flashFee(address(token1), debtToRepay);
        emit log_named_decimal_uint("             flashFee", flashFee, 18);

        // we reject cases with invalid config or not profitable
        vm.assume(collateralToLiquidate >= debtToRepay + flashFee);

        // "swap mock", so we can repay flashloan
        token1.mint(address(LIQUIDATION_HELPER), debtToRepay + flashFee);

        assertEq(token0.balanceOf(TOKENS_RECEIVER), 0, "no collateral before liquidation");

        (uint256 withdrawCollateral, uint256 repayDebtAssets) = _executeLiquidation(debtToRepay);

        assertEq(
            collateralToLiquidate,
            withdrawCollateral - LIQUIDATION_UNDERESTIMATION,
            "collateralToLiquidate == withdrawCollateral"
        );

        assertEq(debtToRepay, repayDebtAssets, "debtToRepay == repayDebtAssets");

        emit log_named_decimal_uint("token0.balanceOf(TOKENS_RECEIVER)", token0.balanceOf(TOKENS_RECEIVER), 18);
        emit log_named_decimal_uint("token1.balanceOf(TOKENS_RECEIVER)", token1.balanceOf(TOKENS_RECEIVER), 18);

        assertLe(
            token0.balanceOf(TOKENS_RECEIVER),
            LIQUIDATION_UNDERESTIMATION,
            "expect full collateral to be swapped"
        );

        // TODO, because we not swapping anything, we not transferring debt token
        // this assertion can be turn on once we add swap to it
//        assertEq(
//            token1.balanceOf(TOKENS_RECEIVER),
//            withdrawCollateral - repayDebtAssets - flashFee + LIQUIDATION_UNDERESTIMATION,
//            "expect debt to be transfer (price is 1:1)"
//        );

        // TODO, because we not swapping anything, we not transferring debt token
        // so contract will have debt, this assertion can be turn on once we add swap to the test
        // _assertAddressDoesNotHaveTokens(address(LIQUIDATION_HELPER));
        _assertAddressHasNoSTokens(silo0, TOKENS_RECEIVER);
        _assertAddressHasNoSTokens(silo1, TOKENS_RECEIVER);
    }
}
