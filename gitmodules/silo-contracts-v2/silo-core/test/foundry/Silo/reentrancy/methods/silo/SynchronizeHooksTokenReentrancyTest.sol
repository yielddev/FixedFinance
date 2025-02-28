// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";

import {MethodReentrancyTest} from "../MethodReentrancyTest.sol";
import {TestStateLib} from "../../TestState.sol";

contract SynchronizeHooksTokenReentrancyTest is MethodReentrancyTest {
    function callMethod() external {
        emit log_string("\tEnsure it will not revert");
        _ensureItWillRevertWithOnlySilo();
    }

    function verifyReentrancy() external {
        _ensureItWillRevertWithOnlySilo();
    }

    function methodDescription() external pure returns (string memory description) {
        description = "synchronizeHooks(uint24,uint24)";
    }

    function _ensureItWillRevertWithOnlySilo() internal {
        address silo0 = address(TestStateLib.silo0());
        vm.expectRevert(IShareToken.OnlySilo.selector);
        IShareToken(silo0).synchronizeHooks(1, 2);

        address silo1 = address(TestStateLib.silo1());
        vm.expectRevert(IShareToken.OnlySilo.selector);
        IShareToken(silo1).synchronizeHooks(1, 2);
    }
}
