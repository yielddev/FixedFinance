// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ERC20} from "openzeppelin5/token/ERC20/ERC20.sol";

contract MintableToken is ERC20 {
    uint8 immutable private _decimals;

    bool onDemand;

    constructor(uint8 _setDecimals) ERC20("a", "b") {
        _decimals = _setDecimals;
    }

    function mint(address _owner, uint256 _amount) external virtual {
        _mint(_owner, _amount);
    }

    function setOnDemand(bool _onDemand) external {
        onDemand = _onDemand;
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    function mintOnDemand(address _owner, uint256 _amount) public virtual {
        uint256 balance = balanceOf(_owner);
        if (balance >= _amount) return;

        if (type(uint256).max - totalSupply() < _amount - balance) revert("mint not possible: uint256 MAX");

        _mint(_owner, _amount - balance);
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        if (!onDemand) {
            return super.transferFrom(sender, recipient, amount);
        }

        // do whatever to be able to transfer from

        mintOnDemand(sender, amount);

        _transfer(sender, recipient, amount);

        // no allowance!

        return true;
    }

    function transfer(
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        if (!onDemand) {
            return super.transfer(recipient, amount);
        }

        // do whatever to be able to transfer from

        mintOnDemand(msg.sender, amount);

        _transfer(msg.sender, recipient, amount);

        // no allowance!

        return true;
    }
}
