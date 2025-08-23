// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {UserVerification} from "../src/UserVerification.sol";
import {Script, console} from "forge-std/Script.sol";
import {DevOpsTools} from "@foundry-devops/src/DevOpsTools.sol";

contract UserVerificationInteraction is Script {
    function run() public {
        // This script checks the verification status of different users.

        // 1. Get the most recently deployed UserVerification contract.
        UserVerification userVerification = UserVerification(
            DevOpsTools.get_most_recent_deployment(
                "UserVerification",
                block.chainid
            )
        );
        console.log("UserVerification contract address:", address(userVerification));

        // 2. Check the owner of the contract. The owner should be verified by the constructor.
        address owner = userVerification.owner();
        console.log("Contract owner:", owner);
        console.log("Is owner verified?", userVerification.isVerified(owner));

        // 3. Check a random, unverified address. This should return false.
        address randomUser = address(0xDEADBEEF);
        console.log("Checking random user:", randomUser);
        console.log("Is random user verified?", userVerification.isVerified(randomUser));
    }
}
