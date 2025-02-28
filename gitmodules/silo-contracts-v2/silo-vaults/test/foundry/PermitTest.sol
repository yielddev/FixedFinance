// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.28;

import {ERC20Permit} from "openzeppelin5/token/ERC20/extensions/ERC20Permit.sol";

import {SigUtils, Permit} from "./helpers/SigUtils.sol";
import {IntegrationTest} from "./helpers/IntegrationTest.sol";

/*
 FOUNDRY_PROFILE=vaults-tests forge test --ffi --mc PermitTest -vvv
*/
contract PermitTest is IntegrationTest {
    uint256 internal constant OWNER_PK = 0xA11CE;
    uint256 internal constant SPENDER_PK = 0xB0B;

    address internal owner;
    address internal spender;

    function setUp() public override {
        super.setUp();

        owner = vm.addr(OWNER_PK);
        spender = vm.addr(SPENDER_PK);

        deal(address(vault), owner, 1e18);
    }

    function testPermit(uint256 deadline) public {
        deadline = bound(deadline, block.timestamp, type(uint48).max);

        Permit memory permit = Permit({owner: owner, spender: spender, value: 1e18, nonce: 0, deadline: deadline});

        bytes32 digest = SigUtils.toTypedDataHash(vault.DOMAIN_SEPARATOR(), permit);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(OWNER_PK, digest);

        vault.permit(permit.owner, permit.spender, permit.value, permit.deadline, v, r, s);

        assertEq(vault.allowance(owner, spender), 1e18);
        assertEq(vault.nonces(owner), 1);
    }

    function testRevertExpiredPermit(uint256 deadline) public {
        deadline = bound(deadline, block.timestamp, type(uint48).max);

        Permit memory permit =
            Permit({owner: owner, spender: spender, value: 1e18, nonce: vault.nonces(owner), deadline: deadline});

        bytes32 digest = SigUtils.toTypedDataHash(vault.DOMAIN_SEPARATOR(), permit);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(OWNER_PK, digest);

        vm.warp(deadline + 1);

        vm.expectRevert(abi.encodeWithSelector(ERC20Permit.ERC2612ExpiredSignature.selector, deadline));
        vault.permit(permit.owner, permit.spender, permit.value, permit.deadline, v, r, s);
    }

    function testRevertInvalidSigner(uint256 deadline) public {
        deadline = bound(deadline, block.timestamp, type(uint48).max);

        Permit memory permit =
            Permit({owner: owner, spender: spender, value: 1e18, nonce: vault.nonces(owner), deadline: deadline});

        bytes32 digest = SigUtils.toTypedDataHash(vault.DOMAIN_SEPARATOR(), permit);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SPENDER_PK, digest); // spender signs owner's approval

        vm.expectRevert(abi.encodeWithSelector(ERC20Permit.ERC2612InvalidSigner.selector, permit.spender, permit.owner));
        vault.permit(permit.owner, permit.spender, permit.value, permit.deadline, v, r, s);
    }

    function testRevertInvalidNonce(uint256 deadline) public {
        deadline = bound(deadline, block.timestamp, type(uint48).max);

        Permit memory permit = Permit({
            owner: owner,
            spender: spender,
            value: 1e18,
            nonce: 1, // owner nonce stored on-chain is 0
            deadline: deadline
        });

        bytes32 digest = SigUtils.toTypedDataHash(vault.DOMAIN_SEPARATOR(), permit);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(OWNER_PK, digest);

        vm.expectRevert();
        vault.permit(permit.owner, permit.spender, permit.value, permit.deadline, v, r, s);
    }

    function testRevertSignatureReplay(uint256 deadline) public {
        deadline = bound(deadline, block.timestamp, type(uint48).max);

        Permit memory permit = Permit({owner: owner, spender: spender, value: 1e18, nonce: 0, deadline: deadline});

        bytes32 digest = SigUtils.toTypedDataHash(vault.DOMAIN_SEPARATOR(), permit);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(OWNER_PK, digest);

        vault.permit(permit.owner, permit.spender, permit.value, permit.deadline, v, r, s);

        vm.expectRevert();
        vault.permit(permit.owner, permit.spender, permit.value, permit.deadline, v, r, s);
    }

    function testTransferFromLimitedPermit(uint256 deadline) public {
        deadline = bound(deadline, block.timestamp, type(uint48).max);

        Permit memory permit = Permit({owner: owner, spender: spender, value: 1e18, nonce: 0, deadline: deadline});

        bytes32 digest = SigUtils.toTypedDataHash(vault.DOMAIN_SEPARATOR(), permit);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(OWNER_PK, digest);

        vault.permit(permit.owner, permit.spender, permit.value, permit.deadline, v, r, s);

        vm.prank(spender);
        vault.transferFrom(owner, spender, 1e18);

        assertEq(vault.balanceOf(owner), 0);
        assertEq(vault.balanceOf(spender), 1e18);
        assertEq(vault.allowance(owner, spender), 0);
    }

    function testTransferFromMaxPermit(uint256 deadline) public {
        deadline = bound(deadline, block.timestamp, type(uint48).max);

        Permit memory permit =
            Permit({owner: owner, spender: spender, value: type(uint256).max, nonce: 0, deadline: deadline});

        bytes32 digest = SigUtils.toTypedDataHash(vault.DOMAIN_SEPARATOR(), permit);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(OWNER_PK, digest);

        vault.permit(permit.owner, permit.spender, permit.value, permit.deadline, v, r, s);

        vm.prank(spender);
        vault.transferFrom(owner, spender, 1e18);

        assertEq(vault.balanceOf(owner), 0);
        assertEq(vault.balanceOf(spender), 1e18);
        assertEq(vault.allowance(owner, spender), type(uint256).max);
    }

    function testFailInvalidAllowance(uint256 deadline) public {
        deadline = bound(deadline, block.timestamp, type(uint48).max);

        Permit memory permit = Permit({
            owner: owner,
            spender: spender,
            value: 5e17, // approve only 0.5 tokens
            nonce: 0,
            deadline: deadline
        });

        bytes32 digest = SigUtils.toTypedDataHash(vault.DOMAIN_SEPARATOR(), permit);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(OWNER_PK, digest);

        vault.permit(permit.owner, permit.spender, permit.value, permit.deadline, v, r, s);

        vm.prank(spender);
        vault.transferFrom(owner, spender, 1e18); // attempt to transfer 1 vault
    }

    function testFailInvalidBalance(uint256 deadline) public {
        deadline = bound(deadline, block.timestamp, type(uint48).max);

        Permit memory permit = Permit({
            owner: owner,
            spender: spender,
            value: 2e18, // approve 2 tokens
            nonce: 0,
            deadline: deadline
        });

        bytes32 digest = SigUtils.toTypedDataHash(vault.DOMAIN_SEPARATOR(), permit);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(OWNER_PK, digest);

        vault.permit(permit.owner, permit.spender, permit.value, permit.deadline, v, r, s);

        vm.prank(spender);
        vault.transferFrom(owner, spender, 2e18); // attempt to transfer 2 tokens (owner only owns 1)
    }
}
