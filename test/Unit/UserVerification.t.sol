// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {UserVerification} from "../../src/UserVerification.sol";
import {Test, console} from "forge-std/Test.sol";

contract UserVerificationTest is Test {
    UserVerification userVerification;
    address owner;
    address randomUser = makeAddr("randomUser");

    function setUp() public {
        owner = msg.sender;
        vm.prank(owner);
        userVerification = new UserVerification();
    }

    function test_OwnerIsVerifiedOnDeployment() public view {
        assertTrue(userVerification.isVerified(owner));
    }

    function test_RandomUserIsNotVerified() public view {
        assertFalse(userVerification.isVerified(randomUser));
    }
}
