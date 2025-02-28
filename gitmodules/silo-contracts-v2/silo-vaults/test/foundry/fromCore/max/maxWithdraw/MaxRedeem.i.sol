// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {VaultsLittleHelper} from "../../_common/VaultsLittleHelper.sol";

/*
    FOUNDRY_PROFILE=vaults-tests forge test -vv --ffi --mc MaxRedeemTest
*/
contract MaxRedeemTest is VaultsLittleHelper {
    address immutable depositor;

    constructor() {
        depositor = makeAddr("Depositor");
    }
    
    /*
    FOUNDRY_PROFILE=vaults-tests forge test -vv --ffi --mt test_maxRedeem_zero
    */
    function test_maxRedeem_zero() public view {
        uint256 maxRedeem = vault.maxRedeem(depositor);
        assertEq(maxRedeem, 0, "nothing to redeem");
    }

    /*
    FOUNDRY_PROFILE=vaults-tests forge test -vv --ffi --mt test_maxRedeem_deposit_fuzz
    */
    /// forge-config: vaults-tests.fuzz.runs = 1000
    function test_maxRedeem_deposit_fuzz(
        uint112 _assets,
        uint16 _assets2
    ) public {
        vm.assume(_assets > 0);
        vm.assume(_assets2 > 0);

        _deposit(_assets, depositor);
        _deposit(_assets2, address(1)); // any

        uint256 maxRedeem = vault.maxRedeem(depositor);
        assertEq(maxRedeem, _assets, "max withdraw == _assets/shares if no interest");

        _assertDepositorCanNotRedeemMore(maxRedeem);
        _assertDepositorHasNothingToRedeem();
    }

    /*
    FOUNDRY_PROFILE=vaults-tests forge test -vv --ffi --mt test_maxRedeem_whenBorrow
    */
    /// forge-config: vaults-tests.fuzz.runs = 1000
    function test_maxRedeem_whenBorrow_1token_fuzz(
        uint128 _collateral,
        uint128 _toBorrow
    ) public {
        vm.assume(_toBorrow > 0);
        vm.assume(_toBorrow <= _collateral);

        _reduceLiquidity(_collateral, _toBorrow);

        uint256 maxRedeem = vault.maxRedeem(depositor);
        assertLt(maxRedeem, vault.balanceOf(depositor), "with debt you can not withdraw all");

        _assertDepositorCanNotRedeemMore(maxRedeem);
    }

    /*
    FOUNDRY_PROFILE=vaults-tests forge test -vv --ffi --mt test_maxRedeem_whenInterest_
    */
    /// forge-config: vaults-tests.fuzz.runs = 1000
    function test_maxRedeem_whenInterest_fuzz(
        uint128 _collateral,
        uint128 _toBorrow
    ) public {
        vm.assume(_toBorrow > 0);
        vm.assume(_toBorrow <= _collateral);

        _reduceLiquidity(_collateral, _toBorrow);

        vm.warp(block.timestamp + 100 days);

        uint256 maxRedeem = vault.maxRedeem(depositor);
        assertLt(maxRedeem, vault.balanceOf(depositor), "with debt you can not withdraw all");

        _assertDepositorCanNotRedeemMore(maxRedeem, 3);
    }

    function _assertDepositorHasNothingToRedeem() internal view {
        assertEq(vault.maxRedeem(depositor), 0, "expect maxRedeem to be 0");
        assertEq(vault.balanceOf(depositor), 0, "expect share balance to be 0");
    }

    function _assertDepositorCanNotRedeemMore(uint256 _maxRedeem) internal {
        _assertDepositorCanNotRedeemMore(_maxRedeem, 1);
    }

    function _assertDepositorCanNotRedeemMore(uint256 _maxRedeem, uint256 _underestimate) internal {
        emit log_named_uint("------- QA: _assertDepositorCanNotRedeemMore shares", _maxRedeem);

        assertGt(_underestimate, 0, "_underestimate must be at least 1");

        if (_maxRedeem > 0) {
            vm.prank(depositor);
            vault.redeem(_maxRedeem, depositor, depositor);
        }

        uint256 counterExample = _underestimate;
        emit log_named_uint("=========== [counterexample] testing counterexample for maxRedeem with", counterExample);

        vm.prank(depositor);
        vm.expectRevert();
        vault.redeem(counterExample, depositor, depositor);
    }

    function _assertMaxRedeemIsZeroAtTheEnd() internal {
        _assertMaxRedeemIsZeroAtTheEnd(0);
    }

    function _assertMaxRedeemIsZeroAtTheEnd(uint256 _underestimate) internal {
        emit log_named_uint("================= _assertMaxRedeemIsZeroAtTheEnd ================= +/-", _underestimate);

        uint256 maxRedeem = vault.maxRedeem(depositor);

        assertLe(
            maxRedeem,
            _underestimate,
            string.concat("at this point max should return 0 +/-", string(abi.encodePacked(_underestimate)))
        );
    }

    function _reduceLiquidity(uint256 _depositAssets, uint256 _toBorrow) internal {
        _deposit(_depositAssets, depositor);

        address borrower = makeAddr("Borrower");

        vm.startPrank(borrower);
        _silo0().deposit(_toBorrow * 10, borrower);
        _silo1().borrow(_toBorrow, borrower, borrower);
        vm.stopPrank();
    }
}
