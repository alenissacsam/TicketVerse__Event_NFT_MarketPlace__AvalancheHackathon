// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IERC721, IERC165} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {UserVerification} from "./UserVerification.sol";
import {EventTicket} from "./EventTicket.sol";

/**
 * @title TicketMarketplace
 * @author alenissacsam
 * @dev Enhanced marketplace with anti-manipulation features, fund escrow, and security improvements
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

    // Anti-manipulation settings
    uint256 public constant PRICE_INCREASE_LIMIT = 2000; // 20% in basis points
    uint256 public constant RESALE_COOLDOWN = 1 hours;
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant ESCROW_RELEASE_DELAY = 1 days; // Release funds 1 day after event

    struct PlatformConfig {
        uint256 platformFeePercent;
        uint256 maxAuctionDuration;
    }

    PlatformConfig public config;
    address public immutable PLATFORM_ADDRESS;
    address public immutable I_USER_VERFIER_ADDRESS;

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

    /*//////////////////////////////////////////////////////////////
                                FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    constructor(
        address _platformAddress,
        uint256 _platformFeePercent,
        uint256 _maxAuctionDuration,
        address _userVerfierAddress
    ) Ownable(msg.sender) {
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
    /**
     * @dev Enhanced fixed price listing with price validation and cooldown checks
     */
    function listItemFixedPrice(
        address tokenContract,
        uint256 tokenId,
        uint256 price
    ) external {
        _validateListing(tokenContract, tokenId);
        
        bytes32 listingId = getListingId(tokenContract, tokenId);
        
        // Check price increase limits
        _validatePriceIncrease(listingId, price);
        
        // Check resale cooldown
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

        // Track marketplace usage in the ticket contract
        EventTicket(tokenContract).trackMarketplaceUsage(msg.sender, tokenId);

        emit Listed(
            msg.sender,
            tokenContract,
            tokenId,
            price,
            SaleType.FIXED_PRICE
        );
    }

    /**
     * @dev Enhanced auction creation with price validation
     */
    function createAuction(
        address tokenContract,
        uint256 tokenId,
        uint256 startingPrice,
        uint256 reservePrice,
        uint256 duration,
        uint256 minBidIncrement
    ) external {
        if (duration > config.maxAuctionDuration) {
            revert Marketplace__InvalidTime();
        }
        
        _validateListing(tokenContract, tokenId);
        
        bytes32 listingId = getListingId(tokenContract, tokenId);
        
        // Validate auction starting price against last sale price
        _validatePriceIncrease(listingId, startingPrice);
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

        // Track marketplace usage
        EventTicket(tokenContract).trackMarketplaceUsage(msg.sender, tokenId);

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

    /**
     * @dev Cancel listing with proper refund handling
     */
    function cancelListing(
        address tokenContract,
        uint256 tokenId
    ) external nonReentrant {
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
    /**
     * @dev Buy fixed price item with enhanced escrow system
     */
    function buyItem(
        address tokenContract,
        uint256 tokenId
    ) external payable nonReentrant {
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
        
        // Get event start time for escrow
        uint256 eventStartTime = EventTicket(tokenContract).eventStartTime();
        
        // Execute transfer with escrow
        _executeTransferWithEscrow(listingId, msg.sender, msg.value, eventStartTime);
        
        // Update price tracking
        lastSalePrice[listingId] = listing.price;
        lastSaleTime[listingId] = block.timestamp;
    }

    /**
     * @dev Place bid with enhanced validation
     */
    function placeBid(
        address tokenContract,
        uint256 tokenId
    ) external payable nonReentrant {
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

        // Refund previous highest bidder
        if (auction.highestBidder != address(0)) {
            _refundBidder(auction.highestBidder, auction.highestBid);
        } else {
            auction.bidders.push(msg.sender);
        }

        if (auction.bids[msg.sender] == 0) {
            auction.bidders.push(msg.sender);
        }

        auction.bids[msg.sender] = msg.value;
        auction.highestBidder = msg.sender;
        auction.highestBid = msg.value;

        emit BidPlaced(listingId, msg.sender, msg.value, block.timestamp);

        // Auto-extend auction if bid placed in last 10 minutes
        if (auction.endTime - block.timestamp < 600) {
            auction.endTime += 600;
        }
    }

    /**
     * @dev Settle auction with escrow system
     */
    function settleAuction(
        address tokenContract,
        uint256 tokenId
    ) external nonReentrant {
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
            if (auction.highestBidder != address(0)) {
                _refundBidder(auction.highestBidder, auction.highestBid);
            }
            emit AuctionSettled(listingId, address(0), 0);
            return;
        }

        // Get event start time for escrow
        uint256 eventStartTime = EventTicket(tokenContract).eventStartTime();
        
        // Execute transfer with escrow
        _executeTransferWithEscrow(listingId, auction.highestBidder, auction.highestBid, eventStartTime);
        
        // Update price tracking
        lastSalePrice[listingId] = auction.highestBid;
        lastSaleTime[listingId] = block.timestamp;

        emit AuctionSettled(listingId, auction.highestBidder, auction.highestBid);
    }

    /*//////////////////////////////////////////////////////////////
                            ESCROW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @dev Release escrowed funds after event completion
     */
    function releaseEscrowedFunds(bytes32 listingId) external nonReentrant {
        EscrowInfo storage escrow = escrowedFunds[listingId];
        
        if (escrow.amount == 0) {
            revert Marketplace__ItemNotListed(address(0), 0);
        }
        if (escrow.released) {
            revert Marketplace__FundsAlreadyReleased();
        }
        
        // Check if enough time has passed since event start
        if (block.timestamp < escrow.eventStartTime + ESCROW_RELEASE_DELAY) {
            revert Marketplace__EventNotCompleted();
        }

        escrow.released = true;
        uint256 amount = escrow.amount;
        
        // Calculate and distribute payments
        _distributeFundsFromEscrow(listingId, amount);
        
        emit EscrowReleased(listingId, amount, escrow.seller);
    }

    /**
     * @dev Emergency release for cancelled events
     */
    function emergencyReleaseToFunds(address tokenContract, uint256 tokenId) external nonReentrant {
        bytes32 listingId = getListingId(tokenContract, tokenId);
        EscrowInfo storage escrow = escrowedFunds[listingId];
        
        // Check if event was cancelled
        bool eventCancelled = EventTicket(tokenContract).eventCancelled();
        if (!eventCancelled) {
            revert Marketplace__EventNotCompleted();
        }
        
        if (escrow.released) {
            revert Marketplace__FundsAlreadyReleased();
        }

        escrow.released = true;
        
        // Refund buyer in case of cancelled event
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
            revert Marketplace__NotAuthorized();
        }
    }

    function _validatePriceIncrease(bytes32 listingId, uint256 newPrice) internal {
        uint256 lastPrice = lastSalePrice[listingId];
        
        if (lastPrice > 0) {
            uint256 maxAllowedPrice = lastPrice + (lastPrice * PRICE_INCREASE_LIMIT / BASIS_POINTS);
            if (newPrice > maxAllowedPrice) {
                revert Marketplace__PriceIncreaseTooHigh();
            }
            
            uint256 increasePercentage = ((newPrice - lastPrice) * BASIS_POINTS) / lastPrice;
            emit PriceValidated(listingId, newPrice, lastPrice, increasePercentage);
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

    function _distributeFundsFromEscrow(bytes32 listingId, uint256 amount) internal {
        Listing memory listing = listings[listingId];
        
        // Calculate fees
        (address royaltyRecipient, uint256 royaltyAmount) = IERC2981(listing.tokenContract)
            .royaltyInfo(listing.tokenId, amount);
            
        uint256 platformFee = (amount * config.platformFeePercent) / BASIS_POINTS;
        uint256 sellerAmount = amount - platformFee - royaltyAmount;

        // Distribute payments
        _safeTransfer(payable(listing.seller), sellerAmount);
        _safeTransfer(payable(PLATFORM_ADDRESS), platformFee);
        
        if (royaltyAmount > 0 && royaltyRecipient != address(0)) {
            _safeTransfer(payable(royaltyRecipient), royaltyAmount);
        }
    }

    function _safeTransfer(address payable recipient, uint256 amount) internal {
        (bool success, ) = recipient.call{value: amount}("");
        if (!success) {
            revert Marketplace__PaymentFailed();
        }
    }

    function _refundBidder(address bidder, uint256 amount) internal {
        _safeTransfer(payable(bidder), amount);
    }

    function _refundAllBidders(bytes32 listingId) internal {
        Auction storage auction = auctions[listingId];
        for (uint256 i = 0; i < auction.bidders.length; i++) {
            address bidder = auction.bidders[i];
            uint256 bidAmount = auction.bids[bidder];
            if (bidAmount > 0) {
                auction.bids[bidder] = 0;
                _refundBidder(bidder, bidAmount);
            }
        }
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
            AuctionStatus status
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
            auction.status
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

    /*//////////////////////////////////////////////////////////////
                            OWNER FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function updatePlatformFee(uint256 newFee) external onlyOwner {
        require(newFee <= 1000, "Fee too high"); // Max 10%
        config.platformFeePercent = newFee;
    }

    function updateMaxAuctionDuration(uint256 newDuration) external onlyOwner {
        config.maxAuctionDuration = newDuration;
    }

    function emergencyWithdraw() external onlyOwner {
        _safeTransfer(payable(owner()), address(this).balance);
    }
}