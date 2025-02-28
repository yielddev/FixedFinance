// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {VaultsLittleHelper} from "../../_common/VaultsLittleHelper.sol";

/*
    forge test -vv --ffi --mc PreviewWithdrawTest
*/
contract PreviewWithdrawTest is VaultsLittleHelper {
    address immutable depositor;

    constructor() {
        depositor = makeAddr("Depositor");
    }

    /*
    forge test -vv --ffi --mt test_previewWithdraw_noInterestNoDebt_fuzz
    */
    /// forge-config: vaults-tests.fuzz.runs = 1000
    function test_previewWithdraw_noInterestNoDebt_fuzz(
        uint128 _assetsOrShares,
        bool _partial
    ) public {
        uint256 amountIn = _partial ? uint256(_assetsOrShares) * 37 / 100 : _assetsOrShares;
        vm.assume(amountIn > 0);

        _deposit(_assetsOrShares, depositor);

        uint256 preview = _getPreview(amountIn);

        _assertEqPrevAmountInSharesWhenNoInterest(preview, amountIn);

        _assertPreviewWithdraw(preview, amountIn);
    }

    /*
    forge test -vv --ffi --mt test_previewWithdraw_debt_fuzz
    same asset: we check preview on same silo
    two assets: we need to borrow on silo0 in addition
    */
    /// forge-config: vaults-tests.fuzz.runs = 1000
    function test_previewWithdraw_debt_fuzz(
        uint128 _assetsOrShares,
        bool _interest,
        bool _partial
    ) public {
        vm.assume(_assetsOrShares > 1); // can not create debt with 1 collateral
        uint128 amountToUse = _partial ? uint128(uint256(_assetsOrShares) * 37 / 100) : _assetsOrShares;
        vm.assume(amountToUse > 0);

        _deposit(_assetsOrShares, depositor);

        _createSiloUsage();

        if (_interest) _applyInterest();

        uint256 preview = _getPreview(amountToUse);

        if (!_interest) {
            _assertEqPrevAmountInSharesWhenNoInterest(preview, amountToUse);
        }

        _assertPreviewWithdraw(preview, amountToUse);
    }

    /*
    forge test -vv --ffi --mt test_previewWithdraw_random_fuzz
    */
    /// forge-config: vaults-tests.fuzz.runs = 1000
    function test_previewWithdraw_random_fuzz(uint64 _assetsOrShares, bool _interest) public {
        vm.assume(_assetsOrShares > 0);

        _deposit(_assetsOrShares, depositor);

        _createSiloUsage();

        if (_interest) _applyInterest();

        uint256 preview = _getPreview(_assetsOrShares);

        if (!_interest) {
            _assertEqPrevAmountInSharesWhenNoInterest(preview, _assetsOrShares);
        }

        _assertPreviewWithdraw(preview, _assetsOrShares);
    }

    /*
    forge test -vv --ffi --mt test_previewWithdraw_min_fuzz
    */
    /// forge-config: vaults-tests.fuzz.runs = 1000
    function test_previewWithdraw_min_fuzz(uint112 _assetsOrShares, bool _interest) public {
        vm.assume(_assetsOrShares > 0);

        _deposit(_assetsOrShares, depositor);

        _createSiloUsage();

        if (_interest) _applyInterest();

        uint256 minInput = _useRedeem() ? vault.convertToShares(1) : vault.convertToAssets(1);
        uint256 minPreview = _getPreview(minInput);

        if (!_interest) {
            _assertEqPrevAmountInSharesWhenNoInterest(minPreview, minInput);

        }

        _assertPreviewWithdraw(minPreview, minInput);
    }

    /*
    forge test -vv --ffi --mt test_previewWithdraw_max_fuzz
    */
    /// forge-config: vaults-tests.fuzz.runs = 1000
    function test_previewWithdraw_max_fuzz(uint64 _assets, bool _interest) public {
        vm.assume(_assets > 0);

        _deposit(_assets, depositor);

        _createSiloUsage();

        if (_interest) _applyInterest();

        uint256 maxInput = _useRedeem()
            // we can not use balance of share token, because we not sure about liquidity
            ? vault.maxRedeem(depositor)
            : vault.maxWithdraw(depositor);

        uint256 maxPreview = _getPreview(maxInput);

        if (!_interest) {
            _assertEqPrevAmountInSharesWhenNoInterest(maxPreview, maxInput);
        }

        _assertPreviewWithdraw(maxPreview, maxInput);
    }

    function _createSiloUsage() internal {
        vm.prank(depositor);
        vault.deposit(type(uint128).max, depositor);

        address borrower = makeAddr("Borrower");

        vm.startPrank(borrower);
        _silo0().deposit(type(uint128).max, borrower);
        _silo1().borrow(type(uint64).max, borrower, borrower);
        vm.stopPrank();
    }

    function _applyInterest() internal {
        vm.warp(block.timestamp + 200 days);
        _silo0().accrueInterest();
        _silo1().accrueInterest();
    }

    function _assertPreviewWithdraw(uint256 _preview, uint256 _assetsOrShares) internal {
        vm.assume(_preview > 0);
        vm.prank(depositor);

        uint256 results = _useRedeem()
            ? vault.redeem(_assetsOrShares, depositor, depositor)
            : vault.withdraw(_assetsOrShares, depositor, depositor);

        assertGt(results, 0, "expect any withdraw amount > 0");

        if (_useRedeem()) assertEq(_preview, results, "preview should give us exact result, NOT more");
        else assertEq(_preview, results, "preview should give us exact result, NOT fewer");
    }

    function _getPreview(uint256 _amountToUse) internal view virtual returns (uint256 preview) {
        preview = _useRedeem()
            ? vault.previewRedeem(_amountToUse)
            : vault.previewWithdraw(_amountToUse);
    }

    function _useRedeem() internal pure virtual returns (bool) {
        return false;
    }

    function _assertEqPrevAmountInSharesWhenNoInterest(uint256 _preview, uint256 _amountIn) private pure {
        if (_useRedeem()) assertEq(_preview, _amountIn, "previewWithdraw == assets == shares, when no interest");
        else assertEq(_preview, _amountIn, "previewWithdraw == assets == shares, when no interest");
    }
}
