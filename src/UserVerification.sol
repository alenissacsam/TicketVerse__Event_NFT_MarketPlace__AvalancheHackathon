// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/**
 * @title UserVerification
 * @author alenissacsam
 * @dev Enhanced smart contract for managing user verification on the blockchain.
 * It allows the owner to verify users, revoke verification, and manage user metadata.
 * This contract is designed to be used with other contracts that require user verification.
 */
contract UserVerification is Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;

    /*//////////////////////////////////////////////////////////////
                                ENUMS
    //////////////////////////////////////////////////////////////*/
    enum VerificationLevel { Basic, Premium, VIP }

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/
    error UserVerification__UserAlreadyVerified(address user);
    error UserVerification__UserNotVerified(address user);
    error UserVerification__UserNotVerifiedOrLevelTooLow(address user, VerificationLevel requiredLevel);
    error UserVerification__OffsetOutOfBounds();
    error UserVerification__InvalidBatchSize();

    /*//////////////////////////////////////////////////////////////
                                VARIABLES
    //////////////////////////////////////////////////////////////*/
    EnumerableSet.AddressSet private _verifiedUsers;

    mapping(address => uint256) public verificationTime;
    mapping(address => string) public userMetadata;
    mapping(address => VerificationLevel) public verificationLevel;

    // Batch verification limits
    uint256 public constant MAX_BATCH_SIZE = 100;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    event UserVerified(address indexed user, uint256 timestamp, VerificationLevel level);
    event UserLevelUpgraded(address indexed user, VerificationLevel oldLevel, VerificationLevel newLevel);
    event UserRevoked(address indexed user, uint256 timestamp);
    event UserMetadataUpdated(address indexed user, string metadata);
    event BatchVerificationCompleted(uint256 userCount, uint256 timestamp);

    /*//////////////////////////////////////////////////////////////
                                FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    constructor() Ownable(msg.sender) {}

    /**
     * @dev Verify a single user
     */
    function verifyUser(address user) external onlyOwner {
        _verifyUserWithLevel(user, "", VerificationLevel.Basic);
    }

    /**
     * @dev Verify user with metadata
     */
    function verifyUserWithMetadata(address user, string memory metadata) external onlyOwner {
        _verifyUserWithLevel(user, metadata, VerificationLevel.Basic);
    }

    /**
     * @dev Verify user with specific verification level
     */
    function verifyUserWithLevel(
        address user, 
        string memory metadata, 
        VerificationLevel level
    ) external onlyOwner {
        _verifyUserWithLevel(user, metadata, level);
    }

    /**
     * @dev Batch verify multiple users
     */
    function batchVerifyUsers(address[] calldata users) external onlyOwner {
        if (users.length > MAX_BATCH_SIZE) {
            revert UserVerification__InvalidBatchSize();
        }

        for (uint256 i = 0; i < users.length; i++) {
            // _verifyUserWithLevel handles the check for already verified users
            _verifyUserWithLevel(users[i], "", VerificationLevel.Basic);
        }

        emit BatchVerificationCompleted(users.length, block.timestamp);
    }

    /**
     * @dev Batch verify users with different levels
     */
    function batchVerifyUsersWithLevels(
        address[] calldata users,
        VerificationLevel[] calldata levels
    ) external onlyOwner {
        if (users.length != levels.length || users.length > MAX_BATCH_SIZE) {
            revert UserVerification__InvalidBatchSize();
        }

        for (uint256 i = 0; i < users.length; i++) {
            _verifyUserWithLevel(users[i], "", levels[i]);
        }

        emit BatchVerificationCompleted(users.length, block.timestamp);
    }

    /**
     * @dev Revoke user verification
     */
    function revokeUser(address user) external onlyOwner {
        if (!_verifiedUsers.remove(user)) {
            revert UserVerification__UserNotVerified(user);
        }

        delete verificationTime[user];
        delete userMetadata[user];
        delete verificationLevel[user];
        
        emit UserRevoked(user, block.timestamp);
    }

    /**
     * @dev Update user metadata without changing verification status
     */
    function updateUserMetadata(address user, string memory metadata) external onlyOwner {
        if (!_verifiedUsers.contains(user)) {
            revert UserVerification__UserNotVerified(user);
        }

        userMetadata[user] = metadata;
        emit UserMetadataUpdated(user, metadata);
    }

    /**
     * @dev Upgrade user verification level
     */
    function upgradeUserLevel(address user, VerificationLevel newLevel) external onlyOwner {
        if (!_verifiedUsers.contains(user)) {
            revert UserVerification__UserNotVerified(user);
        }

        VerificationLevel oldLevel = verificationLevel[user];
        verificationLevel[user] = newLevel;

        emit UserLevelUpgraded(user, oldLevel, newLevel);
    }

    /*//////////////////////////////////////////////////////////////
                        EXTERNAL VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @dev Check if user is verified
     */
    function isVerified(address user) external view returns (bool) {
        return _verifiedUsers.contains(user);
    }

    /**
     * @dev Check if user has specific verification level or higher
     */
    function hasMinimumLevel(address user, VerificationLevel minLevel) external view returns (bool) {
        return _verifiedUsers.contains(user) && verificationLevel[user] >= minLevel;
    }

    /**
     * @dev Get user's verification level
     */
    function getUserLevel(address user) external view returns (VerificationLevel) {
        return verificationLevel[user];
    }

    /**
     * @dev Get verification time for user
     */
    function getVerificationTime(address user) external view returns (uint256) {
        return verificationTime[user];
    }

    /**
     * @dev Get user metadata
     */
    function getUserMetadata(address user) external view returns (string memory) {
        return userMetadata[user];
    }

    /**
     * @dev Get total verified users count
     */
    function getVerifiedUsersCount() external view returns (uint256) {
        return _verifiedUsers.length();
    }

    /**
     * @dev Get paginated list of verified users
     */
    function getVerifiedUsers(
        uint256 offset, 
        uint256 limit
    ) external view returns (address[] memory) {
        uint256 count = _verifiedUsers.length();
        if (offset >= count) {
            revert UserVerification__OffsetOutOfBounds();
        }

        uint256 end = offset + limit > count ? count : offset + limit;
        address[] memory result = new address[](end - offset);
        for (uint256 i = 0; i < result.length; i++) {
            result[i] = _verifiedUsers.at(offset + i);
        }
        return result;
    }

    /**
     * @dev Get users by verification level
     */
    function getUsersByLevel(VerificationLevel level) external view returns (address[] memory) {
        uint256 totalVerified = _verifiedUsers.length();
        address[] memory usersWithLevel = new address[](totalVerified);
        uint256 resultCount = 0;

        for (uint256 i = 0; i < totalVerified; i++) {
            address user = _verifiedUsers.at(i);
            if (verificationLevel[user] == level) {
                usersWithLevel[resultCount] = user;
                resultCount++;
            }
        }

        address[] memory result = new address[](resultCount);
        assembly { mstore(result, resultCount) }
        for (uint256 i = 0; i < resultCount; i++) {
            result[i] = usersWithLevel[i];
        }

        return result;
    }

    /**
     * @dev Check if user was verified before a specific timestamp
     */
    function wasVerifiedBefore(address user, uint256 timestamp) external view returns (bool) {
        return _verifiedUsers.contains(user) && verificationTime[user] <= timestamp;
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function _verifyUserWithLevel(
        address user, 
        string memory metadata, 
        VerificationLevel level
    ) internal {
        if (!_verifiedUsers.add(user)) {
            revert UserVerification__UserAlreadyVerified(user);
        }

        verificationTime[user] = block.timestamp;
        verificationLevel[user] = level;
        
        if (bytes(metadata).length > 0) {
            userMetadata[user] = metadata;
            emit UserMetadataUpdated(user, metadata);
        }

        emit UserVerified(user, block.timestamp, level);
    }
}