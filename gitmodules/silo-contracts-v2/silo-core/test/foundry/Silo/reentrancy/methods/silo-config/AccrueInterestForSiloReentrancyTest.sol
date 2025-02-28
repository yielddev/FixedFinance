// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {MethodReentrancyTest} from "../MethodReentrancyTest.sol";
import {TestStateLib} from "../../TestState.sol";

contract AccrueInterestForSiloReentrancyTest is MethodReentrancyTest {
    function callMethod() external {
        emit log_string("\tEnsure it will revert only for wrong silo");
        _ensureItWillRevertAsExpected();
    }

    function verifyReentrancy() external {
        _ensureItWillRevertAsExpected();
    }

    function methodDescription() external pure returns (string memory description) {
        description = "accrueInterestForSilo(address)";
    }

    function _ensureItWillRevertAsExpected() internal {
        ISiloConfig config = TestStateLib.siloConfig();
        address silo0 = address(TestStateLib.silo0());
        address silo1 = address(TestStateLib.silo1());
        address wrongSilo = makeAddr("Wrong silo");

        config.accrueInterestForSilo(silo0);
        config.accrueInterestForSilo(silo1);

        vm.expectRevert(ISiloConfig.WrongSilo.selector);
        config.accrueInterestForSilo(wrongSilo);

        vm.expectRevert(ISiloConfig.WrongSilo.selector);
        config.accrueInterestForSilo(address(0));
    }
}
