// SPDX-License-Identifier: GPL-2.0-or-later
methods {
    function multicall(bytes[]) external returns(bytes[]) => NONDET DELETE;

    function asset() external returns(address) envfree;
    function timelock() external returns(uint256) envfree;
    function guardian() external returns(address) envfree;
    function supplyQueueLength() external returns(uint256) envfree;
    function supplyQueue(uint256) external returns(address) envfree;
    function withdrawQueueLength() external returns(uint256) envfree;
    function withdrawQueue(uint256) external returns(address) envfree;
    function fee() external returns(uint96) envfree;
    function feeRecipient() external returns(address) envfree;
    function owner() external returns(address) envfree;
    function curator() external returns(address) envfree;
    function isAllocator(address) external returns(bool) envfree;
    function skimRecipient() external returns(address) envfree;

    // HARNESS
    function pendingTimelock_() external returns(MetaMorphoHarness.PendingUint192) envfree;
    function getVaultAsset(address) external returns(address) envfree;
    function pendingGuardian_() external returns(MetaMorphoHarness.PendingAddress) envfree;
    function config_(address) external returns(MetaMorphoHarness.MarketConfig) envfree;
    function pendingCap_(address) external returns(MetaMorphoHarness.PendingUint192) envfree;
    function minTimelock() external returns(uint256) envfree;
    function maxTimelock() external returns(uint256) envfree;
    function maxQueueLength() external returns(uint256) envfree;
    function maxFee() external returns(uint256) envfree;

    // PATCH
    function withdrawRank(address) external returns(uint256) envfree;
    function deletedAt(address) external returns(uint256) envfree;
}

function isPendingTimelockInRange() returns bool {
    MetaMorphoHarness.PendingUint192 pendingTimelock = pendingTimelock_();

    return pendingTimelock.validAt != 0 =>
        assert_uint256(pendingTimelock.value) <= maxTimelock() &&
        assert_uint256(pendingTimelock.value) >= minTimelock();
}

// Check that the pending timelock is bounded by the min timelock and the max timelock.
invariant pendingTimelockInRange()
    isPendingTimelockInRange();

// Check that the timelock is bounded by the min timelock and the max timelock.
invariant timelockInRange()
    timelock() <= maxTimelock() && timelock() >= minTimelock()
{
    preserved {
        requireInvariant pendingTimelockInRange();
    }
}

// Check that the fee cannot go over the max fee.
invariant feeInRange()
    assert_uint256(fee()) <= maxFee();

// Check that the supply queue length cannot go over the max queue length.
invariant supplyQueueLengthInRange()
    supplyQueueLength() <= maxQueueLength();

// Check that the withdraw queue length cannot go over the max queue length.
invariant withdrawQueueLengthInRange()
    withdrawQueueLength() <= maxQueueLength();
