// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {UserVerificationErrorsAndEnums} from "./Interface/IUserVerificationeErrorsAndEnums.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/**
 * @title UserVerification
 * @author alenissacsam (Enhanced by AI)
 * @dev Enhanced user verification with all logic errors fixed
 */
contract UserVerification is UserVerificationErrorsAndEnums {
    using EnumerableSet for EnumerableSet.AddressSet;

    /*//////////////////////////////////////////////////////////////
                                VARIABLES
    //////////////////////////////////////////////////////////////*/
    EnumerableSet.AddressSet private _verifiedUsers;

    // Core verification data
    mapping(address => uint256) public verificationTime;
    mapping(address => string) public userMetadata;
    mapping(address => VerificationLevel) public verificationLevel;

    // Enhanced features
    mapping(address => uint256) public verificationExpiry;
    mapping(address => bool) public isSuspended;
    mapping(address => uint256) public suspensionEndTime;
    mapping(address => SuspensionReason) public suspensionReason;
    mapping(address => uint256) public verificationAttempts;
    mapping(address => uint256) public lastVerificationAttempt;

    // Configuration
    uint256 public verificationDuration = 365 days; // Default 1 year
    uint256 public maxBatchSize = 100; // Configurable batch size
    uint256 public maxVerificationAttempts = 3; // Max attempts per day
    uint256 public verificationCooldown = 1 days; // Cooldown between attempts

    // FIXED: Synchronized level counting
    mapping(VerificationLevel => uint256) public levelCounts;
    uint256 public totalSuspensions;
    uint256 public totalExpirations;

    address public immutable I_OWNER;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    event UserVerified(address indexed user, uint256 timestamp, VerificationLevel level, uint256 expiryTime);
    event UserLevelUpgraded(address indexed user, VerificationLevel oldLevel, VerificationLevel newLevel);
    event UserLevelDowngraded(address indexed user, VerificationLevel oldLevel, VerificationLevel newLevel);
    event UserRevoked(address indexed user, uint256 timestamp);
    event UserSuspended(address indexed user, uint256 endTime, SuspensionReason reason);
    event UserUnsuspended(address indexed user, uint256 timestamp);
    event UserMetadataUpdated(address indexed user, string metadata);
    event VerificationExpired(address indexed user, uint256 timestamp);
    event VerificationRenewed(address indexed user, uint256 newExpiryTime);
    event BatchVerificationCompleted(uint256 userCount, uint256 timestamp);
    event ConfigurationUpdated(string parameter, uint256 newValue);

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier notSuspended(address user) {
        if (isSuspended[user] && block.timestamp < suspensionEndTime[user]) {
            revert UserVerification__UserSuspended(user);
        }
        _;
    }

    modifier validLevel(VerificationLevel level) {
        if (level > VerificationLevel.Admin) {
            revert UserVerification__InvalidVerificationLevel(level);
        }
        _;
    }

    modifier isAdmin() {
        if (verificationLevel[msg.sender] != VerificationLevel.Admin) {
            revert UserVerification__InsufficientLevel(msg.sender, VerificationLevel.Admin);
        }
        _;
    }

    modifier isOwner() {
        if (msg.sender != I_OWNER) {
            revert UserVerification__NotOwner();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor() {
        _verifyUserWithLevel(msg.sender, "", VerificationLevel.Admin);
        I_OWNER = msg.sender;
    }

    /*//////////////////////////////////////////////////////////////
                            VERIFICATION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function verifyUser(address user) external isAdmin {
        _verifyUserWithLevel(user, "", VerificationLevel.Basic);
    }

    function verifyUserWithMetadata(address user, string memory metadata, uint256 customDuration) external isAdmin {
        _verifyUserWithLevel(user, metadata, VerificationLevel.Basic);
        if (customDuration > 0 && customDuration != verificationDuration) {
            verificationExpiry[user] = block.timestamp + customDuration;
        }
    }

    function verifyUserWithLevel(address user, string memory metadata, VerificationLevel level)
        external
        isAdmin
        validLevel(level)
    {
        _verifyUserWithLevel(user, metadata, level);
    }

    function batchVerifyUsers(address[] calldata users, VerificationLevel level) external isAdmin validLevel(level) {
        if (users.length > maxBatchSize) {
            revert UserVerification__InvalidBatchSize();
        }

        uint256 successCount = 0;
        for (uint256 i = 0; i < users.length; i++) {
            if (!_verifiedUsers.contains(users[i]) && !isSuspended[users[i]]) {
                _verifyUserWithLevel(users[i], "", level);
                successCount++;
            }
        }

        emit BatchVerificationCompleted(successCount, block.timestamp);
    }

    function batchVerifyUsersWithLevels(address[] calldata users, VerificationLevel[] calldata levels)
        external
        isAdmin
    {
        if (users.length != levels.length || users.length > maxBatchSize) {
            revert UserVerification__InvalidBatchSize();
        }

        uint256 successCount = 0;
        for (uint256 i = 0; i < users.length; i++) {
            if (levels[i] <= VerificationLevel.Admin && !_verifiedUsers.contains(users[i]) && !isSuspended[users[i]]) {
                _verifyUserWithLevel(users[i], "", levels[i]);
                successCount++;
            }
        }

        emit BatchVerificationCompleted(successCount, block.timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                            SUSPENSION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function suspendUser(address user, uint256 duration, SuspensionReason reason) external isAdmin {
        if (!_verifiedUsers.contains(user)) {
            revert UserVerification__UserNotVerified(user);
        }
        if (duration == 0) {
            revert UserVerification__InvalidSuspensionDuration();
        }

        isSuspended[user] = true;
        suspensionEndTime[user] = block.timestamp + duration;
        suspensionReason[user] = reason;
        totalSuspensions++;

        emit UserSuspended(user, suspensionEndTime[user], reason);
    }

    function unsuspendUser(address user) external isAdmin {
        if (!isSuspended[user]) {
            revert UserVerification__UserNotSuspended(user);
        }

        isSuspended[user] = false;
        suspensionEndTime[user] = 0;
        suspensionReason[user] = SuspensionReason.None;

        emit UserUnsuspended(user, block.timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                            LEVEL MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    function upgradeUserLevel(address user, VerificationLevel newLevel)
        external
        isAdmin
        validLevel(newLevel)
        notSuspended(user)
    {
        if (!_verifiedUsers.contains(user)) {
            revert UserVerification__UserNotVerified(user);
        }
        if (_isVerificationExpired(user)) {
            revert UserVerification__VerificationExpired(user);
        }

        VerificationLevel oldLevel = verificationLevel[user];
        if (newLevel <= oldLevel) {
            revert UserVerification__UpgradeToSameOrLowerLevel();
        }

        // FIXED: Synchronized level counting
        _updateLevelCounts(oldLevel, newLevel);
        verificationLevel[user] = newLevel;

        emit UserLevelUpgraded(user, oldLevel, newLevel);
    }

    function downgradeUserLevel(address user, VerificationLevel newLevel) external isAdmin validLevel(newLevel) {
        if (!_verifiedUsers.contains(user)) {
            revert UserVerification__UserNotVerified(user);
        }

        VerificationLevel oldLevel = verificationLevel[user];
        if (newLevel >= oldLevel) {
            revert UserVerification__DowngradeToSameOrHigherLevel();
        }

        // FIXED: Synchronized level counting
        _updateLevelCounts(oldLevel, newLevel);
        verificationLevel[user] = newLevel;

        emit UserLevelDowngraded(user, oldLevel, newLevel);
    }

    /*//////////////////////////////////////////////////////////////
                            RENEWAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function renewVerification(address user, uint256 additionalDuration) external isAdmin notSuspended(user) {
        if (!_verifiedUsers.contains(user)) {
            revert UserVerification__UserNotVerified(user);
        }

        uint256 currentExpiry = verificationExpiry[user];
        uint256 newExpiry;

        if (_isVerificationExpired(user)) {
            // If expired, start from current time
            newExpiry = block.timestamp + (additionalDuration > 0 ? additionalDuration : verificationDuration);
        } else {
            // If not expired, extend from current expiry
            newExpiry = currentExpiry + (additionalDuration > 0 ? additionalDuration : verificationDuration);
        }

        verificationExpiry[user] = newExpiry;
        emit VerificationRenewed(user, newExpiry);
    }

    function revokeUser(address user) external isAdmin {
        if (!_verifiedUsers.remove(user)) {
            revert UserVerification__UserNotVerified(user);
        }

        VerificationLevel level = verificationLevel[user];

        // FIXED: Proper level count management
        if (levelCounts[level] > 0) {
            levelCounts[level]--;
        }

        // Clean up all user data
        delete verificationTime[user];
        delete verificationExpiry[user];
        delete userMetadata[user];
        delete verificationLevel[user];
        delete verificationAttempts[user];
        delete lastVerificationAttempt[user];

        emit UserRevoked(user, block.timestamp);
    }

    function updateUserMetadata(address user, string memory metadata) external isAdmin notSuspended(user) {
        if (!_verifiedUsers.contains(user)) {
            revert UserVerification__UserNotVerified(user);
        }

        userMetadata[user] = metadata;
        emit UserMetadataUpdated(user, metadata);
    }

    /**
     * @dev FIXED: Automatic expiration with proper cleanup
     */
    function expireOldVerifications(address[] calldata users) external isAdmin {
        for (uint256 i = 0; i < users.length; i++) {
            if (_verifiedUsers.contains(users[i]) && _isVerificationExpired(users[i])) {
                _expireUser(users[i]);
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                        CONFIGURATION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function setVerificationDuration(uint256 _duration) external isOwner {
        if (_duration < 30 days || _duration > 5 * 365 days) {
            revert UserVerification__InvalidDuration();
        }
        verificationDuration = _duration;
        emit ConfigurationUpdated("verificationDuration", _duration);
    }

    function setMaxBatchSize(uint256 _size) external isOwner {
        if (_size < 10 || _size > 1000) {
            revert UserVerification__InvalidMaxBatchSize();
        }
        maxBatchSize = _size;
        emit ConfigurationUpdated("maxBatchSize", _size);
    }

    function setMaxVerificationAttempts(uint256 _attempts) external isOwner {
        if (_attempts < 1 || _attempts > 10) {
            revert UserVerification__InvalidMaxAttempts();
        }
        maxVerificationAttempts = _attempts;
        emit ConfigurationUpdated("maxVerificationAttempts", _attempts);
    }

    function setVerificationCooldown(uint256 _cooldown) external isOwner {
        if (_cooldown < 1 hours || _cooldown > 7 days) {
            revert UserVerification__InvalidCooldown();
        }
        verificationCooldown = _cooldown;
        emit ConfigurationUpdated("verificationCooldown", _cooldown);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function isVerifiedAndActive(address user) external view returns (bool) {
        return _verifiedUsers.contains(user) && !_isUserSuspended(user) && !_isVerificationExpired(user);
    }

    function isVerified(address user) external view returns (bool) {
        return _verifiedUsers.contains(user);
    }

    function hasMinimumLevel(address user, VerificationLevel minLevel) external view returns (bool) {
        return _verifiedUsers.contains(user) && !_isUserSuspended(user) && !_isVerificationExpired(user)
            && verificationLevel[user] >= minLevel;
    }

    function getUserStatus(address user)
        external
        view
        returns (
            bool _isVerified,
            VerificationLevel level,
            uint256 verifiedAt,
            uint256 expiresAt,
            bool suspended,
            uint256 suspendedUntil,
            SuspensionReason suspendedReason
        )
    {
        _isVerified = _verifiedUsers.contains(user);
        level = verificationLevel[user];
        verifiedAt = verificationTime[user];
        expiresAt = verificationExpiry[user];
        suspended = _isUserSuspended(user);
        suspendedUntil = suspensionEndTime[user];
        suspendedReason = suspensionReason[user];
    }

    /**
     * @dev FIXED: Accurate verification statistics
     */
    function getVerificationStats()
        external
        view
        returns (
            uint256 totalVerified,
            uint256 totalActive,
            uint256 totalSuspended,
            uint256 totalExpired,
            uint256[5] memory levelDistribution
        )
    {
        totalVerified = _verifiedUsers.length();
        totalSuspended = totalSuspensions;
        totalExpired = totalExpirations;

        // Count active users
        for (uint256 i = 0; i < _verifiedUsers.length(); i++) {
            address user = _verifiedUsers.at(i);
            if (!_isUserSuspended(user) && !_isVerificationExpired(user)) {
                totalActive++;
            }
        }

        // Level distribution from synchronized counts
        levelDistribution[0] = levelCounts[VerificationLevel.None];
        levelDistribution[1] = levelCounts[VerificationLevel.Basic];
        levelDistribution[2] = levelCounts[VerificationLevel.Premium];
        levelDistribution[3] = levelCounts[VerificationLevel.VIP];
        levelDistribution[4] = levelCounts[VerificationLevel.Admin];
    }

    function getUsersByLevel(VerificationLevel level, bool onlyActive) external view returns (address[] memory) {
        uint256 totalVerified = _verifiedUsers.length();

        // First pass: count matching users
        uint256 count = 0;
        for (uint256 i = 0; i < totalVerified; i++) {
            address user = _verifiedUsers.at(i);
            if (verificationLevel[user] == level) {
                if (!onlyActive || (!_isUserSuspended(user) && !_isVerificationExpired(user))) {
                    count++;
                }
            }
        }

        // Second pass: populate result
        address[] memory result = new address[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < totalVerified; i++) {
            address user = _verifiedUsers.at(i);
            if (verificationLevel[user] == level) {
                if (!onlyActive || (!_isUserSuspended(user) && !_isVerificationExpired(user))) {
                    result[index] = user;
                    index++;
                }
            }
        }

        return result;
    }

    function getVerifiedUsers(uint256 offset, uint256 limit, bool onlyActive)
        external
        view
        returns (address[] memory)
    {
        uint256 count = _verifiedUsers.length();
        if (offset >= count) {
            revert UserVerification__OffsetOutOfBounds();
        }

        uint256 end = offset + limit > count ? count : offset + limit;

        if (!onlyActive) {
            // Simple case: return all users in range
            address[] memory _result = new address[](end - offset);
            for (uint256 i = 0; i < _result.length; i++) {
                _result[i] = _verifiedUsers.at(offset + i);
            }
            return _result;
        }

        // Complex case: filter active users
        address[] memory temp = new address[](end - offset);
        uint256 resultCount = 0;

        for (uint256 i = offset; i < end; i++) {
            address user = _verifiedUsers.at(i);
            if (!_isUserSuspended(user) && !_isVerificationExpired(user)) {
                temp[resultCount] = user;
                resultCount++;
            }
        }

        // Create final result array with correct size
        address[] memory result = new address[](resultCount);
        for (uint256 i = 0; i < resultCount; i++) {
            result[i] = temp[i];
        }

        return result;
    }

    // Compatibility functions
    function getUserLevel(address user) external view returns (VerificationLevel) {
        return verificationLevel[user];
    }

    function getVerificationTime(address user) external view returns (uint256) {
        return verificationTime[user];
    }

    function getUserMetadata(address user) external view returns (string memory) {
        return userMetadata[user];
    }

    function getVerifiedUsersCount() external view returns (uint256) {
        return _verifiedUsers.length();
    }

    function wasVerifiedBefore(address user, uint256 timestamp) external view returns (bool) {
        return _verifiedUsers.contains(user) && verificationTime[user] <= timestamp;
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev FIXED: Rate limiting with proper error handling
     */
    function _verifyUserWithLevel(address user, string memory metadata, VerificationLevel level) internal {
        // FIXED: Rate limiting with custom error instead of string revert
        if (lastVerificationAttempt[user] + verificationCooldown > block.timestamp) {
            if (verificationAttempts[user] >= maxVerificationAttempts) {
                revert UserVerification__RateLimitExceeded(user);
            }
        } else {
            verificationAttempts[user] = 0; // Reset counter after cooldown
        }

        if (!_verifiedUsers.add(user)) {
            revert UserVerification__UserAlreadyVerified(user);
        }

        // Set verification data
        verificationTime[user] = block.timestamp;
        verificationExpiry[user] = block.timestamp + verificationDuration;
        verificationLevel[user] = level;
        verificationAttempts[user]++;
        lastVerificationAttempt[user] = block.timestamp;

        // FIXED: Synchronized level count updates
        levelCounts[level]++;

        if (bytes(metadata).length > 0) {
            userMetadata[user] = metadata;
            emit UserMetadataUpdated(user, metadata);
        }

        emit UserVerified(user, block.timestamp, level, verificationExpiry[user]);
    }

    /**
     * @dev FIXED: Proper expiration with level count updates
     */
    function _expireUser(address user) internal {
        if (_verifiedUsers.remove(user)) {
            VerificationLevel level = verificationLevel[user];

            // FIXED: Proper level count management
            if (levelCounts[level] > 0) {
                levelCounts[level]--;
            }

            totalExpirations++;
            emit VerificationExpired(user, block.timestamp);
            // Keep data for potential renewal
        }
    }

    /**
     * @dev FIXED: Atomic level count updates
     */
    function _updateLevelCounts(VerificationLevel oldLevel, VerificationLevel newLevel) internal {
        if (levelCounts[oldLevel] > 0) {
            levelCounts[oldLevel]--;
        }
        levelCounts[newLevel]++;
    }

    function _isUserSuspended(address user) internal view returns (bool) {
        return isSuspended[user] && block.timestamp < suspensionEndTime[user];
    }

    function _isVerificationExpired(address user) internal view returns (bool) {
        return block.timestamp >= verificationExpiry[user];
    }
}
