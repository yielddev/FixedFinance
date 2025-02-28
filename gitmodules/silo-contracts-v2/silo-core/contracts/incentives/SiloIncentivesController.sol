// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {SafeERC20} from "openzeppelin5/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";
import {EnumerableSet} from "openzeppelin5/utils/structs/EnumerableSet.sol";
import {Strings} from "openzeppelin5/utils/Strings.sol";

import {ISiloIncentivesController} from "./interfaces/ISiloIncentivesController.sol";
import {BaseIncentivesController} from "./base/BaseIncentivesController.sol";
import {DistributionTypes} from "./lib/DistributionTypes.sol";

/**
 * @title SiloIncentivesController
 * @notice Distributor contract for rewards to the Aave protocol, using a staked token as rewards asset.
 * The contract stakes the rewards before redistributing them to the Aave protocol participants.
 * The reference staked token implementation is at https://github.com/aave/aave-stake-v2
 * @author Aave
 */
contract SiloIncentivesController is BaseIncentivesController {
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using SafeERC20 for IERC20;

    /// @param _owner address of wallet that can manage the storage
    /// @param _notifier is contract with IERC20 interface with users balances, based based on which
    /// rewards distribution is calculated
    constructor(address _owner, address _notifier) BaseIncentivesController(_owner, _notifier) {}

    /// @inheritdoc ISiloIncentivesController
    function afterTokenTransfer(
        address _sender,
        uint256 _senderBalance,
        address _recipient,
        uint256 _recipientBalance,
        uint256 _totalSupply,
        uint256 _amount
    ) public virtual onlyNotifier {
        uint256 numberOfPrograms = _incentivesProgramIds.length();

        if (_sender == _recipient || numberOfPrograms == 0) {
            return;
        }

        // updating total supply and users balances to the state before the transfer

        if (_sender == address(0)) {
            // we minting tokens, so supply before was less
            // we safe, because this amount came from token, if token handle them we can handle as well
            unchecked { _totalSupply -= _amount; }
        } else if (_recipient == address(0)) {
            // we burning, so supply before was more
            // we safe, because this amount came from token, if token handle them we can handle as well
            unchecked { _totalSupply += _amount; }
        }

        // here user either transferring token to someone else or burning tokens
        // user state will be new, because this event is `onAfterTransfer`
        // we need to recreate status before event in order to automatically calculate rewards
        if (_sender != address(0)) {
            // we safe, because this amount came from token, if token handle them we can handle as well
            unchecked { _senderBalance = _senderBalance + _amount; }
        }

        // we have to checkout also user `_recipient`
        if (_recipient != address(0)) {
            // we safe, because this amount came from token, if token handle them we can handle as well
            unchecked { _recipientBalance = _recipientBalance - _amount; }
        }

        // iterate over incentives programs
        for (uint256 i = 0; i < numberOfPrograms; i++) {
            bytes32 programId = _incentivesProgramIds.at(i);

            if (_sender != address(0)) {
                _handleAction(programId, _sender, _totalSupply, _senderBalance);
            }

            if (_recipient != address(0)) {
                _handleAction(programId, _recipient, _totalSupply, _recipientBalance);
            }
        }
    }

    /// @inheritdoc ISiloIncentivesController
    function immediateDistribution(address _tokenToDistribute, uint104 _amount) external virtual onlyNotifierOrOwner {
        if (_amount == 0) return;

        uint256 totalStaked = _shareToken().totalSupply();

        bytes32 programId = _getOrCreateImmediateDistributionProgram(_tokenToDistribute);

        IncentivesProgram storage program = incentivesPrograms[programId];

        // Update the program's internal state to guarantee that further actions will not break it.
        _updateAssetStateInternal(programId, totalStaked);

        uint40 distributionEndBefore = program.distributionEnd;
        uint104 emissionPerSecondBefore = program.emissionPerSecond;

        // Distributing `_amount` of rewards in one second allows the rewards to be added to users' balances
        // even to the active incentives program.
        program.distributionEnd = uint40(block.timestamp);  
        program.lastUpdateTimestamp = uint40(block.timestamp - 1);
        program.emissionPerSecond = _amount;

        _updateAssetStateInternal(programId, totalStaked);

        // If we have ongoing distribution, we need to revert the changes and keep the state as it was.
        program.distributionEnd = distributionEndBefore;
        program.lastUpdateTimestamp = uint40(block.timestamp);
        program.emissionPerSecond = emissionPerSecondBefore;
    }

    /// @inheritdoc ISiloIncentivesController
    function rescueRewards(address _rewardToken) external onlyOwner {
        IERC20(_rewardToken).safeTransfer(msg.sender, IERC20(_rewardToken).balanceOf(address(this)));
    }

    /// @dev Creates a new immediate distribution program if it does not exist.
    /// @param _tokenToDistribute The address of the token to distribute.
    /// @return programId The ID of the created or existing program.
    function _getOrCreateImmediateDistributionProgram(address _tokenToDistribute)
        internal
        virtual
        returns (bytes32 programId)
    {
        string memory programName = Strings.toHexString(_tokenToDistribute);
        programId = getProgramId(programName);

        if (incentivesPrograms[programId].lastUpdateTimestamp == 0) {
            DistributionTypes.IncentivesProgramCreationInput memory _incentivesProgramInput;

            _incentivesProgramInput.name = programName;
            _incentivesProgramInput.rewardToken = _tokenToDistribute;
            _incentivesProgramInput.emissionPerSecond = 0;
            _incentivesProgramInput.distributionEnd = 0;

            _createIncentiveProgram(_incentivesProgramInput);
        }
    }
}
