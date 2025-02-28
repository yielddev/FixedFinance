// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";

import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";

import {ManualLiquidationHelperCommon} from "./ManualLiquidationHelperCommon.sol";

/*
    FOUNDRY_PROFILE=core-test forge test -vv --ffi --mc ManualLiquidationHelper2TokensSTokensTest
*/
contract ManualLiquidationHelper2TokensSTokensTest is ManualLiquidationHelperCommon {
    uint256 constant LIQUIDATION_UNDERESTIMATION = 2;

    function setUp() public {
        vm.label(BORROWER, "BORROWER");
        siloConfig = _setUpLocalFixture();

        _depositForBorrow(DEBT + COLLATERAL, makeAddr("depositor"));
        _depositCollateral(COLLATERAL, BORROWER, TWO_ASSETS);
        _borrow(DEBT, BORROWER, TWO_ASSETS);

        ISiloConfig.ConfigData memory collateralConfig = siloConfig.getConfig(address(silo0));

        assertEq(collateralConfig.liquidationFee, 0.05e18, "liquidationFee");

       _debtAsset = address(token1);
    }

    function _executeLiquidation() internal override {
        LIQUIDATION_HELPER.executeLiquidation(silo1, BORROWER, 2 ** 128, true, _tokenReceiver());
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

        token1.mint(address(this), debtToRepay);
        token1.approve(address(LIQUIDATION_HELPER), debtToRepay);

        assertEq(token0.balanceOf(_tokenReceiver()), 0, "no collateral before liquidation");

        _assertAddressHasNoSTokens(silo0, _tokenReceiver());
        _assertAddressHasNoSTokens(silo1, _tokenReceiver());

        _executeLiquidation();

        assertTrue(silo0.isSolvent(BORROWER), "borrower must be solvent after manual liquidation");

        uint256 withdrawCollateral = token0.balanceOf(_tokenReceiver());

        assertEq(token0.balanceOf(_tokenReceiver()), 0, "token0.balanceOf");
        assertEq(token1.balanceOf(_tokenReceiver()), 0, "token1.balanceOf");

        _assertAddressHasSTokens(silo0, _tokenReceiver());
    }
}
