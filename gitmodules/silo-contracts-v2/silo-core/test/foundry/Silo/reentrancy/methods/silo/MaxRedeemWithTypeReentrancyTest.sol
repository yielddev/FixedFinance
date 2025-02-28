// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {MethodReentrancyTest} from "../MethodReentrancyTest.sol";
import {TestStateLib} from "../../TestState.sol";

contract MaxRedeemWithTypeReentrancyTest is MethodReentrancyTest {
    function callMethod() external {
        emit log_string("\tEnsure it will not revert");
        _ensureItWillNotRevert();
    }

    function verifyReentrancy() external {
        _ensureItWillNotRevert();
    }

    function methodDescription() external pure returns (string memory description) {
        description = "maxRedeem(address,uint8)";
    }

    function _ensureItWillNotRevert() internal {
        address anyAddr = makeAddr("Any address");

        TestStateLib.silo0().maxRedeem(anyAddr, ISilo.CollateralType.Collateral);
        TestStateLib.silo1().maxRedeem(anyAddr, ISilo.CollateralType.Collateral);

        TestStateLib.silo0().maxRedeem(anyAddr, ISilo.CollateralType.Protected);
        TestStateLib.silo1().maxRedeem(anyAddr, ISilo.CollateralType.Protected);
    }
}
