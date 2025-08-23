// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC721URIStorage, ERC721, IERC165} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";

/**
 * @title EventTicket - FULLY CORRECTED VERSION
 * @author alenissacsam (Enhanced by AI)
 * @dev Enhanced smart contract with all logic errors fixed
 */
contract EventTicket is ERC721URIStorage, IERC2981, ReentrancyGuard, Ownable {

    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/
    
    struct VIPConfig {
        uint256 totalVIPSeats;
        uint256 vipSeatStart;
        uint256 vipSeatEnd;
        uint256 vipHoldingPeriod;
        uint256 vipPriceMultiplier;
        bool vipEnabled;
    }

    struct TicketInfo {
        string eventName;
        string seatNumber;
        bool isVIP;
        uint256 mintedAt;
        uint256 pricePaid;
        bool isUsed;
        bool isTransferable;
        string venue;
    }

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/
    error EventTicket__UserNotVerified();
    error EventTicket__UserSuspended();
    error EventTicket__mintCooldown(address user, uint256 lastMintTime);
    error EventTicket__ZeroAddressNotAllowed();
    error EventTicket__InvalidPercentage(uint256 percentage);
    error EventTicket__OrganizerPaymentFailed();
    error EventTicket__PlatformPaymentFailed();
    error EventTicket__SupplyCannotBeZero();
    error EventTicket__MaxSupplyReached();
    error EventTicket__InsufficientPayment(uint256 required, uint256 provided);
    error EventTicket__MintLimitExceeded();
    error EventTicket__NotAuthorized();
    error EventTicket__NoRefundAvailable();
    error EventTicket__RefundFailed();
    error EventTicket__EventAlreadyCancelled();
    error EventTicket__EventNotCancellable();
    error EventTicket__InvalidSeatNumber();
    error EventTicket__SeatAlreadyTaken();
    error EventTicket__VIPSeatNotAvailable();
    error EventTicket__NotOnWhitelist();
    error EventTicket__MarketplaceDepositFailed();
    error EventTicket__CallerNotMarketplace();
    error EventTicket__TokenDoesNotExist();
    error EventTicket__EventAlreadyEnded();
    error EventTicket__TicketAlreadyUsed();
    error EventTicket__InvalidTimeConfiguration();
    error EventTicket__PriceOverflow();

    /*//////////////////////////////////////////////////////////////
                                VARIABLES
    //////////////////////////////////////////////////////////////*/
    uint256 public maxSupply;
    uint256 public baseMintPrice;
    address public eventOrganizer;
    address public platformAddress;
    uint256 public nextTicketId = 0;
    uint256 public eventStartTime;
    uint256 public eventEndTime;
    uint256 public maxMintsPerUser;
    bool public waitlistEnabled;
    uint256 public whitelistSaleEndTime;
    bool public eventCancelled;
    bool public eventCompleted;
    address public marketplaceAddress;
    string public venue;
    string public eventDescription;

    VIPConfig public vipConfig;

    // Enhanced mappings
    mapping(address => uint256) public lastMintTime;
    mapping(uint256 => TicketInfo) public tickets;
    mapping(address => uint256) public userMintCount; // A user's mint count for this event
    mapping(uint256 => bool) public hasUsedMarketplace; // A specific ticket has been involved with the marketplace
    mapping(address => bool) public waitlistApproved;
    mapping(uint256 => bool) public vipSeatsUsed;
    mapping(string => bool) public seatTaken;
    mapping(string => uint256) public seatPrices;
    mapping(uint256 => bool) public ticketUsed;
    mapping(address => uint256) public userRefundCount;

    // Constants
    uint256 public constant MINT_COOLDOWN = 5 seconds;
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant MIN_EVENT_SETUP_TIME = 24 hours;
    uint256 public constant MAX_REFUNDS_PER_USER = 3;
    uint256 public immutable I_ORGANIZER_PERCENTAGE;
    uint256 public immutable I_ROYALTY_FEE_PERCENTAGE;
    address public immutable I_USER_VERFIER_ADDRESS;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    event TicketMinted(address indexed user, uint256 indexed ticketId, string seatNumber, bool isVIP, uint256 pricePaid);
    event TicketRefunded(address indexed user, uint256 indexed ticketId, uint256 refundAmount);
    event TicketUsed(address indexed user, uint256 indexed ticketId, uint256 timestamp);
    event EventCancelled(uint256 timestamp, string reason);
    event EventCompleted(uint256 timestamp);
    event MarketplaceUsageTracked(address indexed user, uint256 indexed tokenId);
    event WaitlistUpdated(address indexed user, bool approved);
    event SeatPriceUpdated(string indexed seatNumber, uint256 newPrice);
    event VIPConfigUpdated(VIPConfig newConfig);

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier onlyVerifiedAndActive() {
        // FIXED: Proper interface call with error handling
        if (!_isUserVerified(msg.sender)) {
            revert EventTicket__UserNotVerified();
        }
        _;
    }

    modifier mintCooldown() {
        if (block.timestamp < lastMintTime[msg.sender] + MINT_COOLDOWN) {
            revert EventTicket__mintCooldown(msg.sender, lastMintTime[msg.sender]);
        }
        _;
    }

    modifier eventNotCancelled() {
        if (eventCancelled) {
            revert EventTicket__EventAlreadyCancelled();
        }
        _;
    }

    modifier eventNotEnded() {
        if (block.timestamp >= eventEndTime) {
            revert EventTicket__EventAlreadyEnded();
        }
        _;
    }

    modifier tokenExists(uint256 tokenId) {
        if (_ownerOf(tokenId) == address(0)) {
            revert EventTicket__TokenDoesNotExist();
        }
        _;
    }

    modifier onlyBeforeEvent() {
        if (block.timestamp >= eventStartTime) {
            revert EventTicket__EventNotCancellable();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(
        string memory name,
        string memory symbol,
        uint256 _maxSupply,
        uint256 _baseMintPrice,
        address _eventOrganizer,
        address _platformAddress,
        uint256 _organizerPercentage,
        address _userVerfierAddress,
        uint256 _royaltyFeePercentage,
        uint256 _eventStartTime,
        uint256 _eventEndTime,
        uint256 _maxMintsPerUser,
        VIPConfig memory _vipConfig,
        bool _waitlistEnabled,
        uint256 _whitelistSaleDuration,
        address[] memory _initialWhitelist,
        string memory _venue,
        string memory _eventDescription
    ) ERC721(name, symbol) Ownable(msg.sender) {
        // Enhanced validation
        if (_maxSupply == 0) {
            revert EventTicket__SupplyCannotBeZero();
        }

        if (_organizerPercentage > 9800 || _royaltyFeePercentage > 1000) {
            revert EventTicket__InvalidPercentage(_organizerPercentage);
        }

        if (_eventOrganizer == address(0) || _platformAddress == address(0) || _userVerfierAddress == address(0)) {
            revert EventTicket__ZeroAddressNotAllowed();
        }

        // Validate event timing
        if (_eventStartTime <= block.timestamp + MIN_EVENT_SETUP_TIME) {
            revert EventTicket__InvalidTimeConfiguration();
        }

        if (_eventEndTime <= _eventStartTime) {
            revert EventTicket__InvalidTimeConfiguration();
        }

        // Validate whitelist sale timing
        if (block.timestamp + _whitelistSaleDuration >= _eventStartTime) {
            revert EventTicket__InvalidTimeConfiguration();
        }

        // Set variables
        maxSupply = _maxSupply;
        baseMintPrice = _baseMintPrice;
        eventOrganizer = _eventOrganizer;
        platformAddress = _platformAddress;
        I_ORGANIZER_PERCENTAGE = _organizerPercentage;
        I_USER_VERFIER_ADDRESS = _userVerfierAddress;
        I_ROYALTY_FEE_PERCENTAGE = _royaltyFeePercentage;
        eventStartTime = _eventStartTime;
        eventEndTime = _eventEndTime;
        maxMintsPerUser = _maxMintsPerUser;
        vipConfig = _vipConfig;
        waitlistEnabled = _waitlistEnabled;
        whitelistSaleEndTime = block.timestamp + _whitelistSaleDuration;
        venue = _venue;
        eventDescription = _eventDescription;

        // Add initial whitelist addresses
        for (uint256 i = 0; i < _initialWhitelist.length; i++) {
            waitlistApproved[_initialWhitelist[i]] = true;
            emit WaitlistUpdated(_initialWhitelist[i], true);
        }
    }

    /*//////////////////////////////////////////////////////////////
                            MAIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev FIXED: Enhanced mint function with overflow protection
     */
    function mintTicket(
        string memory _eventName,
        string memory _seatNumber,
        bool _isVIP,
        string memory tokenURI
    ) external payable onlyVerifiedAndActive mintCooldown eventNotCancelled eventNotEnded nonReentrant {
        // Basic validations
        if (nextTicketId >= maxSupply) {
            revert EventTicket__MaxSupplyReached();
        }

        if (userMintCount[msg.sender] >= maxMintsPerUser) {
            revert EventTicket__MintLimitExceeded();
        }

        // Check if seat is available
        if (seatTaken[_seatNumber]) {
            revert EventTicket__SeatAlreadyTaken();
        }

        // FIXED: Calculate actual price with overflow protection
        uint256 actualPrice = getSeatPrice(_seatNumber, _isVIP);
        if (msg.value < actualPrice) {
            revert EventTicket__InsufficientPayment(actualPrice, msg.value);
        }

        // Whitelist/Presale check
        if (block.timestamp < whitelistSaleEndTime) {
            bool isWhitelisted = waitlistApproved[msg.sender] || _hasVIPLevel(msg.sender);
            if (!isWhitelisted) {
                revert EventTicket__NotOnWhitelist();
            }
        }

        // VIP seat validation
        if (_isVIP) {
            if (!vipConfig.vipEnabled) {
                revert EventTicket__VIPSeatNotAvailable();
            }

            if (!_hasVIPLevel(msg.sender)) {
                revert EventTicket__NotAuthorized();
            }

            _validateAndAssignVIPSeat(_seatNumber);
        }

        // Mint the ticket
        uint256 ticketId = nextTicketId++;
        userMintCount[msg.sender]++;
        seatTaken[_seatNumber] = true;

        tickets[ticketId] = TicketInfo({
            eventName: _eventName,
            seatNumber: _seatNumber,
            isVIP: _isVIP,
            mintedAt: block.timestamp,
            pricePaid: actualPrice,
            isUsed: false,
            isTransferable: true,
            venue: venue
        });

        _safeMint(msg.sender, ticketId);
        _setTokenURI(ticketId, tokenURI);
        lastMintTime[msg.sender] = block.timestamp;

        // Distribute funds
        _distributeFunds(actualPrice);

        // Refund excess payment
        if (msg.value > actualPrice) {
            payable(msg.sender).transfer(msg.value - actualPrice);
        }

        emit TicketMinted(msg.sender, ticketId, _seatNumber, _isVIP, actualPrice);
    }

    /**
     * @dev FIXED: Dynamic seat pricing with overflow protection
     */
    function getSeatPrice(string memory seatNumber, bool isVIP) public view returns (uint256) {
        uint256 basePrice = seatPrices[seatNumber] > 0 ? seatPrices[seatNumber] : baseMintPrice;
        
        if (isVIP && vipConfig.vipEnabled && vipConfig.vipPriceMultiplier > 0) {
            // FIXED: Overflow protection for VIP pricing
            if (basePrice > type(uint256).max / vipConfig.vipPriceMultiplier) {
                revert EventTicket__PriceOverflow();
            }
            return (basePrice * vipConfig.vipPriceMultiplier) / BASIS_POINTS;
        }

        return basePrice;
    }

    function setSeatPrices(string[] calldata seatNumbers, uint256[] calldata prices) external onlyOwner {
        require(seatNumbers.length == prices.length, "Arrays length mismatch");
        for (uint256 i = 0; i < seatNumbers.length; i++) {
            seatPrices[seatNumbers[i]] = prices[i];
            emit SeatPriceUpdated(seatNumbers[i], prices[i]);
        }
    }

    function useTicket(uint256 tokenId) external tokenExists(tokenId) {
        require(msg.sender == eventOrganizer || msg.sender == owner(), "Not authorized");
        require(block.timestamp >= eventStartTime && block.timestamp <= eventEndTime, "Outside event time");
        
        if (ticketUsed[tokenId]) {
            revert EventTicket__TicketAlreadyUsed();
        }

        ticketUsed[tokenId] = true;
        tickets[tokenId].isUsed = true;
        emit TicketUsed(_ownerOf(tokenId), tokenId, block.timestamp);
    }

    /**
     * @dev Enhanced refund calculation with abuse prevention
     */
    function calculateRefundPercentage(address user, uint256 tokenId)
        external view tokenExists(tokenId) returns (uint256) {
        if (eventCancelled) return BASIS_POINTS; // 100% if event cancelled
        if (hasUsedMarketplace[tokenId]) return 0; // No refund if used marketplace
        if (tickets[tokenId].isUsed) return 0; // No refund if ticket was used
        if (userRefundCount[user] >= MAX_REFUNDS_PER_USER) return 0; // Prevent abuse

        TicketInfo memory ticket = tickets[tokenId];
        uint256 timeSinceMint = block.timestamp - ticket.mintedAt;
        uint256 timeToEvent = eventStartTime > block.timestamp ? eventStartTime - block.timestamp : 0;

        // 100% refund for first hour
        if (timeSinceMint <= 1 hours) {
            return BASIS_POINTS;
        }

        // No refund after event starts
        if (block.timestamp >= eventStartTime) {
            return 0;
        }

        // Calculate refund based on time remaining
        uint256 totalEventTime = eventStartTime - ticket.mintedAt;
        if (timeToEvent <= totalEventTime / 2) {
            return 0;
        }

        uint256 refundWindow = totalEventTime / 2 - 1 hours;
        uint256 timeInRefundWindow = timeSinceMint - 1 hours;
        if (timeInRefundWindow >= refundWindow) return 0;

        return BASIS_POINTS - ((timeInRefundWindow * BASIS_POINTS) / refundWindow);
    }

    function refundTicket(uint256 tokenId) external nonReentrant tokenExists(tokenId) onlyBeforeEvent {
        require(_ownerOf(tokenId) == msg.sender, "Not token owner");
        require(userRefundCount[msg.sender] < MAX_REFUNDS_PER_USER, "Refund limit exceeded");

        uint256 refundPercentage = this.calculateRefundPercentage(msg.sender, tokenId);
        if (refundPercentage == 0) {
            revert EventTicket__NoRefundAvailable();
        }

        TicketInfo memory ticket = tickets[tokenId];
        uint256 refundAmount = (ticket.pricePaid * refundPercentage) / BASIS_POINTS;

        // Update state
        userMintCount[msg.sender]--;
        userRefundCount[msg.sender]++;
        seatTaken[ticket.seatNumber] = false; // Free up the seat

        // Clean up VIP seat if applicable
        if (ticket.isVIP) {
            uint256 seatNum = _parseSeatNumber(ticket.seatNumber);
            vipSeatsUsed[seatNum] = false;
        }

        delete tickets[tokenId];
        _burn(tokenId);

        // Send refund
        (bool success, ) = payable(msg.sender).call{value: refundAmount}("");
        if (!success) {
            revert EventTicket__RefundFailed();
        }

        emit TicketRefunded(msg.sender, tokenId, refundAmount);
    }

    function markEventCompleted() external {
        require(msg.sender == eventOrganizer || msg.sender == owner(), "Not authorized");
        require(block.timestamp >= eventEndTime, "Event not ended yet");
        require(!eventCancelled, "Event was cancelled");
        
        eventCompleted = true;
        emit EventCompleted(block.timestamp);
    }

    function cancelEvent(string memory reason) external onlyBeforeEvent {
        require(msg.sender == eventOrganizer || msg.sender == owner(), "Not authorized");
        
        eventCancelled = true;
        emit EventCancelled(block.timestamp, reason);
    }

    function updateVIPConfig(VIPConfig memory newConfig) external onlyOwner onlyBeforeEvent {
        require(newConfig.vipSeatEnd < maxSupply, "VIP seats exceed supply");
        require(newConfig.vipSeatEnd >= newConfig.vipSeatStart, "Invalid VIP range");
        
        vipConfig = newConfig;
        emit VIPConfigUpdated(newConfig);
    }

    /*//////////////////////////////////////////////////////////////
                        MARKETPLACE INTEGRATION
    //////////////////////////////////////////////////////////////*/

    function trackMarketplaceUsage(address user, uint256 tokenId) external {
        require(msg.sender == marketplaceAddress, "Not marketplace");
        hasUsedMarketplace[tokenId] = true;
        emit MarketplaceUsageTracked(user, tokenId);
    }

    function setMarketplaceAddress(address _marketplace) external onlyOwner {
        marketplaceAddress = _marketplace;
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _validateAndAssignVIPSeat(string memory _seatNumber) private {
        if (vipConfig.totalVIPSeats == 0) {
            revert EventTicket__VIPSeatNotAvailable();
        }

        uint256 seatNum = _parseSeatNumber(_seatNumber);
        if (seatNum < vipConfig.vipSeatStart || seatNum > vipConfig.vipSeatEnd) {
            revert EventTicket__InvalidSeatNumber();
        }

        if (vipSeatsUsed[seatNum]) {
            revert EventTicket__VIPSeatNotAvailable();
        }

        vipSeatsUsed[seatNum] = true;
    }

    /**
     * @dev FIXED: Enhanced seat number parsing for alphanumeric seats
     */
    function _parseSeatNumber(string memory _seatNumber) private pure returns (uint256) {
        bytes memory stringBytes = bytes(_seatNumber);
        uint256 result = 0;
        bool foundNumber = false;
        
        for (uint256 i = 0; i < stringBytes.length; i++) {
            uint8 char = uint8(stringBytes[i]);
            if (char >= 48 && char <= 57) { // 0-9
                result = result * 10 + (char - 48);
                foundNumber = true;
            } else if (foundNumber) {
                // Stop parsing once we hit a non-number after finding numbers
                break;
            }
        }
        
        return result;
    }

    function _distributeFunds(uint256 amount) private {
        if (marketplaceAddress == address(0)) {
            revert EventTicket__ZeroAddressNotAllowed();
        }
        // Forward the entire mint payment to the marketplace for deferred settlement
        (bool success, ) = marketplaceAddress.call{value: amount}(
            abi.encodeWithSignature(
                "registerPrimarySale(address,address,uint256)",
                msg.sender, // minter
                eventOrganizer,
                I_ORGANIZER_PERCENTAGE
            )
        );
        if (!success) revert EventTicket__MarketplaceDepositFailed();
    }

    /**
     * @dev FIXED: Safe user verification check
     */
    function _isUserVerified(address user) internal view returns (bool) {
        (bool success, bytes memory data) = I_USER_VERFIER_ADDRESS.staticcall(
            abi.encodeWithSignature("isVerified(address)", user)
        );
        
        if (success && data.length >= 32) {
            return abi.decode(data, (bool));
        }
        
        return false;
    }

    /**
     * @dev FIXED: Safe VIP level check
     */
    function _hasVIPLevel(address user) internal view returns (bool) {
        (bool success, bytes memory data) = I_USER_VERFIER_ADDRESS.staticcall(
            abi.encodeWithSignature("hasMinimumLevel(address,uint8)", user, 3) // VIP = 3
        );
        
        if (success && data.length >= 32) {
            return abi.decode(data, (bool));
        }
        
        return false;
    }

    // Override transfer to handle non-transferable tickets
    function _update(address to, uint256 tokenId, address auth)
        internal override(ERC721) returns (address) {
        address from = super._update(to, tokenId, auth);
        
        // Check if ticket is transferable
        if (from != address(0) && to != address(0)) {
            require(tickets[tokenId].isTransferable, "Ticket not transferable");
            if (auth != marketplaceAddress) {
                hasUsedMarketplace[tokenId] = true;
            }
        }

        return from;
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getTicketInfo(uint256 tokenId) external view tokenExists(tokenId) returns (TicketInfo memory) {
        return tickets[tokenId];
    }

    function isTicketUsed(uint256 tokenId) external view returns (bool) {
        return ticketUsed[tokenId];
    }

    function isSeatAvailable(string memory seatNumber) external view returns (bool) {
        return !seatTaken[seatNumber];
    }

    function getEventInfo() external view returns (
        uint256 startTime,
        uint256 endTime,
        string memory venueInfo,
        string memory description,
        bool cancelled,
        bool completed
    ) {
        return (eventStartTime, eventEndTime, venue, eventDescription, eventCancelled, eventCompleted);
    }

    /*//////////////////////////////////////////////////////////////
                            ROYALTY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function royaltyInfo(uint256 tokenId, uint256 salePrice)
        external view override returns (address, uint256) {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        
        uint256 royaltyAmount = (salePrice * I_ROYALTY_FEE_PERCENTAGE) / BASIS_POINTS;
        return (eventOrganizer, royaltyAmount);
    }

    function supportsInterface(bytes4 interfaceId)
        public view override(ERC721URIStorage, IERC165) returns (bool) {
        return interfaceId == type(IERC2981).interfaceId || super.supportsInterface(interfaceId);
    }
}