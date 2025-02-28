// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";

import {Gas} from "./Gas.sol";

/*
forge test -vv --ffi --mt test_gas_ | grep -i '\[GAS\]'
*/
contract TransitionCollateralTest is Gas, Test {
    function setUp() public {
        _gasTestsInit();

        _depositCollateral(ASSETS * 2, BORROWER, TWO_ASSETS);
        _depositForBorrow(ASSETS, DEPOSITOR);
        _borrow(ASSETS, BORROWER, TWO_ASSETS);

        vm.warp(block.timestamp + 1);
    }

    /*
    FOUNDRY_PROFILE=core-test forge test -vv --ffi --mt test_gas_transitionCollateral
    */
    function test_gas_transitionCollateral() public {
        _action(
            BORROWER,
            address(silo0),
            abi.encodeCall(ISilo.transitionCollateral, (ASSETS, BORROWER, ISilo.CollateralType.Collateral)),
            "transitionCollateral (when debt)",
            292922 // 74K for interest
        );
    }
}
