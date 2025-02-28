// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

interface IPPausingInterface {
    function pause() external;

    function unpause() external;

    function paused() external view returns (bool);
}
