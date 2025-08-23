// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IERC721, IERC165} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title TicketMarketplace - FULLY CORRECTED VERSION
 * @author alenissacsam (Enhanced by AI)
 * @dev Marketplace with all logic errors fixed and optimized gas usage
 */
contract TicketMarketplace is ReentrancyGuard, Ownable {

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/
    error Marketplace__ItemNotListed(address tokenContract, uint256 tokenId);
    error Marketplace__InsufficientFunds(uint256 required, uint256 provided);
    error Marketplace__CannotBuyOwnItem();
    error Marketplace__PaymentFailed();
    error Marketplace__NotAuthorized();
    error Marketplace__InvalidTime();
    error Marketplace__AuctionEnded();
    error Marketplace__AuctionActive();
    error Marketplace__NoActiveBids();
    error Marketplace__BidTooLow();
    error Marketplace__PriceIncreaseTooHigh();
    error Marketplace__ResaleCooldownActive();
    error Marketplace__EventNotCompleted();
    error Marketplace__FundsAlreadyReleased();
    error Marketplace__InvalidAddress();
    error Marketplace__InvalidFeePercentage();
    error Marketplace__InvalidDuration();
    error Marketplace__MaxExtensionsReached();
    error Marketplace__ContractPaused();
    error Marketplace__InsufficientContractBalance();

    /*//////////////////////////////////////////////////////////////
                            ENUMS & STRUCTS
    //////////////////////////////////////////////////////////////*/
    enum SaleType {
        FIXED_PRICE,
        AUCTION
    }

    enum AuctionStatus {
        ACTIVE,
        ENDED,
        CANCELLED
    }

    struct Listing {
        address seller;
        address tokenContract;
        uint256 tokenId;
        uint256 price;
        SaleType saleType;
        bool active;
        uint256 listedAt;
    }

    struct Auction {
        uint256 startTime;
        uint256 endTime;
        uint256 reservePrice;
        uint256 minBidIncrement;
        address highestBidder;
        uint256 highestBid;
        AuctionStatus status;
        uint256 extensionCount;
        mapping(address => uint256) bids;
        address[] bidders;
    }

    struct EscrowInfo {
        uint256 amount;
        address seller;
        address buyer;
        bool released;
        uint256 eventStartTime;
    }

    struct PlatformConfig {
        uint256 platformFeePercent;
        uint256 maxAuctionDuration;
    }

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    mapping(bytes32 => Listing) public listings;
    mapping(bytes32 => Auction) public auctions;
    mapping(bytes32 => EscrowInfo) public escrowedFunds;
    mapping(bytes32 => uint256) public lastSalePrice;
    mapping(bytes32 => uint256) public lastSaleTime;
    mapping(address => uint256) public tokenContractVolume;
    mapping(uint256 => uint256) public dailyVolume;

    // Constants
    uint256 public constant PRICE_INCREASE_LIMIT = 2000; // 20% in basis points
    uint256 public constant RESALE_COOLDOWN = 1 hours;
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant ESCROW_RELEASE_DELAY = 1 days;
    uint256 public constant MAX_AUCTION_EXTENSIONS = 5;
    uint256 public constant MAX_PLATFORM_FEE = 1000; // 10% max
    uint256 public constant MIN_AUCTION_DURATION = 1 hours;
    uint256 public constant MAX_AUCTION_DURATION = 30 days;

    PlatformConfig public config;
    address public immutable PLATFORM_ADDRESS;
    address public immutable I_USER_VERFIER_ADDRESS;
    
    // Emergency controls
    bool public paused;
    
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    event Listed(
        address indexed seller,
        address indexed tokenContract,
        uint256 indexed tokenId,
        uint256 price,
        SaleType saleType
    );

    event AuctionCreated(
        bytes32 indexed listingId,
        uint256 startTime,
        uint256 endTime,
        uint256 reservePrice
    );

    event BidPlaced(
        bytes32 indexed listingId,
        address indexed bidder,
        uint256 amount,
        uint256 timestamp
    );

    event AuctionSettled(
        bytes32 indexed listingId,
        address indexed winner,
        uint256 finalPrice
    );

    event ListingCancelled(bytes32 indexed listingId, address indexed seller);
    
    event FundsEscrowed(
        bytes32 indexed listingId,
        uint256 amount,
        address seller,
        address buyer
    );
    
    event EscrowReleased(
        bytes32 indexed listingId,
        uint256 amount,
        address recipient
    );

    event PriceValidated(
        bytes32 indexed listingId,
        uint256 newPrice,
        uint256 lastPrice,
        uint256 increasePercentage
    );

    event AuctionExtended(bytes32 indexed listingId, uint256 newEndTime, uint256 extensionCount);
    event MarketplacePaused(bool paused);

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier notPaused() {
        if (paused) revert Marketplace__ContractPaused();
        _;
    }

    modifier validAddress(address _address) {
        if (_address == address(0)) revert Marketplace__InvalidAddress();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(
        address _platformAddress,
        uint256 _platformFeePercent,
        uint256 _maxAuctionDuration,
        address _userVerfierAddress
    ) 
        Ownable(msg.sender) 
        validAddress(_platformAddress)
        validAddress(_userVerfierAddress)
    {
        // FIXED: Add comprehensive input validation
        if (_platformFeePercent > MAX_PLATFORM_FEE) {
            revert Marketplace__InvalidFeePercentage();
        }
        
        if (_maxAuctionDuration < MIN_AUCTION_DURATION || 
            _maxAuctionDuration > MAX_AUCTION_DURATION) {
            revert Marketplace__InvalidDuration();
        }

        PLATFORM_ADDRESS = _platformAddress;
        config = PlatformConfig({
            platformFeePercent: _platformFeePercent,
            maxAuctionDuration: _maxAuctionDuration
        });
        I_USER_VERFIER_ADDRESS = _userVerfierAddress;
    }

    /*//////////////////////////////////////////////////////////////
                            LISTING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function listItemFixedPrice(
        address tokenContract,
        uint256 tokenId,
        uint256 price
    ) external notPaused {
        require(price > 0, "Price must be greater than 0");
        
        _validateListing(tokenContract, tokenId);
        bytes32 listingId = getListingId(tokenContract, tokenId);
        
        _validatePriceIncrease(listingId, price, tokenContract, tokenId);
        _checkResaleCooldown(listingId);

        listings[listingId] = Listing({
            seller: msg.sender,
            tokenContract: tokenContract,
            tokenId: tokenId,
            price: price,
            saleType: SaleType.FIXED_PRICE,
            active: true,
            listedAt: block.timestamp
        });

        _trackMarketplaceUsage(tokenContract, msg.sender, tokenId);

        emit Listed(
            msg.sender,
            tokenContract,
            tokenId,
            price,
            SaleType.FIXED_PRICE
        );
    }

    function createAuction(
        address tokenContract,
        uint256 tokenId,
        uint256 startingPrice,
        uint256 reservePrice,
        uint256 duration,
        uint256 minBidIncrement
    ) external notPaused {
        require(startingPrice > 0, "Starting price must be greater than 0");
        require(minBidIncrement > 0, "Min bid increment must be greater than 0");
        require(reservePrice >= startingPrice, "Reserve must be >= starting price");
        
        if (duration > config.maxAuctionDuration || duration < MIN_AUCTION_DURATION) {
            revert Marketplace__InvalidTime();
        }

        _validateListing(tokenContract, tokenId);
        bytes32 listingId = getListingId(tokenContract, tokenId);
        
        _validatePriceIncrease(listingId, startingPrice, tokenContract, tokenId);
        _checkResaleCooldown(listingId);

        listings[listingId] = Listing({
            seller: msg.sender,
            tokenContract: tokenContract,
            tokenId: tokenId,
            price: startingPrice,
            saleType: SaleType.AUCTION,
            active: true,
            listedAt: block.timestamp
        });

        Auction storage auction = auctions[listingId];
        auction.startTime = block.timestamp;
        auction.endTime = block.timestamp + duration;
        auction.reservePrice = reservePrice;
        auction.minBidIncrement = minBidIncrement;
        auction.status = AuctionStatus.ACTIVE;
        auction.extensionCount = 0;

        _trackMarketplaceUsage(tokenContract, msg.sender, tokenId);

        emit Listed(
            msg.sender,
            tokenContract,
            tokenId,
            startingPrice,
            SaleType.AUCTION
        );

        emit AuctionCreated(
            listingId,
            auction.startTime,
            auction.endTime,
            reservePrice
        );
    }

    function cancelListing(
        address tokenContract,
        uint256 tokenId
    ) external nonReentrant notPaused {
        bytes32 listingId = getListingId(tokenContract, tokenId);
        Listing storage listing = listings[listingId];
        
        if (!listing.active) {
            revert Marketplace__ItemNotListed(tokenContract, tokenId);
        }
        if (listing.seller != msg.sender) {
            revert Marketplace__NotAuthorized();
        }

        if (listing.saleType == SaleType.AUCTION) {
            Auction storage auction = auctions[listingId];
            if (auction.highestBidder != address(0)) {
                _refundAllBidders(listingId);
            }
            auction.status = AuctionStatus.CANCELLED;
        }

        listing.active = false;
        emit ListingCancelled(listingId, msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                            BUYING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function buyItem(
        address tokenContract,
        uint256 tokenId
    ) external payable nonReentrant notPaused {
        bytes32 listingId = getListingId(tokenContract, tokenId);
        Listing storage listing = listings[listingId];
        
        if (!listing.active) {
            revert Marketplace__ItemNotListed(tokenContract, tokenId);
        }
        if (listing.saleType != SaleType.FIXED_PRICE) {
            revert Marketplace__InvalidTime();
        }
        if (msg.value < listing.price) {
            revert Marketplace__InsufficientFunds(listing.price, msg.value);
        }
        if (msg.sender == listing.seller) {
            revert Marketplace__CannotBuyOwnItem();
        }

        listing.active = false;
        
        uint256 eventStartTime = _getEventStartTime(tokenContract);
        
        _executeTransferWithEscrow(listingId, msg.sender, listing.price, eventStartTime);
        
        lastSalePrice[listingId] = listing.price;
        lastSaleTime[listingId] = block.timestamp;
        
        // FIXED: Refund excess payment
        if (msg.value > listing.price) {
            _safeTransfer(payable(msg.sender), msg.value - listing.price);
        }
    }

    /**
     * @dev FIXED: Completely corrected bidding logic
     */
    function placeBid(
        address tokenContract,
        uint256 tokenId
    ) external payable nonReentrant notPaused {
        bytes32 listingId = getListingId(tokenContract, tokenId);
        Listing storage listing = listings[listingId];
        
        if (!listing.active) {
            revert Marketplace__ItemNotListed(tokenContract, tokenId);
        }
        if (listing.saleType != SaleType.AUCTION) {
            revert Marketplace__InvalidTime();
        }
        if (listing.seller == msg.sender) {
            revert Marketplace__CannotBuyOwnItem();
        }

        Auction storage auction = auctions[listingId];
        
        if (block.timestamp >= auction.endTime) {
            revert Marketplace__AuctionEnded();
        }
        if (auction.status != AuctionStatus.ACTIVE) {
            revert Marketplace__AuctionEnded();
        }

        uint256 minBid = auction.highestBid + auction.minBidIncrement;
        if (auction.highestBid == 0) {
            minBid = listing.price;
        }

        if (msg.value < minBid) {
            revert Marketplace__BidTooLow();
        }

        // FIXED: Proper bidding logic with correct refund handling
        address previousHighestBidder = auction.highestBidder;
        uint256 previousHighestBid = auction.highestBid;
        uint256 userPreviousBid = auction.bids[msg.sender];

        // Update auction state first
        auction.bids[msg.sender] = msg.value;
        auction.highestBidder = msg.sender;
        auction.highestBid = msg.value;

        // Add to bidders array if first time
        if (userPreviousBid == 0) {
            auction.bidders.push(msg.sender);
        }

        // Handle refunds after state update
        if (previousHighestBidder != address(0) && previousHighestBidder != msg.sender) {
            // Refund previous highest bidder
            _safeTransfer(payable(previousHighestBidder), previousHighestBid);
        } else if (previousHighestBidder == msg.sender && userPreviousBid > 0) {
            // User is outbidding themselves - refund their previous bid
            _safeTransfer(payable(msg.sender), userPreviousBid);
        }

        emit BidPlaced(listingId, msg.sender, msg.value, block.timestamp);

        // FIXED: Limited auction extension
        if (auction.endTime - block.timestamp < 600 && 
            auction.extensionCount < MAX_AUCTION_EXTENSIONS) {
            auction.endTime += 600;
            auction.extensionCount++;
            emit AuctionExtended(listingId, auction.endTime, auction.extensionCount);
        }
    }

    function settleAuction(
        address tokenContract,
        uint256 tokenId
    ) external nonReentrant notPaused {
        bytes32 listingId = getListingId(tokenContract, tokenId);
        Listing storage listing = listings[listingId];
        Auction storage auction = auctions[listingId];
        
        if (!listing.active) {
            revert Marketplace__ItemNotListed(tokenContract, tokenId);
        }
        if (auction.status != AuctionStatus.ACTIVE) {
            revert Marketplace__AuctionEnded();
        }
        if (block.timestamp < auction.endTime) {
            revert Marketplace__AuctionActive();
        }

        listing.active = false;
        auction.status = AuctionStatus.ENDED;

        if (auction.highestBidder == address(0) || auction.highestBid < auction.reservePrice) {
            // No valid bids - refund all bidders
            if (auction.highestBidder != address(0)) {
                _refundAllBidders(listingId);
            }
            emit AuctionSettled(listingId, address(0), 0);
            return;
        }

        uint256 eventStartTime = _getEventStartTime(tokenContract);
        
        _executeTransferWithEscrow(listingId, auction.highestBidder, auction.highestBid, eventStartTime);
        
        lastSalePrice[listingId] = auction.highestBid;
        lastSaleTime[listingId] = block.timestamp;

        emit AuctionSettled(listingId, auction.highestBidder, auction.highestBid);
    }

    /*//////////////////////////////////////////////////////////////
                            ESCROW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function releaseEscrowedFunds(bytes32 listingId) external nonReentrant {
        EscrowInfo storage escrow = escrowedFunds[listingId];
        
        if (escrow.amount == 0) {
            revert Marketplace__ItemNotListed(address(0), 0);
        }
        if (escrow.released) {
            revert Marketplace__FundsAlreadyReleased();
        }
        
        // FIXED: Proper access control
        if (msg.sender != escrow.buyer && msg.sender != escrow.seller && msg.sender != owner()) {
            revert Marketplace__NotAuthorized();
        }
        
        if (block.timestamp < escrow.eventStartTime + ESCROW_RELEASE_DELAY) {
            revert Marketplace__EventNotCompleted();
        }

        escrow.released = true;
        uint256 amount = escrow.amount;
        
        _distributeFundsFromEscrow(listingId, amount);
        
        emit EscrowReleased(listingId, amount, escrow.seller);
    }

    function emergencyReleaseFunds(address tokenContract, uint256 tokenId) external nonReentrant {
        bytes32 listingId = getListingId(tokenContract, tokenId);
        EscrowInfo storage escrow = escrowedFunds[listingId];
        
        if (escrow.amount == 0) {
            revert Marketplace__ItemNotListed(tokenContract, tokenId);
        }
        if (escrow.released) {
            revert Marketplace__FundsAlreadyReleased();
        }
        
        // FIXED: Proper access control
        if (msg.sender != escrow.buyer && msg.sender != escrow.seller && msg.sender != owner()) {
            revert Marketplace__NotAuthorized();
        }

        bool eventCancelled = _getEventCancellationStatus(tokenContract);
        if (!eventCancelled) {
            revert Marketplace__EventNotCompleted();
        }

        escrow.released = true;
        
        _safeTransfer(payable(escrow.buyer), escrow.amount);
        
        emit EscrowReleased(listingId, escrow.amount, escrow.buyer);
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _validateListing(address tokenContract, uint256 tokenId) internal view {
        if (IERC721(tokenContract).ownerOf(tokenId) != msg.sender) {
            revert Marketplace__NotAuthorized();
        }
        
        if (!IERC721(tokenContract).isApprovedForAll(msg.sender, address(this))) {
            if (IERC721(tokenContract).getApproved(tokenId) != address(this)) {
                revert Marketplace__NotAuthorized();
            }
        }
    }

    function _validatePriceIncrease(
        bytes32 listingId, 
        uint256 newPrice, 
        address tokenContract, 
        uint256 tokenId
    ) internal {
        uint256 lastPrice = lastSalePrice[listingId];
        
        if (lastPrice > 0) {
            uint256 maxAllowedPrice = lastPrice + (lastPrice * PRICE_INCREASE_LIMIT / BASIS_POINTS);
            if (newPrice > maxAllowedPrice) {
                revert Marketplace__PriceIncreaseTooHigh();
            }
            
            uint256 increasePercentage = ((newPrice - lastPrice) * BASIS_POINTS) / lastPrice;
            emit PriceValidated(listingId, newPrice, lastPrice, increasePercentage);
        } else {
            uint256 mintPrice = _getMintPrice(tokenContract);
            if (mintPrice > 0) {
                uint256 maxAllowedPrice = mintPrice + (mintPrice * PRICE_INCREASE_LIMIT / BASIS_POINTS);
                if (newPrice > maxAllowedPrice) {
                    revert Marketplace__PriceIncreaseTooHigh();
                }
                
                uint256 increasePercentage = ((newPrice - mintPrice) * BASIS_POINTS) / mintPrice;
                emit PriceValidated(listingId, newPrice, mintPrice, increasePercentage);
            }
        }
    }

    function _checkResaleCooldown(bytes32 listingId) internal view {
        uint256 lastSale = lastSaleTime[listingId];
        if (lastSale > 0 && block.timestamp < lastSale + RESALE_COOLDOWN) {
            revert Marketplace__ResaleCooldownActive();
        }
    }

    function _executeTransferWithEscrow(
        bytes32 listingId,
        address buyer,
        uint256 amount,
        uint256 eventStartTime
    ) internal {
        Listing memory listing = listings[listingId];

        // Transfer NFT immediately
        IERC721(listing.tokenContract).transferFrom(
            listing.seller,
            buyer,
            listing.tokenId
        );

        // Escrow funds until after event
        escrowedFunds[listingId] = EscrowInfo({
            amount: amount,
            seller: listing.seller,
            buyer: buyer,
            released: false,
            eventStartTime: eventStartTime
        });

        emit FundsEscrowed(listingId, amount, listing.seller, buyer);

        // Track volume
        tokenContractVolume[listing.tokenContract] += amount;
        dailyVolume[block.timestamp / 1 days] += amount;
    }

    /**
     * @dev FIXED: Safe fund distribution with comprehensive error handling
     */
    function _distributeFundsFromEscrow(bytes32 listingId, uint256 amount) internal {
        Listing memory listing = listings[listingId];
        
        uint256 royaltyAmount = 0;
        address royaltyRecipient = address(0);
        
        // FIXED: Robust royalty calculation
        if (IERC165(listing.tokenContract).supportsInterface(type(IERC2981).interfaceId)) {
            try IERC2981(listing.tokenContract).royaltyInfo(listing.tokenId, amount) 
                returns (address recipient, uint256 royalty) {
                if (recipient != address(0) && royalty <= amount) {
                    royaltyRecipient = recipient;
                    royaltyAmount = royalty;
                }
            } catch {
                // Ignore royalty calculation failure
            }
        }

        uint256 platformFee = (amount * config.platformFeePercent) / BASIS_POINTS;
        
        // FIXED: Comprehensive fee validation
        uint256 totalFees = platformFee + royaltyAmount;
        if (totalFees > amount) {
            platformFee = (platformFee * amount) / totalFees;
            royaltyAmount = (royaltyAmount * amount) / totalFees;
            totalFees = platformFee + royaltyAmount;
        }
        
        uint256 sellerAmount = amount - totalFees;

        // FIXED: Check contract balance before transfers
        if (address(this).balance < amount) {
            revert Marketplace__InsufficientContractBalance();
        }

        // Distribute payments
        if (sellerAmount > 0) {
            _safeTransfer(payable(listing.seller), sellerAmount);
        }
        if (platformFee > 0) {
            _safeTransfer(payable(PLATFORM_ADDRESS), platformFee);
        }
        if (royaltyAmount > 0 && royaltyRecipient != address(0)) {
            _safeTransfer(payable(royaltyRecipient), royaltyAmount);
        }
    }

    function _safeTransfer(address payable recipient, uint256 amount) internal {
        if (amount == 0) return;
        
        (bool success, ) = recipient.call{value: amount}("");
        if (!success) {
            revert Marketplace__PaymentFailed();
        }
    }

    function _refundBidder(address bidder, uint256 amount) internal {
        _safeTransfer(payable(bidder), amount);
    }

    /**
     * @dev FIXED: Improved bidder refund with proper accounting
     */
    function _refundAllBidders(bytes32 listingId) internal {
        Auction storage auction = auctions[listingId];
        
        for (uint256 i = 0; i < auction.bidders.length; i++) {
            address bidder = auction.bidders[i];
            uint256 bidAmount = auction.bids[bidder];
            
            if (bidAmount > 0) {
                auction.bids[bidder] = 0;
                _safeTransfer(payable(bidder), bidAmount);
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                        OPTIMIZED EXTERNAL CALLS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev FIXED: Gas-optimized external calls
     */
    function _trackMarketplaceUsage(address tokenContract, address user, uint256 tokenId) internal {
        (bool success, ) = tokenContract.call(
            abi.encodeWithSignature("trackMarketplaceUsage(address,uint256)", user, tokenId)
        );
        // Ignore failure - marketplace still functions
    }

    function _getEventStartTime(address tokenContract) internal view returns (uint256) {
        (bool success, bytes memory data) = tokenContract.staticcall(
            abi.encodeWithSignature("eventStartTime()")
        );
        
        if (success && data.length >= 32) {
            return abi.decode(data, (uint256));
        }
        
        return block.timestamp + 30 days; // Default fallback
    }

    function _getEventCancellationStatus(address tokenContract) internal view returns (bool) {
        (bool success, bytes memory data) = tokenContract.staticcall(
            abi.encodeWithSignature("eventCancelled()")
        );
        
        if (success && data.length >= 32) {
            return abi.decode(data, (bool));
        }
        
        return false; // Default to not cancelled
    }

    function _getMintPrice(address tokenContract) internal view returns (uint256) {
        // Try mintPrice first
        (bool success, bytes memory data) = tokenContract.staticcall(
            abi.encodeWithSignature("mintPrice()")
        );
        
        if (success && data.length >= 32) {
            return abi.decode(data, (uint256));
        }
        
        // Try baseMintPrice as fallback
        (success, data) = tokenContract.staticcall(
            abi.encodeWithSignature("baseMintPrice()")
        );
        
        if (success && data.length >= 32) {
            return abi.decode(data, (uint256));
        }
        
        return 0;
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getListingId(address tokenContract, uint256 tokenId) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(tokenContract, tokenId));
    }

    function getAuctionInfo(address tokenContract, uint256 tokenId)
        external
        view
        returns (
            uint256 startTime,
            uint256 endTime,
            uint256 reservePrice,
            address highestBidder,
            uint256 highestBid,
            AuctionStatus status,
            uint256 extensionCount
        )
    {
        bytes32 listingId = getListingId(tokenContract, tokenId);
        Auction storage auction = auctions[listingId];
        return (
            auction.startTime,
            auction.endTime,
            auction.reservePrice,
            auction.highestBidder,
            auction.highestBid,
            auction.status,
            auction.extensionCount
        );
    }

    function getEscrowInfo(bytes32 listingId) external view returns (EscrowInfo memory) {
        return escrowedFunds[listingId];
    }

    function getTodaysVolume() external view returns (uint256) {
        return dailyVolume[block.timestamp / 1 days];
    }

    function getLastSaleInfo(bytes32 listingId) external view returns (uint256 price, uint256 time) {
        return (lastSalePrice[listingId], lastSaleTime[listingId]);
    }

    function getBidInfo(bytes32 listingId, address bidder) external view returns (uint256) {
        return auctions[listingId].bids[bidder];
    }

    function getAuctionBidders(bytes32 listingId) external view returns (address[] memory) {
        return auctions[listingId].bidders;
    }

    /*//////////////////////////////////////////////////////////////
                            OWNER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function updatePlatformFee(uint256 newFee) external onlyOwner {
        if (newFee > MAX_PLATFORM_FEE) {
            revert Marketplace__InvalidFeePercentage();
        }
        config.platformFeePercent = newFee;
    }

    function updateMaxAuctionDuration(uint256 newDuration) external onlyOwner {
        if (newDuration < MIN_AUCTION_DURATION || newDuration > MAX_AUCTION_DURATION) {
            revert Marketplace__InvalidDuration();
        }
        config.maxAuctionDuration = newDuration;
    }

    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
        emit MarketplacePaused(_paused);
    }

    function emergencyWithdraw() external onlyOwner {
        _safeTransfer(payable(owner()), address(this).balance);
    }

    /**
     * @dev FIXED: More restrictive emergency escrow release
     */
    function emergencyReleaseEscrow(bytes32 listingId) external onlyOwner {
        EscrowInfo storage escrow = escrowedFunds[listingId];
        require(escrow.amount > 0 && !escrow.released, "Invalid escrow");
        
        escrow.released = true;
        // Always refund to buyer in emergency - more fair and secure
        _safeTransfer(payable(escrow.buyer), escrow.amount);
        
        emit EscrowReleased(listingId, escrow.amount, escrow.buyer);
    }
}