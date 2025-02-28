// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";

import {MethodReentrancyTest} from "../MethodReentrancyTest.sol";
import {TestStateLib} from "../../TestState.sol";

contract ForwardTransferFromNoChecksTest is MethodReentrancyTest {
    function callMethod() external {
        emit log_string("\tEnsure it will revert with OnlySilo");
        _ensureItWillRevertWithOnlySilo();
    }

    function verifyReentrancy() external {
        _ensureItWillRevertWithOnlySilo();
    }

    function methodDescription() external pure returns (string memory description) {
        description = "forwardTransferFromNoChecks(address,address,uint256)";
    }

    function _ensureItWillRevertWithOnlySilo() internal {
        address silo0 = address(TestStateLib.silo0());
        vm.expectRevert(ISilo.OnlyHookReceiver.selector);
        IShareToken(silo0).forwardTransferFromNoChecks(address(1), address(2), 3);

        address silo1 = address(TestStateLib.silo1());
        vm.expectRevert(ISilo.OnlyHookReceiver.selector);
        IShareToken(silo1).forwardTransferFromNoChecks(address(1), address(2), 3);
    }
}
