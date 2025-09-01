// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface UserVerificationErrorsAndEnums {
    /*//////////////////////////////////////////////////////////////
                                ENUMS
    //////////////////////////////////////////////////////////////*/
    enum VerificationLevel {
        None,
        Basic,
        Premium,
        VIP,
        Admin
    }

    enum SuspensionReason {
        None,
        Fraud,
        Abuse,
        PolicyViolation,
        Other
    }

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error UserVerification__UserAlreadyVerified(address user);
    error UserVerification__UserNotVerified(address user);
    error UserVerification__UserSuspended(address user);
    error UserVerification__UserNotSuspended(address user);
    error UserVerification__VerificationExpired(address user);
    error UserVerification__InsufficientLevel(address user, VerificationLevel required);
    error UserVerification__RateLimitExceeded(address user);
    error UserVerification__NotOwner();

    // Configuration and input validation errors
    error UserVerification__OffsetOutOfBounds();
    error UserVerification__InvalidBatchSize();
    error UserVerification__InvalidDuration();
    error UserVerification__InvalidSuspensionDuration();
    error UserVerification__InvalidVerificationLevel(VerificationLevel level);
    error UserVerification__InvalidMaxBatchSize();
    error UserVerification__InvalidMaxAttempts();
    error UserVerification__InvalidCooldown();

    // Level management errors
    error UserVerification__UpgradeToSameOrLowerLevel();
    error UserVerification__DowngradeToSameOrHigherLevel();
}
