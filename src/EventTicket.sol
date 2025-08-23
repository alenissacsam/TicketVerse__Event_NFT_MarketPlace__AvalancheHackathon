// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC721URIStorage, ERC721, IERC165} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";
import {UserVerification} from "./UserVerification.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "./structs.sol";

/**
 * @title EventTicket
 * @author alenissacsam
 * @dev Enhanced smart contract for creating event tickets with refund system, VIP functionality, and anti-manipulation features.
 */

contract EventTicket is ERC721URIStorage, IERC2981, ReentrancyGuard, Ownable {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/
    error EventTicket__UserNotVerified();
    error EventTicket__mintCooldown(address user, uint256 lastMintTime);
    error EventTicket__ZeroAddressNotAllowed();
    error EventTicket__InvalidOrganizerPercentage(uint256 percentage);
    error EventTicket__OrganizerPaymentFailed();
    error EventTicket__PlatformPaymentFailed();
    error EventTicket__SupplyCannotBeZero();
    error EventTicket__MaxSupplyReached();
    error EventTicket__InsufficientPayment();
    error EventTicket__MintLimitExceeded();
    error EventTicket__NotAuthorized();
    error EventTicket__NoRefundAvailable();
    error EventTicket__RefundFailed();
    error EventTicket__EventAlreadyCancelled();
    error EventTicket__EventNotCancellable();
    error EventTicket__InvalidSeatNumber();
    error EventTicket__VIPSeatNotAvailable();
    error EventTicket__NotOnWhitelist();
    error EventTicket__CallerNotMarketplace();

    /*//////////////////////////////////////////////////////////////
                                VARIABLES
    //////////////////////////////////////////////////////////////*/
    uint256 public maxSupply;
    uint256 public mintPrice;
    address public eventOrganizer;
    address public platformAddress;
    uint256 public nextTicketId = 0;
    uint256 public eventStartTime;
    uint256 public maxMintsPerUser;
    bool public waitlistEnabled;
    uint256 public whitelistSaleEndTime;
    bool public eventCancelled;

    address public marketplaceAddress; // Address of the marketplace contract
    VIPConfig public vipConfig;

    // Mappings
    mapping(address => uint256) public lastMintTime;
    mapping(uint256 => TicketInfo) public tickets;
    mapping(address => uint256) public userMintCount;
    mapping(address => bool) public hasUsedMarketplace;
    mapping(address => bool) public waitlistApproved;
    mapping(uint256 => bool) public vipSeatsUsed; // Track which VIP seats are taken

    // Constants
    uint256 public constant MINT_COOLDOWN = 5 seconds;
    uint256 public constant BASIS_POINTS = 10000; // 100% = 10000 basis points
    uint256 public immutable I_ORGANIZER_PERCENTAGE;
    uint256 public immutable I_ROYALTY_FEE_PERCENTAGE;
    address public immutable I_USER_VERFIER_ADDRESS;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    event TicketMinted(
        address indexed user,
        uint256 indexed ticketId,
        string seatNumber,
        bool isVIP
    );
    event TicketRefunded(
        address indexed user,
        uint256 indexed ticketId,
        uint256 refundAmount
    );
    event EventCancelled(uint256 timestamp);
    event MarketplaceUsageTracked(
        address indexed user,
        uint256 indexed tokenId
    );
    event WaitlistUpdated(address indexed user, bool approved);

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier onlyVerified() {
        if (!UserVerification(I_USER_VERFIER_ADDRESS).isVerified(msg.sender)) {
            revert EventTicket__UserNotVerified();
        }
        _;
    }

    modifier mintCooldown() {
        if (block.timestamp < lastMintTime[msg.sender] + MINT_COOLDOWN) {
            revert EventTicket__mintCooldown(
                msg.sender,
                lastMintTime[msg.sender]
            );
        }
        _;
    }

    modifier eventNotCancelled() {
        if (eventCancelled) {
            revert EventTicket__EventAlreadyCancelled();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                                FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    constructor(
        string memory name,
        string memory symbol,
        uint256 _maxSupply,
        uint256 _mintPrice,
        address _eventOrganizer,
        address _platformAddress,
        uint256 _organizerPercentage,
        address _userVerfierAddress,
        uint256 _royaltyFeePercentage,
        uint256 _eventStartTime,
        uint256 _maxMintsPerUser,
        VIPConfig memory _vipConfig,
        bool _waitlistEnabled,
        uint256 _whitelistSaleDuration,
        address[] memory _initialWhitelist
    ) ERC721(name, symbol) Ownable(msg.sender) {
        if (_maxSupply == 0) {
            revert EventTicket__SupplyCannotBeZero();
        }

        if (_organizerPercentage > 9800 || _royaltyFeePercentage > 1000) {
            revert EventTicket__InvalidOrganizerPercentage(
                _organizerPercentage
            );
        }

        if (
            _eventOrganizer == address(0) ||
            _platformAddress == address(0) ||
            _userVerfierAddress == address(0)
        ) {
            revert EventTicket__ZeroAddressNotAllowed();
        }

        maxSupply = _maxSupply;
        mintPrice = _mintPrice;
        eventOrganizer = _eventOrganizer;
        platformAddress = _platformAddress;
        I_ORGANIZER_PERCENTAGE = _organizerPercentage;
        I_USER_VERFIER_ADDRESS = _userVerfierAddress;
        I_ROYALTY_FEE_PERCENTAGE = _royaltyFeePercentage;
        eventStartTime = _eventStartTime;
        maxMintsPerUser = _maxMintsPerUser;
        vipConfig = _vipConfig;
        waitlistEnabled = _waitlistEnabled;
        whitelistSaleEndTime = block.timestamp + _whitelistSaleDuration;

        // Add initial whitelist addresses provided at creation
        for (uint256 i = 0; i < _initialWhitelist.length; i++) {
            waitlistApproved[_initialWhitelist[i]] = true;
            emit WaitlistUpdated(_initialWhitelist[i], true);
        }
    }

    /**
     * @dev Enhanced mint function with all new features
     */
    function mintTicket(
        string memory _eventName,
        string memory _seatNumber,
        bool _isVIP,
        string memory tokenURI
    )
        external
        payable
        onlyVerified
        mintCooldown
        eventNotCancelled
        nonReentrant
    {
        if (nextTicketId >= maxSupply) {
            revert EventTicket__MaxSupplyReached();
        }

        if (msg.value < mintPrice) {
            revert EventTicket__InsufficientPayment();
        }

        if (userMintCount[msg.sender] >= maxMintsPerUser) {
            revert EventTicket__MintLimitExceeded();
        }

        // Whitelist / Presale check
        if (block.timestamp < whitelistSaleEndTime) {
            bool isWhitelisted = waitlistApproved[msg.sender] ||
                UserVerification(I_USER_VERFIER_ADDRESS).hasMinimumLevel(
                    msg.sender,
                    UserVerification.VerificationLevel.VIP
                );
            if (!isWhitelisted) {
                revert EventTicket__NotOnWhitelist();
            }
        }

        // Handle VIP seat logic
        if (_isVIP) {
            // Only users with VIP level in UserVerification can mint VIP tickets
            if (
                !UserVerification(I_USER_VERFIER_ADDRESS).hasMinimumLevel(
                    msg.sender,
                    UserVerification.VerificationLevel.VIP
                )
            ) {
                revert EventTicket__NotAuthorized();
            }
            _validateAndAssignVIPSeat(_seatNumber);
        }

        uint256 ticketId = nextTicketId++;
        userMintCount[msg.sender]++;

        tickets[ticketId] = TicketInfo({
            eventName: _eventName,
            seatNumber: _seatNumber,
            isVIP: _isVIP,
            mintedAt: block.timestamp
        });

        _safeMint(msg.sender, ticketId);
        _setTokenURI(ticketId, tokenURI);
        lastMintTime[msg.sender] = block.timestamp;

        // Distribute funds
        _distributeFunds(msg.value);

        emit TicketMinted(msg.sender, ticketId, _seatNumber, _isVIP);
    }

    /**
     * @dev Calculate refund percentage based on time elapsed and event timing
     */
    function calculateRefundPercentage(
        address user,
        uint256 tokenId
    ) public view returns (uint256) {
        if (eventCancelled) return BASIS_POINTS; // 100% if event cancelled
        if (hasUsedMarketplace[user]) return 0; // No refund if used marketplace
        if (_ownerOf(tokenId) == address(0)) return 0; // Token doesn't exist or was burned

        TicketInfo memory ticket = tickets[tokenId];
        uint256 timeSinceMint = block.timestamp - ticket.mintedAt;
        uint256 timeToEvent = eventStartTime > block.timestamp
            ? eventStartTime - block.timestamp
            : 0;

        // 100% refund for first hour
        if (timeSinceMint <= 1 hours) {
            return BASIS_POINTS;
        }

        // Calculate total time from mint to event
        uint256 totalEventTime = eventStartTime - ticket.mintedAt;

        // No refund when less than half time remains to event
        if (timeToEvent <= totalEventTime / 2) {
            return 0;
        }

        // Linear decrease from 100% to 0% over the refund window
        uint256 refundWindow = totalEventTime / 2 - 1 hours; // Exclude first hour
        uint256 timeInRefundWindow = timeSinceMint - 1 hours;

        if (timeInRefundWindow >= refundWindow) return 0;

        return
            BASIS_POINTS - ((timeInRefundWindow * BASIS_POINTS) / refundWindow);
    }

    /**
     * @dev Refund ticket with calculated percentage
     */
    function refundTicket(uint256 tokenId) external nonReentrant {
        if (_ownerOf(tokenId) != msg.sender) {
            revert EventTicket__NotAuthorized();
        }

        uint256 refundPercentage = calculateRefundPercentage(
            msg.sender,
            tokenId
        );
        if (refundPercentage == 0) {
            revert EventTicket__NoRefundAvailable();
        }

        uint256 refundAmount = (mintPrice * refundPercentage) / BASIS_POINTS;

        // Update state before external call
        userMintCount[msg.sender]--;
        delete tickets[tokenId]; // Clean up storage
        _burn(tokenId);

        // Send refund
        (bool success, ) = payable(msg.sender).call{value: refundAmount}("");
        if (!success) {
            revert EventTicket__RefundFailed();
        }

        emit TicketRefunded(msg.sender, tokenId, refundAmount);
    }

    /**
     * @dev Cancel event (only organizer) - triggers full refunds
     */
    function cancelEvent() external {
        if (msg.sender != eventOrganizer && msg.sender != owner()) {
            revert EventTicket__NotAuthorized();
        }

        if (block.timestamp >= eventStartTime) {
            revert EventTicket__EventNotCancellable();
        }

        eventCancelled = true;
        emit EventCancelled(block.timestamp);
    }

    /**
     * @dev Track when user uses marketplace (called by marketplace contract)
     */
    function trackMarketplaceUsage(address user, uint256 tokenId) external {
        if (msg.sender != marketplaceAddress) {
            revert EventTicket__CallerNotMarketplace();
        }
        hasUsedMarketplace[user] = true;
        emit MarketplaceUsageTracked(user, tokenId);
    }

    /**
     * @dev Add users to waitlist (only owner)
     */
    function addToWaitlist(address[] calldata users) external onlyOwner {
        for (uint256 i = 0; i < users.length; i++) {
            waitlistApproved[users[i]] = true;
            emit WaitlistUpdated(users[i], true);
        }
    }

    /**
     * @dev Remove users from waitlist (only owner)
     */
    function removeFromWaitlist(address[] calldata users) external onlyOwner {
        for (uint256 i = 0; i < users.length; i++) {
            waitlistApproved[users[i]] = false;
            emit WaitlistUpdated(users[i], false);
        }
    }

    /**
     * @dev Sets the trusted marketplace address. Can only be called by the owner.
     */
    function setMarketplaceAddress(
        address _marketplaceAddress
    ) external onlyOwner {
        if (_marketplaceAddress == address(0)) {
            revert EventTicket__ZeroAddressNotAllowed();
        }
        marketplaceAddress = _marketplaceAddress;
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @dev See {ERC721-_update}.
     *
     * Overridden to track marketplace usage. If a transfer is initiated by an
     * account that is not the marketplace, we assume it's a peer-to-peer
     * transfer that uses a marketplace UI, thus disabling refunds for the seller.
     */
    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal override(ERC721) returns (address) {
        address from = super._update(to, tokenId, auth);

        // A transfer is when from and to are not zero.
        if (
            from != address(0) && to != address(0) && auth != marketplaceAddress
        ) {
            hasUsedMarketplace[from] = true;
        }

        return from;
    }

    function _validateAndAssignVIPSeat(string memory _seatNumber) private {
        if (vipConfig.totalVIPSeats == 0) {
            revert EventTicket__VIPSeatNotAvailable();
        }

        // Convert seat number to uint (assuming numeric seats)
        // This is simplified - implement proper seat validation logic
        uint256 seatNum = _parseSeatNumber(_seatNumber);

        if (
            seatNum < vipConfig.vipSeatStart || seatNum > vipConfig.vipSeatEnd
        ) {
            revert EventTicket__InvalidSeatNumber();
        }

        if (vipSeatsUsed[seatNum]) {
            revert EventTicket__VIPSeatNotAvailable();
        }

        vipSeatsUsed[seatNum] = true;
    }

    function _parseSeatNumber(
        string memory _seatNumber
    ) private pure returns (uint256) {
        // Simplified implementation - convert string to uint
        // In production, implement proper parsing logic for your seat format
        bytes memory stringBytes = bytes(_seatNumber);
        uint256 result = 0;

        for (uint256 i = 0; i < stringBytes.length; i++) {
            // ASCII '0' is 48, '9' is 57
            if (uint8(stringBytes[i]) >= 48 && uint8(stringBytes[i]) <= 57) {
                result = result * 10 + (uint8(stringBytes[i]) - 48);
            }
        }

        return result;
    }

    function _distributeFunds(uint256 amount) private {
        uint256 organizerShare = (amount * I_ORGANIZER_PERCENTAGE) /
            BASIS_POINTS;
        uint256 platformShare = amount - organizerShare;

        (bool sent1, ) = payable(eventOrganizer).call{value: organizerShare}(
            ""
        );
        if (!sent1) {
            revert EventTicket__OrganizerPaymentFailed();
        }

        (bool sent2, ) = payable(platformAddress).call{value: platformShare}(
            ""
        );
        if (!sent2) {
            revert EventTicket__PlatformPaymentFailed();
        }
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function getTicketInfo(
        uint256 tokenId
    ) external view returns (TicketInfo memory) {
        return tickets[tokenId];
    }

    function getRemainingRefundTime(
        uint256 tokenId
    ) external view returns (uint256) {
        if (_ownerOf(tokenId) == address(0)) return 0;

        TicketInfo memory ticket = tickets[tokenId];
        uint256 totalEventTime = eventStartTime - ticket.mintedAt;
        uint256 refundDeadline = ticket.mintedAt + (totalEventTime / 2);

        return
            refundDeadline > block.timestamp
                ? refundDeadline - block.timestamp
                : 0;
    }

    function isVIPSeatAvailable(
        uint256 seatNumber
    ) external view returns (bool) {
        return
            seatNumber >= vipConfig.vipSeatStart &&
            seatNumber <= vipConfig.vipSeatEnd &&
            !vipSeatsUsed[seatNumber];
    }

    /*//////////////////////////////////////////////////////////////
                            ROYALTY FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function royaltyInfo(
        uint256 tokenId,
        uint256 salePrice
    ) external view override returns (address receiver, uint256 royaltyAmount) {
        _requireOwned(tokenId);
        receiver = eventOrganizer;
        royaltyAmount = (salePrice * I_ROYALTY_FEE_PERCENTAGE) / BASIS_POINTS;
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC721URIStorage, IERC165) returns (bool) {
        return
            interfaceId == type(IERC2981).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
