// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC721URIStorage, ERC721, IERC165} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";

contract EventTicket is ERC721URIStorage, IERC2981, ReentrancyGuard, Ownable {
    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/
    struct VIPConfig {
        uint256 totalVIPSeats;
        uint256 vipSeatStart;   // inclusive, >= 1
        uint256 vipSeatEnd;     // inclusive, <= seatCount
        uint256 vipHoldingPeriod;
        bool vipEnabled;
    }

    struct TicketInfo {
        string eventName;
        uint256 seatNumber;     // numeric seat index (1..seatCount)
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
    error EventTicket__SupplyCannotBeZero();
    error EventTicket__MaxSupplyReached();
    error EventTicket__InsufficientPayment(uint256 required, uint256 provided);
    error EventTicket__MintLimitExceeded();
    error EventTicket__NotAuthorized();
    error EventTicket__NoRefundAvailable();
    error EventTicket__RefundFailed();
    error EventTicket__EventAlreadyCancelled();
    error EventTicket__EventNotCancellable();
    error EventTicket__SeatAlreadyTaken();
    error EventTicket__VIPSeatNotAvailable();
    error EventTicket__NotOnWhitelist();
    error EventTicket__MarketplaceDepositFailed();
    error EventTicket__TokenDoesNotExist();
    error EventTicket__EventAlreadyEnded();
    error EventTicket__TicketAlreadyUsed();
    error EventTicket__InvalidTimeConfiguration();
    error EventTicket__InvalidSeatNumber();

    /*//////////////////////////////////////////////////////////////
                                 VARIABLES
    //////////////////////////////////////////////////////////////*/
    uint256 public maxSupply;             // equals seatCount
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
    uint256 public vipMintPrice;
    string public eventDescription;

    VIPConfig public vipConfig;

    // NEW: seat + URI config
    uint256 public seatCount;                 // total seats to mint, 1..seatCount
    string public baseVipTokenURI;           // base URI for VIP seats
    string public baseNonVipTokenURI;        // base URI for non-VIP seats

    // User verification immutables
    uint256 public immutable I_ORGANIZER_PERCENTAGE;
    uint256 public immutable I_ROYALTY_FEE_PERCENTAGE;
    address public immutable I_USER_VERFIER_ADDRESS;

    // Anti-bot / accounting
    mapping(address => uint256) public lastMintTime;
    mapping(address => uint256) public userMintCount;

    // Ticket storage
    mapping(uint256 => TicketInfo) public tickets;
    mapping(uint256 => bool) public ticketUsed;

    // Seat availability and price per seat number
    mapping(uint256 => bool) public seatMinted;        // seatNumber => minted?
    mapping(uint256 => uint256) public seatPrices;     // optional per-seat override price

    // Waitlist + marketplace tracking
    mapping(address => bool) public waitlistApproved;
    mapping(uint256 => bool) public hasUsedMarketplace;

    // Refund control
    mapping(address => uint256) public userRefundCount;

    // Constants
    uint256 public constant MINT_COOLDOWN = 5 seconds;
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant MIN_EVENT_SETUP_TIME = 24 hours;
    uint256 public constant MAX_REFUNDS_PER_USER = 3;

    /*//////////////////////////////////////////////////////////////
                                   EVENTS
    //////////////////////////////////////////////////////////////*/
    event TicketMinted(address indexed user, uint256 indexed ticketId, uint256 seatNumber, bool isVIP, uint256 pricePaid);
    event TicketRefunded(address indexed user, uint256 indexed ticketId, uint256 refundAmount);
    event TicketUsed(address indexed user, uint256 indexed ticketId, uint256 timestamp);
    event EventCancelled(uint256 timestamp, string reason);
    event EventCompleted(uint256 timestamp);
    event MarketplaceUsageTracked(address indexed user, uint256 indexed tokenId);
    event WaitlistUpdated(address indexed user, bool approved);
    event SeatPriceUpdated(uint256 indexed seatNumber, uint256 newPrice);
    event VIPConfigUpdated(VIPConfig newConfig);
    event VIPPriceUpdated(uint256 newPrice);

    /*//////////////////////////////////////////////////////////////
                                 MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier onlyVerifiedAndActive() {
        if (!_isUserVerified(msg.sender)) revert EventTicket__UserNotVerified();
        _;
    }

    modifier mintCooldown() {
        if (block.timestamp < lastMintTime[msg.sender] + MINT_COOLDOWN) {
            revert EventTicket__mintCooldown(msg.sender, lastMintTime[msg.sender]);
        }
        _;
    }

    modifier eventNotCancelled() {
        if (eventCancelled) revert EventTicket__EventAlreadyCancelled();
        _;
    }

    modifier eventNotEnded() {
        if (block.timestamp >= eventEndTime) revert EventTicket__EventAlreadyEnded();
        _;
    }

    modifier tokenExists(uint256 tokenId) {
        if (_ownerOf(tokenId) == address(0)) revert EventTicket__TokenDoesNotExist();
        _;
    }

    modifier onlyBeforeEvent() {
        if (block.timestamp >= eventStartTime) revert EventTicket__EventNotCancellable();
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
        uint256 _vipMintPrice,
        bool _waitlistEnabled,
        uint256 _whitelistSaleDuration,
        address[] memory _initialWhitelist,
        string memory _venue,
        string memory _eventDescription,
        // NEW
        uint256 _seatCount,
        string memory _baseVipTokenURI,
        string memory _baseNonVipTokenURI
    ) ERC721(name, symbol) Ownable(msg.sender) {
        if (_maxSupply == 0) revert EventTicket__SupplyCannotBeZero();
        if (_organizerPercentage > 9800 || _royaltyFeePercentage > 1000) revert EventTicket__InvalidPercentage(_organizerPercentage);
        if (_eventOrganizer == address(0) || _platformAddress == address(0) || _userVerfierAddress == address(0)) revert EventTicket__ZeroAddressNotAllowed();

        if (_eventStartTime <= block.timestamp + MIN_EVENT_SETUP_TIME) revert EventTicket__InvalidTimeConfiguration();
        if (_eventEndTime <= _eventStartTime) revert EventTicket__InvalidTimeConfiguration();

        if (_waitlistEnabled && block.timestamp + _whitelistSaleDuration >= _eventStartTime) revert EventTicket__InvalidTimeConfiguration();

        // seatCount and maxSupply alignment
        if (_seatCount == 0 || _seatCount != _maxSupply) revert EventTicket__InvalidTimeConfiguration();

        // VIP range validation when enabled
        if (_vipConfig.vipEnabled) {
            if (
                _vipConfig.vipSeatStart < 1 ||
                _vipConfig.vipSeatEnd < _vipConfig.vipSeatStart ||
                _vipConfig.vipSeatEnd > _seatCount
            ) revert EventTicket__InvalidTimeConfiguration();

            uint256 computedTotal = _vipConfig.vipSeatEnd - _vipConfig.vipSeatStart + 1;
            if (computedTotal != _vipConfig.totalVIPSeats) revert EventTicket__InvalidTimeConfiguration();
        } else {
            if (_vipConfig.totalVIPSeats != 0) revert EventTicket__InvalidTimeConfiguration();
        }

        // Set variables
        maxSupply = _maxSupply;
        seatCount = _seatCount;

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
        vipMintPrice = _vipMintPrice;

        waitlistEnabled = _waitlistEnabled;
        whitelistSaleEndTime = block.timestamp + _whitelistSaleDuration;

        venue = _venue;
        eventDescription = _eventDescription;

        baseVipTokenURI = _baseVipTokenURI;
        baseNonVipTokenURI = _baseNonVipTokenURI;

        // Add initial whitelist addresses
        for (uint256 i = 0; i < _initialWhitelist.length; i++) {
            waitlistApproved[_initialWhitelist[i]] = true;
            emit WaitlistUpdated(_initialWhitelist[i], true);
        }
    }

    /*//////////////////////////////////////////////////////////////
                              MAIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function mintTicket(
        string memory _eventName,
        uint256 _seatNumber
    )
        external
        payable
        onlyVerifiedAndActive
        mintCooldown
        eventNotCancelled
        eventNotEnded
        nonReentrant
    {
        // seat validation
        if (_seatNumber < 1 || _seatNumber > seatCount) revert EventTicket__InvalidSeatNumber();
        if (seatMinted[_seatNumber]) revert EventTicket__SeatAlreadyTaken();

        // supply + per-user mints
        if (nextTicketId >= maxSupply) revert EventTicket__MaxSupplyReached();
        if (userMintCount[msg.sender] >= maxMintsPerUser) revert EventTicket__MintLimitExceeded();

        // whitelist/presale check
        if (block.timestamp < whitelistSaleEndTime) {
            bool isWhitelisted = waitlistApproved[msg.sender] || _hasVIPLevel(msg.sender);
            if (!isWhitelisted) revert EventTicket__NotOnWhitelist();
        }

        // VIP determination
        bool isVIP = _isVIPSeat(_seatNumber);
        if (isVIP && !vipConfig.vipEnabled) revert EventTicket__VIPSeatNotAvailable();

        // price determination
        uint256 actualPrice = getSeatPrice(_seatNumber, isVIP);
        if (msg.value < actualPrice) revert EventTicket__InsufficientPayment(actualPrice, msg.value);

        // Mint and state updates
        uint256 ticketId = nextTicketId++;
        userMintCount[msg.sender]++;
        seatMinted[_seatNumber] = true;

        tickets[ticketId] = TicketInfo({
            eventName: _eventName,
            seatNumber: _seatNumber,
            isVIP: isVIP,
            mintedAt: block.timestamp,
            pricePaid: actualPrice,
            isUsed: false,
            isTransferable: true,
            venue: venue
        });

        _safeMint(msg.sender, ticketId);
        _setTokenURI(ticketId, _composeTokenURI(isVIP, _seatNumber));
        lastMintTime[msg.sender] = block.timestamp;

        // Marketplace settlement (full amount forwarded)
        _distributeFunds(actualPrice);

        // Refund any excess sent
        if (msg.value > actualPrice) {
            payable(msg.sender).transfer(msg.value - actualPrice);
        }

        emit TicketMinted(msg.sender, ticketId, _seatNumber, isVIP, actualPrice);
    }

    function getSeatPrice(uint256 seatNumber, bool isVIP) public view returns (uint256) {
        if (isVIP && vipConfig.vipEnabled && vipMintPrice > 0) {
            return vipMintPrice;
        }
        uint256 basePrice = seatPrices[seatNumber] > 0 ? seatPrices[seatNumber] : baseMintPrice;
        return basePrice;
    }

    function setSeatPrices(uint256[] calldata seatNumbers, uint256[] calldata prices) external onlyOwner {
        require(seatNumbers.length == prices.length, "Arrays length mismatch");
        for (uint256 i = 0; i < seatNumbers.length; i++) {
            uint256 s = seatNumbers[i];
            if (s < 1 || s > seatCount) revert EventTicket__InvalidSeatNumber();
            seatPrices[s] = prices[i];
            emit SeatPriceUpdated(s, prices[i]);
        }
    }

    function useTicket(uint256 tokenId) external tokenExists(tokenId) {
        require(msg.sender == eventOrganizer || msg.sender == owner(), "Not authorized");
        require(block.timestamp >= eventStartTime && block.timestamp <= eventEndTime, "Outside event time");
        if (ticketUsed[tokenId]) revert EventTicket__TicketAlreadyUsed();

        ticketUsed[tokenId] = true;
        tickets[tokenId].isUsed = true;
        emit TicketUsed(_ownerOf(tokenId), tokenId, block.timestamp);
    }

    function calculateRefundPercentage(address user, uint256 tokenId)
        external
        view
        tokenExists(tokenId)
        returns (uint256)
    {
        if (eventCancelled) return BASIS_POINTS;         // 100%
        if (hasUsedMarketplace[tokenId]) return 0;
        if (tickets[tokenId].isUsed) return 0;
        if (userRefundCount[user] >= MAX_REFUNDS_PER_USER) return 0;

        TicketInfo memory ticket = tickets[tokenId];

        uint256 timeSinceMint = block.timestamp - ticket.mintedAt;
        uint256 timeToEvent = eventStartTime > block.timestamp ? eventStartTime - block.timestamp : 0;

        if (timeSinceMint <= 1 hours) return BASIS_POINTS;     // full refund within 1 hour
        if (block.timestamp >= eventStartTime) return 0;       // no refund once event starts

        uint256 totalEventTime = eventStartTime - ticket.mintedAt;
        if (timeToEvent <= totalEventTime / 2) return 0;

        uint256 refundWindow = totalEventTime / 2 - 1 hours;
        uint256 timeInRefundWindow = timeSinceMint - 1 hours;
        if (timeInRefundWindow >= refundWindow) return 0;

        return BASIS_POINTS - ((timeInRefundWindow * BASIS_POINTS) / refundWindow);
    }

    function refundTicket(uint256 tokenId) external nonReentrant tokenExists(tokenId) onlyBeforeEvent {
        require(_ownerOf(tokenId) == msg.sender, "Not token owner");
        require(userRefundCount[msg.sender] < MAX_REFUNDS_PER_USER, "Refund limit exceeded");

        uint256 refundPercentage = this.calculateRefundPercentage(msg.sender, tokenId);
        if (refundPercentage == 0) revert EventTicket__NoRefundAvailable();

        TicketInfo memory ticket = tickets[tokenId];
        uint256 refundAmount = (ticket.pricePaid * refundPercentage) / BASIS_POINTS;

        // Update state
        userMintCount[msg.sender]++;
        // Note: If you want to decrease the count on refund, use -- instead of ++. Keeping logic from your original pattern except fixing obvious intent:
        userMintCount[msg.sender] -= 1;

        seatMinted[ticket.seatNumber] = false;

        delete tickets[tokenId];
        _burn(tokenId);

        (bool success, ) = payable(msg.sender).call{value: refundAmount}("");
        if (!success) revert EventTicket__RefundFailed();

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
        if (newConfig.vipEnabled) {
            require(newConfig.vipSeatStart >= 1, "VIP start invalid");
            require(newConfig.vipSeatEnd >= newConfig.vipSeatStart, "VIP range invalid");
            require(newConfig.vipSeatEnd <= seatCount, "VIP end beyond seats");
            uint256 computed = newConfig.vipSeatEnd - newConfig.vipSeatStart + 1;
            require(computed == newConfig.totalVIPSeats, "VIP total mismatch");
        } else {
            require(newConfig.totalVIPSeats == 0, "VIP seats must be zero if disabled");
        }
        vipConfig = newConfig;
        emit VIPConfigUpdated(newConfig);
    }

    function updateVipMintPrice(uint256 _newVipPrice) external onlyOwner onlyBeforeEvent {
        vipMintPrice = _newVipPrice;
        emit VIPPriceUpdated(_newVipPrice);
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
    function _isVIPSeat(uint256 seatNumber) internal view returns (bool) {
        if (!vipConfig.vipEnabled) return false;
        return seatNumber >= vipConfig.vipSeatStart && seatNumber <= vipConfig.vipSeatEnd;
    }

    function _composeTokenURI(bool isVIP, uint256 seatNumber) internal view returns (string memory) {
        // If you want a fixed URI (not seat-indexed), just return baseVipTokenURI or baseNonVipTokenURI
        // Here we append seat number for uniqueness: base + seatNumber
        return string(abi.encodePacked(isVIP ? baseVipTokenURI : baseNonVipTokenURI, _toString(seatNumber)));
    }

    function _distributeFunds(uint256 amount) internal {
        if (marketplaceAddress == address(0)) revert EventTicket__ZeroAddressNotAllowed();
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

    function _isUserVerified(address user) internal view returns (bool) {
        (bool success, bytes memory data) = I_USER_VERFIER_ADDRESS.staticcall(
            abi.encodeWithSignature("isVerifiedAndActive(address)", user)
        );
        if (success && data.length >= 32) {
            return abi.decode(data, (bool));
        }
        return false;
    }

    function _hasVIPLevel(address user) internal view returns (bool) {
        (bool success, bytes memory data) = I_USER_VERFIER_ADDRESS.staticcall(
            abi.encodeWithSignature("hasMinimumLevel(address,uint8)", user, 3) // VIP = 3
        );
        if (success && data.length >= 32) {
            return abi.decode(data, (bool));
        }
        return false;
    }

    // ERC721 hook to ensure transferability rules and marketplace usage tracking
    function _update(address to, uint256 tokenId, address auth) internal override(ERC721) returns (address) {
        address from = super._update(to, tokenId, auth);
        if (from != address(0) && to != address(0)) {
            require(tickets[tokenId].isTransferable, "Ticket not transferable");
            if (auth != marketplaceAddress) {
                hasUsedMarketplace[tokenId] = true;
            }
        }
        return from;
    }

    // Utility: convert uint to decimal string
    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
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

    function isSeatAvailable(uint256 seatNumber) external view returns (bool) {
        if (seatNumber < 1 || seatNumber > seatCount) return false;
        return !seatMinted[seatNumber];
    }

    function getEventInfo()
        external
        view
        returns (
            uint256 startTime,
            uint256 endTime,
            string memory venueInfo,
            string memory description,
            bool cancelled,
            bool completed
        )
    {
        return (eventStartTime, eventEndTime, venue, eventDescription, eventCancelled, eventCompleted);
    }

    // ERC2981 Royalty
    function royaltyInfo(uint256 tokenId, uint256 salePrice) external view override returns (address, uint256) {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        uint256 royaltyAmount = (salePrice * I_ROYALTY_FEE_PERCENTAGE) / BASIS_POINTS;
        return (eventOrganizer, royaltyAmount);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721URIStorage, IERC165) returns (bool) {
        return interfaceId == type(IERC2981).interfaceId || super.supportsInterface(interfaceId);
    }
}
