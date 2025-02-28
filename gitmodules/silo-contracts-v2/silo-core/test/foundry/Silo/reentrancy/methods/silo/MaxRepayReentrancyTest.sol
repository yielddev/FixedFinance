// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {MethodReentrancyTest} from "../MethodReentrancyTest.sol";
import {TestStateLib} from "../../TestState.sol";

contract MaxRepayReentrancyTest is MethodReentrancyTest {
    function callMethod() external {
        emit log_string("\tEnsure it will not revert");
        _ensureItWillNotRevert();
    }

    function verifyReentrancy() external {
        _ensureItWillNotRevert();
    }

    function methodDescription() external pure returns (string memory description) {
        description = "maxRepay(address)";
    }

    function _ensureItWillNotRevert() internal {
        address anyAddr = makeAddr("Any address");

        TestStateLib.silo0().maxRepay(anyAddr);
        TestStateLib.silo1().maxRepay(anyAddr);
    }
}
