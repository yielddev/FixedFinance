// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Interfaces
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {ISilo} from "silo-core/contracts/Silo.sol";

// Libraries
import "forge-std/console.sol";

// Test Contracts
import {Actor} from "../../utils/Actor.sol";
import {BaseHandler} from "../../base/BaseHandler.t.sol";
import {TestERC20} from "../../utils/mocks/TestERC20.sol";

/// @title BorrowingHandler
/// @notice Handler test contract for a set of actions
contract BorrowingHandler is BaseHandler {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                      STATE VARIABLES                                      //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /* 
    
    E.g. num of active pools
    uint256 public activePools;
        
    */

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          ACTIONS                                          //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function borrow(uint256 _assets, uint8 i, uint8 j) external setup {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address receiver = _getRandomActor(i);

        address target = _getRandomSilo(j);

        _before();
        (success, returnData) =
            actor.proxy(target, abi.encodeWithSelector(ISilo.borrow.selector, _assets, receiver, address(actor)));

        // POST-CONDITIONS

        if (success) {
            _after();

            assertEq(
                defaultVarsBefore[target].debtAssets + _assets, defaultVarsAfter[target].debtAssets, LENDING_HSPOST_A
            );

            assertEq(defaultVarsAfter[target].balance + _assets, defaultVarsBefore[target].balance, BORROWING_HSPOST_O);
        }
    }

    function borrowSameAsset(uint256 _assets, uint8 i, uint8 j) external setup {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address receiver = _getRandomActor(i);

        address target = _getRandomSilo(j);

        _before();
        (success, returnData) = actor.proxy(
            target, abi.encodeWithSelector(ISilo.borrowSameAsset.selector, _assets, receiver, address(actor))
        );

        if (success) {
            _after();

            assertEq(
                defaultVarsBefore[target].debtAssets + _assets, defaultVarsAfter[target].debtAssets, LENDING_HSPOST_A
            );

            assertEq(defaultVarsAfter[target].balance + _assets, defaultVarsBefore[target].balance, BORROWING_HSPOST_O);
        }
    }

    function borrowShares(uint256 _shares, uint8 i, uint8 j) external setup {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address receiver = _getRandomActor(i);

        address target = _getRandomSilo(j);

        _before();
        (success, returnData) =
            actor.proxy(target, abi.encodeWithSelector(ISilo.borrowShares.selector, _shares, receiver, address(actor)));

        if (success) {
            _after();

            assertGe(
                defaultVarsAfter[target].userDebtShares, defaultVarsBefore[target].userDebtShares, BORROWING_HSPOST_Q
            );

            assertGe(defaultVarsAfter[target].userBalance, defaultVarsBefore[target].userBalance, BORROWING_HSPOST_R);
        }
    }

    function repay(uint256 _assets, uint8 i, uint8 j) external setup {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address borrower = _getRandomActor(i);

        _setTargetActor(borrower);

        address target = _getRandomSilo(j);

        uint256 maxRepayShares = ISilo(target).maxRepayShares(borrower);
        uint256 shares = ISilo(target).previewRepay(_assets);

        _before();
        (success, returnData) = actor.proxy(target, abi.encodeWithSelector(ISilo.repay.selector, _assets, borrower));

        if (success) {
            _after();

            assertGe(maxRepayShares + 1, shares, BORROWING_HSPOST_G);
            assertLe(defaultVarsAfter[target].userDebt, defaultVarsBefore[target].userDebt, BORROWING_HSPOST_H);
        }
    }

    function repayShares(uint256 _shares, uint8 i, uint8 j) external setup {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address borrower = _getRandomActor(i);

        _setTargetActor(borrower);

        address target = _getRandomSilo(j);

        uint256 maxRepayShares = ISilo(target).maxRepayShares(borrower);

        _before();
        (success, returnData) =
            actor.proxy(target, abi.encodeWithSelector(ISilo.repayShares.selector, _shares, borrower));

        if (success) {
            _after();

            if (_shares >= maxRepayShares) {
                assertEq(IERC20(siloConfig.getDebtSilo(borrower)).balanceOf(borrower), 0, BORROWING_HSPOST_B);
            }
            assertGe(maxRepayShares + 1, _shares, BORROWING_HSPOST_G);
            assertLe(defaultVarsAfter[target].userDebt, defaultVarsBefore[target].userDebt, BORROWING_HSPOST_H);
        }
    }

    function switchCollateralToThisSilo(uint8 i) external setup {
        bool success;
        bytes memory returnData;

        address target = _getRandomSilo(i);

        _before();
        (success, returnData) = actor.proxy(target, abi.encodeWithSelector(ISilo.switchCollateralToThisSilo.selector));

        if (success) {
            _after();
        }
    }

    function transitionCollateral(uint256 _shares, uint8 i, uint8 j, uint8 k) external setup {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address owner = _getRandomActor(i);

        _setTargetActor(owner);

        address target = _getRandomSilo(j);

        ISilo.CollateralType _collateralType = ISilo.CollateralType(k % 2);

        uint256 liquidity = ISilo(target).getLiquidity();

        (uint256 collateralAssets,) = ISilo(target).getCollateralAndDebtTotalsStorage();

        uint256 _assets = ISilo(target).convertToAssets(
            _shares,
            (_collateralType == ISilo.CollateralType.Protected)
                ? ISilo.AssetType.Protected
                : ISilo.AssetType.Collateral
        );

        _before();
        (success, returnData) = actor.proxy(
            target, abi.encodeWithSelector(ISilo.transitionCollateral.selector, _shares, owner, _collateralType)
        );

        // POST-CONDITIONS

        if (defaultVarsBefore[target].isSolvent && _collateralType == ISilo.CollateralType.Protected) {
            if (_shares > 0) {
                assertTrue(success, BORROWING_HSPOST_L);
            }
        }

        if (success) {
            _after();

            if (_collateralType != ISilo.CollateralType.Protected) {
                assertGe(liquidity, _assets, LENDING_HSPOST_D);
            }
            assertApproxEqAbs(defaultVarsAfter[target].userAssets, defaultVarsBefore[target].userAssets, 2 wei, BORROWING_HSPOST_J);
        }
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                         OWNER ACTIONS                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          PROPERTIES                                       //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function assert_BORROWING_HSPOST_D(uint8 i, uint8 j) external setup {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address borrower = _getRandomActor(i);

        address target = _getRandomSilo(j);

        uint256 debtAmount = ISilo(target).maxRepay(borrower);

        (, address debtAsset) = siloConfig.getDebtShareTokenAndAsset(target);

        if (debtAmount > IERC20(debtAsset).balanceOf(address(actor))) {
            TestERC20(debtAsset).mint(address(actor), debtAmount - IERC20(debtAsset).balanceOf(address(actor)));
        }

        _before();
        (success, returnData) = actor.proxy(target, abi.encodeWithSelector(ISilo.repay.selector, debtAmount, borrower));

        if (debtAmount > 0) {
            assertTrue(success, BORROWING_HSPOST_D);
            assertEq(ISilo(target).maxRepay(borrower), 0, BORROWING_HSPOST_D);
        }

        if (success) {
            _after();
        }
    }

    function assertBORROWING_HSPOST_F(uint8 i, uint8 j) external setup {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address receiver = _getRandomActor(i);

        address target = _getRandomSilo(j);

        uint256 maxBorrow = ISilo(target).maxBorrow(address(actor));

        _before();
        (success, returnData) =
            actor.proxy(target, abi.encodeWithSelector(ISilo.borrow.selector, maxBorrow, receiver, address(actor)));

        if (maxBorrow > 0) {
            assertTrue(success, BORROWING_HSPOST_F);
        }

        if (success) {
            _after();
        }
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                           HELPERS                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////
}
