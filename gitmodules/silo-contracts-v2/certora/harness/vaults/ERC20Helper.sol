// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {SafeERC20, IERC20} from "openzeppelin5/token/ERC20/utils/SafeERC20.sol";

contract ERC20Helper {
    using SafeERC20 for IERC20;

    function balanceOf(address token, address user) external view returns (uint256) {
        return IERC20(token).balanceOf(user);
    }

    function totalSupply(address token) external view returns (uint256) {
        return IERC20(token).totalSupply();
    }

    function safeTransferFrom(address token, address from, address to, uint256 amount) external {
        IERC20(token).safeTransferFrom(from, to, amount);
    }
}
