// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {SiloConfigsNames} from "silo-core/deploy/silo/SiloDeployments.sol";

import {SiloLittleHelper} from "../../_common/SiloLittleHelper.sol";

/*
    forge test -vv --ffi --mc PreviewTest
*/
contract PreviewTest is SiloLittleHelper, Test {
    uint256 constant DEPOSIT_BEFORE = 1e18 + 9876543211;

    ISiloConfig siloConfig;
    address immutable depositor;
    address immutable borrower;

    constructor() {
        depositor = makeAddr("Depositor");
        borrower = makeAddr("Borrower");
    }

    function setUp() public {
        siloConfig = _setUpLocalFixture(SiloConfigsNames.SILO_LOCAL_NO_ORACLE_NO_LTV_SILO);
    }

    /*
    forge test -vv --ffi --mt test_previewBorrow_zero_fuzz
    */
    /// forge-config: core-test.fuzz.runs = 10000
    function test_previewBorrow_zero_fuzz(uint256 _assets, bool _useShares) public view {
        assertEq(_useShares ? silo0.previewBorrowShares(_assets) : silo0.previewBorrow(_assets), _assets);
    }

    /*
    forge test -vv --ffi --mt test_previewBorrow_beforeInterest_
    */
    /// forge-config: core-test.fuzz.runs = 10000
    function test_previewBorrow_beforeInterest_1token_fuzz(uint128 _assets, bool _useShares) public {
        _previewBorrow_beforeInterest(_assets, _useShares);
    }

    function _previewBorrow_beforeInterest(uint128 _assets, bool _useShares) private {
        uint256 assetsOrSharesToBorrow = _assets / 10 + (_assets % 2); // keep even/odd
        vm.assume(assetsOrSharesToBorrow < _assets);

        // can be 0 if _assets < 10
        if (assetsOrSharesToBorrow == 0) {
            _assets = 3;
            assetsOrSharesToBorrow = 1;
        }

        _createBorrowCase(_assets);

        uint256 preview = _useShares
            ? silo1.previewBorrowShares(assetsOrSharesToBorrow)
            : silo1.previewBorrow(assetsOrSharesToBorrow);

        uint256 result = _useShares
            ? _borrow(assetsOrSharesToBorrow, borrower)
            : _borrowShares(assetsOrSharesToBorrow, borrower);

        assertEq(preview, assetsOrSharesToBorrow, "previewBorrow shares are exact as amount when no interest");
        assertEq(preview, result, "previewBorrow - expect exact match");
    }

    /*
    forge test -vv --ffi --mt test_previewBorrow_withInterest
    */
    /// forge-config: core-test.fuzz.runs = 10000
    function test_previewBorrow_withInterest_1token_fuzz(uint128 _assets, bool _useShares) public {
        _previewBorrow_withInterest(_assets, _useShares);
    }

    function _previewBorrow_withInterest(uint128 _assets, bool _useShares) private {
        uint256 assetsOrSharesToBorrow = _assets / 10 + (_assets % 2); // keep even/odd
        vm.assume(assetsOrSharesToBorrow < _assets);

        if (assetsOrSharesToBorrow == 0) {
            _assets = 3;
            assetsOrSharesToBorrow = 1;
        }

        _createBorrowCase(_assets);

        vm.warp(block.timestamp + 365 days);

        uint256 preview = _useShares
            ? silo1.previewBorrowShares(assetsOrSharesToBorrow)
            : silo1.previewBorrow(assetsOrSharesToBorrow);
        uint256 result = _useShares
            ? _borrowShares(assetsOrSharesToBorrow, borrower)
            : _borrow(assetsOrSharesToBorrow, borrower);

        assertEq(
            preview,
            result,
            string.concat(_useShares ? "[shares]" : "[assets]", " previewBorrow - expect exact match")
        );
    }

    /*
    forge test -vv --ffi --mt test_previewRepay_noInterestNoDebt_
    */
    /// forge-config: core-test.fuzz.runs = 10000
    function test_previewRepay_noInterestNoDebt_1token_fuzz(uint128 _assetsOrShares, bool _useShares, bool _repayFull)
        public
    {
        _previewRepay_noInterestNoDebt(_assetsOrShares, _useShares, _repayFull);
    }

    function _previewRepay_noInterestNoDebt(
        uint128 _assetsOrShares,
        bool _useShares,
        bool _repayFull
    ) private {
        uint128 amountToUse = _repayFull ? _assetsOrShares : uint128(uint256(_assetsOrShares) * 37 / 100);
        vm.assume(amountToUse > 0);

        // preview before debt creation
        uint256 preview = _useShares ? silo1.previewRepayShares(amountToUse) : silo1.previewRepay(amountToUse);

        _createDebt(_assetsOrShares, borrower);

        assertEq(preview, amountToUse, "previewRepay == assets == shares, when no interest");

        _assertPreviewRepay(preview, amountToUse, _useShares);
    }

    /*
    forge test -vv --ffi --mt test_previewRepayShares_noInterest_fuzz
    */
    /// forge-config: core-test.fuzz.runs = 10000
    function test_previewRepay_noInterest_1token_fuzz(uint128 _assetsOrShares, bool _useShares, bool _repayFull) public {
        _previewRepay_noInterest(_assetsOrShares, _useShares, _repayFull);
    }

    function _previewRepay_noInterest(uint128 _assetsOrShares, bool _useShares, bool _repayFull) private {
        uint128 amountToUse = _repayFull ? _assetsOrShares : uint128(uint256(_assetsOrShares) * 37 / 100);
        vm.assume(amountToUse > 0);

        _createDebt(_assetsOrShares, borrower);

        uint256 preview = _useShares ? silo1.previewRepayShares(amountToUse) : silo1.previewRepay(amountToUse);

        assertEq(preview, amountToUse, "previewRepay == assets == shares, when no interest");

        _assertPreviewRepay(preview, amountToUse, _useShares);
    }

    /*
    forge test -vv --ffi --mt test_previewRepay_withInterest_
    */
    /// forge-config: core-test.fuzz.runs = 10000
    function test_previewRepay_withInterest_1token_fuzz(
        // uint128 _assetsOrShares, bool _useShares, bool _repayFull
    )
        public
    {
        (uint128 _assetsOrShares, bool _useShares, bool _repayFull) = (280, true, true);
        _previewRepay_withInterest(_assetsOrShares, _useShares, _repayFull);
    }

    function _previewRepay_withInterest(
        uint128 _assetsOrShares,
        bool _useShares,
        bool _repayFull
    ) private {
        uint128 amountToUse = _repayFull ? _assetsOrShares : uint128(uint256(_assetsOrShares) * 37 / 100);
        vm.assume(amountToUse > 0);

        _createDebt(_assetsOrShares, borrower);
        vm.warp(block.timestamp + 100 days);

        uint256 preview = _useShares ? silo1.previewRepayShares(amountToUse) : silo1.previewRepay(amountToUse);

        _assertPreviewRepay(preview, amountToUse, _useShares);
    }

    function _assertPreviewRepay(uint256 _preview, uint128 _assetsOrShares, bool _useShares) internal {
        vm.assume(_preview > 0);

        uint256 repayResult = _useShares
            ? _repayShares(type(uint256).max, _assetsOrShares, borrower)
            : _repay(_assetsOrShares, borrower);

        assertGt(repayResult, 0, "expect any repay amount > 0");

        assertEq(
            _preview,
            repayResult,
            string.concat(_useShares ? "[shares]" : "[amount]", " preview should give us exact repay result")
        );
    }

    function _createBorrowCase(uint128 _assets) internal {
        address somebody = makeAddr("Somebody");

        _deposit(_assets, borrower);

        // deposit to both silos
        _deposit(_assets, somebody);
        _depositForBorrow(_assets, somebody);
    }
}
