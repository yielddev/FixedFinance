// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {MethodReentrancyTest} from "../MethodReentrancyTest.sol";
import {TestStateLib} from "../../TestState.sol";

contract PreviewRepayReentrancyTest is MethodReentrancyTest {
    function callMethod() external {
        emit log_string("\tEnsure it will not revert");
        _ensureItWillNotRevert();
    }

    function verifyReentrancy() external view {
        _ensureItWillNotRevert();
    }

    function methodDescription() external pure returns (string memory description) {
        description = "previewRepay(uint256)";
    }

    function _ensureItWillNotRevert() internal view {
        TestStateLib.silo0().previewRepay(1000_000e18);
        TestStateLib.silo1().previewRepay(1000_000e18);
    }
}
