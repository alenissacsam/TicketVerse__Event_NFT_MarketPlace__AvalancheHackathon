// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC721, IERC165} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {UserVerification} from "./UserVerification.sol";
import "./MarketPlaceStructAndVariables.sol";

/**
 * @title TicketMarketplace 
 * @author alenissacsam (Enhanced by AI)
 * @dev NFT mint payments count as deposits, users can withdraw up to total deposits
 */
contract TicketMarketplace is ReentrancyGuard, Ownable {
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    mapping(bytes32 => Listing) public listings;
    mapping(bytes32 => Auction) public auctions;
    mapping(bytes32 => uint256) public lastSalePrice;
    mapping(bytes32 => uint256) public lastSaleTime;

    // Deposit and balance tracking
    mapping(address => mapping(address => UserBalance)) public userBalances; // user => eventContract => balance
    mapping(address => EventInfo) public eventInfo;
    mapping(address => uint256) public tokenContractVolume;
    mapping(uint256 => uint256) public dailyVolume;

    // Royalty and Fee tracking
    // eventContract => royaltyRecipient => amountOwed
    mapping(address => mapping(address => uint256)) public royaltiesPayable;
    // eventContract => amountOwed
    mapping(address => uint256) public platformFeesPayable;

    // Authorized event contracts that can register mint payments
    mapping(address => bool) public authorizedEventContracts;

    // Constants
    uint256 public constant PRICE_INCREASE_LIMIT = 2000; // 20% in basis points
    uint256 public constant RESALE_COOLDOWN = 1 hours;
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant MAX_AUCTION_EXTENSIONS = 5;
    uint256 public constant MIN_AUCTION_DURATION = 1 hours;
    uint256 public constant MAX_AUCTION_DURATION = 30 days;

    uint256 public platformFeePercent = 250; // 2.5%
    address public immutable PLATFORM_ADDRESS;
    address public immutable I_USER_VERFIER_ADDRESS;

    //Verifications

    UserVerification public immutable userVerification;

    // Emergency controls
    bool public paused;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    event FundsDeposited(
        address indexed user,
        address indexed eventContract,
        uint256 amount,
        string depositType
    );
    event FundsWithdrawn(
        address indexed user,
        address indexed eventContract,
        uint256 amount
    );
    event PrimarySaleRegistered(
        address indexed user,
        address indexed eventContract,
        uint256 amount
    );
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
    event ItemSold(
        address indexed buyer,
        address indexed seller,
        bytes32 indexed listingId,
        uint256 price
    );
    event ListingCancelled(bytes32 indexed listingId, address indexed seller);
    event EmergencyRefundEnabled(address indexed eventContract);
    event EmergencyRefundClaimed(
        address indexed user,
        address indexed eventContract,
        uint256 amount
    );
    event ProfitsCollected(
        address indexed user,
        address indexed eventContract,
        uint256 amount
    );
    event EventEnded(address indexed eventContract);
    event RoyaltyPaid(
        address indexed eventContract,
        address indexed recipient,
        uint256 amount
    );
    event AuctionExtended(
        bytes32 indexed listingId,
        uint256 newEndTime,
        uint256 extensionCount
    );
    event MarketplacePaused(bool paused);
    event EventContractAuthorized(
        address indexed eventContract,
        bool authorized
    );

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier notPaused() {
        if (paused) revert Marketplace__ContractPaused();
        _;
    }

    modifier validAddress(address _address) {
        require(_address != address(0), "Invalid address");
        _;
    }

    modifier onlyVerifiedUser() {
        require(
            userVerification.isVerifiedAndActive(msg.sender),
            "Marketplace: User not verified or is inactive"
        );
        _;
    }

    modifier onlyAuthorizedEventContract() {
        if (!authorizedEventContracts[msg.sender])
            revert Marketplace__NotEventContract();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(
        address _platformAddress,
        uint256 _platformFeePercent,
        address _userVerfierAddress
    )
        Ownable(msg.sender)
        validAddress(_platformAddress)
        validAddress(_userVerfierAddress)
    {
        if (_platformFeePercent > 1000)
            revert Marketplace__InvalidFeePercentage(_platformFeePercent, 1000);
        userVerification = UserVerification(_userVerfierAddress);
        I_USER_VERFIER_ADDRESS = _userVerfierAddress;
        PLATFORM_ADDRESS = _platformAddress;
        platformFeePercent = _platformFeePercent;
    }

    /*//////////////////////////////////////////////////////////////
                            DEPOSIT SYSTEM
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Users directly deposit funds for a specific event
     * Only verified users can deposit funds
     */
    function depositForEvent(
        address eventContract
    ) external payable nonReentrant notPaused onlyVerifiedUser {
        if (msg.value == 0) revert Marketplace__InsufficientDeposits(1, 0);
        if (eventInfo[eventContract].emergencyRefund)
            revert Marketplace__EmergencyRefundActive();

        _registerDeposit(msg.sender, eventContract, msg.value, "direct");
    }

    /**
     * Only verified user can register primary sale
     * @dev Called by an authorized EventTicket contract during a primary sale (mint).
     * It receives the full mint price, credits the organizer and platform for deferred payment,
     * and registers the full amount as a deposit for the minting user.
     * @param user The address of the user who minted the ticket.
     * @param organizer The address of the event organizer to be paid.
     * @param organizerPercentage The percentage of the mint price owed to the organizer.
     */
    function registerPrimarySale(
        address user,
        address organizer,
        uint256 organizerPercentage
    ) external payable nonReentrant onlyAuthorizedEventContract {
        uint256 totalAmount = msg.value;
        if (totalAmount == 0) revert Marketplace__PaymentFailed();
        address eventContract = msg.sender;

        // Calculate and escrow shares for organizer and platform
        uint256 organizerShare = (totalAmount * organizerPercentage) /
            BASIS_POINTS;
        uint256 platformShare = totalAmount - organizerShare;

        if (organizerShare > 0) {
            userBalances[organizer][eventContract]
                .lockedBalance += organizerShare;
        }
        if (platformShare > 0) {
            platformFeesPayable[eventContract] += platformShare;
        }

        // Register the full mint price as a deposit for the user
        _registerDeposit(user, eventContract, totalAmount, "mint");

        emit PrimarySaleRegistered(user, eventContract, totalAmount);
    }

    /**
     * @dev Internal function to register any type of deposit
     */
    function _registerDeposit(
        address user,
        address eventContract,
        uint256 amount,
        string memory depositType
    ) internal {
        UserBalance storage balance = userBalances[user][eventContract];
        EventInfo storage info = eventInfo[eventContract];

        // Track total deposited and available balance
        balance.totalDeposited += amount;
        balance.availableBalance += amount;

        // Track for emergency refunds
        info.userOriginalDeposits[user] += amount;
        info.totalDeposited += amount;

        emit FundsDeposited(user, eventContract, amount, depositType);
    }

    /**
     * @dev Withdraw available funds (up to maximum of what user originally deposited)
     */

    function withdrawFunds(
        address eventContract,
        uint256 amount
    ) external nonReentrant onlyVerifiedUser {
        UserBalance storage balance = userBalances[msg.sender][eventContract];

        if (balance.availableBalance < amount)
            revert Marketplace__InsufficientWithdrawalBalance();

        if (eventInfo[eventContract].emergencyRefund)
            revert Marketplace__EmergencyRefundActive();
        balance.availableBalance -= amount;
        balance.totalWithdrawn += amount;

        _safeTransfer(payable(msg.sender), amount);

        emit FundsWithdrawn(msg.sender, eventContract, amount);
    }

    /*//////////////////////////////////////////////////////////////
                            AUTHORIZATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Authorize event contracts to register mint payments
     */
    function authorizeEventContract(
        address eventContract,
        bool authorized
    ) external {
        authorizedEventContracts[eventContract] = authorized;
        emit EventContractAuthorized(eventContract, authorized);
    }

    /*//////////////////////////////////////////////////////////////
                            LISTING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function listItemFixedPrice(
        address tokenContract,
        uint256 tokenId,
        uint256 price
    ) external notPaused onlyVerifiedUser {
        if (price == 0) revert Marketplace__PriceMustBeGreaterThanZero();
        if (!authorizedEventContracts[tokenContract])
            revert Marketplace__EventContractNotAuthorized();

        _validateListing(tokenContract, tokenId);
        bytes32 listingId = getListingId(tokenContract, tokenId);

        _validatePriceIncrease(listingId, price, tokenContract);
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
    ) external notPaused onlyVerifiedUser {
        if (startingPrice == 0)
            revert Marketplace__PriceMustBeGreaterThanZero();
        if (minBidIncrement == 0) revert Marketplace__InvalidBidIncrement();
        if (reservePrice < startingPrice)
            revert Marketplace__ReservePriceTooLow();
        if (duration < MIN_AUCTION_DURATION || duration > MAX_AUCTION_DURATION)
            revert Marketplace__InvalidDuration();
        if (!authorizedEventContracts[tokenContract])
            revert Marketplace__EventContractNotAuthorized();
        _validateListing(tokenContract, tokenId);
        bytes32 listingId = getListingId(tokenContract, tokenId);

        _validatePriceIncrease(listingId, startingPrice, tokenContract);
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

    /*//////////////////////////////////////////////////////////////
                            BUYING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Buy item using deposited funds
     */
    function buyItemWithDeposits(
        address tokenContract,
        uint256 tokenId
    ) external nonReentrant notPaused onlyVerifiedUser {
        bytes32 listingId = getListingId(tokenContract, tokenId);
        Listing storage listing = listings[listingId];

        if (!listing.active)
            revert Marketplace__ItemNotListed(tokenContract, tokenId);
        if (listing.saleType != SaleType.FIXED_PRICE)
            revert Marketplace__NotFixedPrice();
        if (msg.sender == listing.seller)
            revert Marketplace__CannotBuyOwnItem();
        if (eventInfo[tokenContract].emergencyRefund)
            revert Marketplace__EmergencyRefundActive();

        UserBalance storage buyerBalance = userBalances[msg.sender][
            tokenContract
        ];
        if (buyerBalance.availableBalance < listing.price)
            revert Marketplace__InsufficientDeposits(
                listing.price,
                buyerBalance.availableBalance
            );
        // Execute the purchase using internal balances
        buyerBalance.availableBalance -= listing.price;
        _distributeSaleProceeds(
            tokenContract,
            listing.tokenId,
            listing.price,
            listing.seller
        );

        // Transfer NFT
        IERC721(tokenContract).transferFrom(
            listing.seller,
            msg.sender,
            tokenId
        );

        // Mark listing as inactive
        listing.active = false;

        // Track sale data
        lastSalePrice[listingId] = listing.price;
        lastSaleTime[listingId] = block.timestamp;
        tokenContractVolume[tokenContract] += listing.price;
        dailyVolume[block.timestamp / 1 days] += listing.price;

        emit ItemSold(msg.sender, listing.seller, listingId, listing.price);
    }

    /**
     * @dev Place bid using deposited funds
     */
    function placeBidWithDeposits(
        address tokenContract,
        uint256 tokenId,
        uint256 bidAmount
    ) external nonReentrant notPaused onlyVerifiedUser {
        bytes32 listingId = getListingId(tokenContract, tokenId);
        Listing storage listing = listings[listingId];

        if (!listing.active)
            revert Marketplace__ItemNotListed(tokenContract, tokenId);
        if (listing.saleType != SaleType.AUCTION)
            revert Marketplace__NotAuction();
        if (msg.sender == listing.seller)
            revert Marketplace__CannotBuyOwnItem();
        if (eventInfo[tokenContract].emergencyRefund)
            revert Marketplace__EmergencyRefundActive();

        Auction storage auction = auctions[listingId];
        if (block.timestamp >= auction.endTime)
            revert Marketplace__AuctionEnded();
        if (auction.status != AuctionStatus.ACTIVE)
            revert Marketplace__AuctionNotActive();
        uint256 minBid = auction.highestBid + auction.minBidIncrement;
        if (auction.highestBid == 0) {
            minBid = listing.price;
        }
        if (bidAmount < minBid) revert Marketplace__BidTooLow();
        UserBalance storage bidderBalance = userBalances[msg.sender][
            tokenContract
        ];
        if (bidderBalance.availableBalance < bidAmount)
            revert Marketplace__InsufficientDeposits(
                bidAmount,
                bidderBalance.availableBalance
            );

        // Handle previous bid refund
        uint256 userPreviousBid = auction.bids[msg.sender];
        if (userPreviousBid > 0) {
            bidderBalance.availableBalance += userPreviousBid; // Refund previous bid
            bidderBalance.lockedBalance -= userPreviousBid;
        }

        // Handle previous highest bidder refund
        if (
            auction.highestBidder != address(0) &&
            auction.highestBidder != msg.sender
        ) {
            UserBalance storage prevBidderBalance = userBalances[
                auction.highestBidder
            ][tokenContract];
            prevBidderBalance.availableBalance += auction.highestBid;
            prevBidderBalance.lockedBalance -= auction.highestBid;
        }

        // Update auction state
        if (userPreviousBid == 0) {
            auction.bidders.push(msg.sender);
        }

        auction.bids[msg.sender] = bidAmount;
        auction.highestBidder = msg.sender;
        auction.highestBid = bidAmount;

        // Lock bidder's funds
        bidderBalance.availableBalance -= bidAmount;
        bidderBalance.lockedBalance += bidAmount;

        emit BidPlaced(listingId, msg.sender, bidAmount, block.timestamp);

        // Auto-extend auction if needed
        if (
            auction.endTime - block.timestamp < 600 &&
            auction.extensionCount < MAX_AUCTION_EXTENSIONS
        ) {
            auction.endTime += 600;
            auction.extensionCount++;
            emit AuctionExtended(
                listingId,
                auction.endTime,
                auction.extensionCount
            );
        }
    }

    /**
     * @dev Settle auction
     */
    function settleAuction(
        address tokenContract,
        uint256 tokenId
    ) external nonReentrant notPaused {
        bytes32 listingId = getListingId(tokenContract, tokenId);
        Listing storage listing = listings[listingId];
        Auction storage auction = auctions[listingId];

        if (!listing.active)
            revert Marketplace__ItemNotListed(tokenContract, tokenId);
        if (auction.status != AuctionStatus.ACTIVE)
            revert Marketplace__AuctionNotActive();
        if (block.timestamp < auction.endTime)
            revert Marketplace__AuctionActive();
        listing.active = false;
        auction.status = AuctionStatus.ENDED;

        if (
            auction.highestBidder == address(0) ||
            auction.highestBid < auction.reservePrice
        ) {
            // No valid bids - refund all bidders
            _refundAllBidders(listingId, tokenContract);
            emit AuctionSettled(listingId, address(0), 0);
            return;
        }

        // Transfer NFT to winner
        IERC721(tokenContract).transferFrom(
            listing.seller,
            auction.highestBidder,
            tokenId
        );

        // Settle funds from the winner's locked bid
        UserBalance storage winnerBalance = userBalances[auction.highestBidder][
            tokenContract
        ];
        winnerBalance.lockedBalance -= auction.highestBid; // The bid is now spent
        _distributeSaleProceeds(
            tokenContract,
            tokenId,
            auction.highestBid,
            listing.seller
        );

        // Refund other bidders
        for (uint256 i = 0; i < auction.bidders.length; i++) {
            address bidder = auction.bidders[i];
            if (bidder != auction.highestBidder) {
                uint256 bidAmount = auction.bids[bidder];
                if (bidAmount > 0) {
                    UserBalance storage bidderBalance = userBalances[bidder][
                        tokenContract
                    ];
                    bidderBalance.availableBalance += bidAmount;
                    bidderBalance.lockedBalance -= bidAmount;
                }
            }
        }

        // Track sale data
        lastSalePrice[listingId] = auction.highestBid;
        lastSaleTime[listingId] = block.timestamp;
        tokenContractVolume[tokenContract] += auction.highestBid;
        dailyVolume[block.timestamp / 1 days] += auction.highestBid;

        emit AuctionSettled(
            listingId,
            auction.highestBidder,
            auction.highestBid
        );
    }

    /*//////////////////////////////////////////////////////////////
                        EVENT COMPLETION & PROFITS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Mark event as ended and enable profit collection
     */

    function markEventEnded(address eventContract) external onlyOwner {
        if (eventInfo[eventContract].eventEnded) revert Marketplace__EventAlreadyEnded();
        if (_getEventCancellationStatus(eventContract)) revert Marketplace__EventNotCancelled();

        eventInfo[eventContract].eventEnded = true;

        emit EventEnded(eventContract);
    }

    /**
     * @dev Collect profits after event ends (locked balances become available)
     */

    function collectProfits(
        address eventContract
    ) external nonReentrant onlyVerifiedUser {
        if (!eventInfo[eventContract].eventEnded) revert Marketplace__EventNotEnded();
        if (eventInfo[eventContract].emergencyRefund) revert Marketplace__EmergencyRefundActive();

        UserBalance storage balance = userBalances[msg.sender][eventContract];
        if (balance.lockedBalance == 0) revert Marketplace__NoProfitsToCollect();
        uint256 lockedAmount = balance.lockedBalance;
        balance.lockedBalance = 0;

        // Add to available balance as profits
        // The lockedAmount is the net profit for the seller after royalties and platform fees.
        balance.availableBalance += lockedAmount;
        balance.totalProfits += lockedAmount;

        emit ProfitsCollected(msg.sender, eventContract, lockedAmount);
    }

    /*//////////////////////////////////////////////////////////////
                        EMERGENCY REFUND SYSTEM
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Enable emergency refunds for cancelled event
     */

    function enableEmergencyRefund(address eventContract) external onlyOwner {
        if (!_getEventCancellationStatus(eventContract)) revert Marketplace__EventNotCancelled();
        if (eventInfo[eventContract].emergencyRefund) revert Marketplace__EmergencyRefundActive();
        eventInfo[eventContract].emergencyRefund = true;

        emit EmergencyRefundEnabled(eventContract);
    }

    /**
     * @dev Claim emergency refund (full original deposit, no fees)
     */
    function claimEmergencyRefund(address eventContract) external nonReentrant {
        if (!eventInfo[eventContract].emergencyRefund) revert Marketplace__EmergencyRefundNotEnabled();

        EventInfo storage info = eventInfo[eventContract];
        UserBalance storage balance = userBalances[msg.sender][eventContract];

        // Refund original deposits plus any locked profits (from sales/organizer fees)
        uint256 refundAmount = info.userOriginalDeposits[msg.sender] +
            balance.lockedBalance;
        if (refundAmount == 0) revert Marketplace__NoDepositsToRefund();


        // Clear user's deposits and balance for this event
        info.userOriginalDeposits[msg.sender] = 0;
        delete userBalances[msg.sender][eventContract];

        // Send full refund (no platform fees on cancelled events)
        _safeTransfer(payable(msg.sender), refundAmount);

        emit EmergencyRefundClaimed(msg.sender, eventContract, refundAmount);
    }

    /**
     * @dev Allows royalty recipients to withdraw their earnings for an event.
     */
    function withdrawRoyalties(
        address eventContract,
        address payable recipient
    ) external nonReentrant {
        if (!eventInfo[eventContract].eventEnded) revert Marketplace__EventNotEnded();
        uint256 amount = royaltiesPayable[eventContract][recipient];
        if (amount == 0) revert Marketplace__NoRoyaltiesToWithdraw();

        royaltiesPayable[eventContract][recipient] = 0;
        _safeTransfer(recipient, amount);

        emit RoyaltyPaid(eventContract, recipient, amount);
    }

    /**
     * @dev Allows the platform to withdraw its fees for an event.
     */
    function withdrawPlatformFees(address eventContract) external nonReentrant {
        if (msg.sender != PLATFORM_ADDRESS && msg.sender != owner()) revert Marketplace__NotAuthorized();
        if (!eventInfo[eventContract].eventEnded) revert Marketplace__EventNotEnded();
        uint256 amount = platformFeesPayable[eventContract];
        if (amount == 0) revert Marketplace__NoPlatformFeesToWithdraw();

        platformFeesPayable[eventContract] = 0;
        _safeTransfer(payable(PLATFORM_ADDRESS), amount);
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _distributeSaleProceeds(
        address tokenContract,
        uint256 tokenId,
        uint256 price,
        address seller
    ) internal {
        // 1. Calculate Royalty
        uint256 royaltyAmount = 0;
        address royaltyRecipient = address(0);

        if (
            IERC165(tokenContract).supportsInterface(type(IERC2981).interfaceId)
        ) {
            try IERC2981(tokenContract).royaltyInfo(tokenId, price) returns (
                address recipient,
                uint256 rAmount
            ) {
                if (recipient != address(0) && rAmount > 0 && rAmount < price) {
                    royaltyRecipient = recipient;
                    royaltyAmount = rAmount;
                }
            } catch {
                /* Proceed without royalty if call fails */
            }
        }

        // 2. Calculate Platform Fee
        uint256 platformFee = (price * platformFeePercent) / BASIS_POINTS;
        uint256 sellerAmount = price - royaltyAmount - platformFee;

        userBalances[seller][tokenContract].lockedBalance += sellerAmount;
        if (royaltyAmount > 0)
            royaltiesPayable[tokenContract][royaltyRecipient] += royaltyAmount;
        if (platformFee > 0) platformFeesPayable[tokenContract] += platformFee;
    }

    function _validateListing(
        address tokenContract,
        uint256 tokenId
    ) internal view {
        if (IERC721(tokenContract).ownerOf(tokenId) != msg.sender) revert Marketplace__NotTokenOwner();
        if (!IERC721(tokenContract).isApprovedForAll(msg.sender, address(this)) &&
            IERC721(tokenContract).getApproved(tokenId) != address(this)
        ) revert Marketplace__NotApproved();
    }

    function _validatePriceIncrease(
        bytes32 listingId,
        uint256 newPrice,
        address tokenContract
    ) internal view {
        uint256 lastPrice = lastSalePrice[listingId];

        if (lastPrice > 0) {
            uint256 maxAllowedPrice = lastPrice +
                ((lastPrice * PRICE_INCREASE_LIMIT) / BASIS_POINTS);
            if (newPrice > maxAllowedPrice) revert Marketplace__PriceIncreaseTooHigh();
        } else {
            uint256 mintPrice = _getMintPrice(tokenContract);
            if (mintPrice > 0) {
                uint256 maxAllowedPrice = mintPrice +
                    ((mintPrice * PRICE_INCREASE_LIMIT) / BASIS_POINTS);
                if (newPrice > maxAllowedPrice) revert Marketplace__PriceIncreaseTooHigh();
            }
        }
    }

    function _checkResaleCooldown(bytes32 listingId) internal view {
        uint256 lastSale = lastSaleTime[listingId];
        if (lastSale != 0 && block.timestamp < lastSale + RESALE_COOLDOWN) revert Marketplace__ResaleCooldownActive();

    }

    function _refundAllBidders(
        bytes32 listingId,
        address tokenContract
    ) internal {
        Auction storage auction = auctions[listingId];

        for (uint256 i = 0; i < auction.bidders.length; i++) {
            address bidder = auction.bidders[i];
            uint256 bidAmount = auction.bids[bidder];

            if (bidAmount > 0) {
                UserBalance storage bidderBalance = userBalances[bidder][
                    tokenContract
                ];
                bidderBalance.availableBalance += bidAmount;
                bidderBalance.lockedBalance -= bidAmount;
                auction.bids[bidder] = 0;
            }
        }
    }

    function _trackMarketplaceUsage(
        address tokenContract,
        address user,
        uint256 tokenId
    ) internal {
        (bool success, ) = tokenContract.call(
            abi.encodeWithSignature(
                "trackMarketplaceUsage(address,uint256)",
                user,
                tokenId
            )
        );
        // Ignore failure
    }

    function _getEventCancellationStatus(
        address tokenContract
    ) internal view returns (bool) {
        (bool success, bytes memory data) = tokenContract.staticcall(
            abi.encodeWithSignature("eventCancelled()")
        );

        if (success && data.length >= 32) {
            return abi.decode(data, (bool));
        }

        return false;
    }

    // Removed mintPrice() check as EventTicket.sol only has baseMintPrice()
    function _getMintPrice(
        address tokenContract
    ) internal view returns (uint256) {
        (bool success, bytes memory data) = tokenContract.staticcall(
            abi.encodeWithSignature("baseMintPrice()")
        );

        if (success && data.length >= 32) {
            return abi.decode(data, (uint256));
        }

        return 0;
    }

    /**
     * @dev Internal function to safely transfer ETH.
     */
    function _safeTransfer(address payable recipient, uint256 amount) internal {
        (bool success, ) = recipient.call{value: amount}("");
        if (!success) revert Marketplace__PaymentFailed();
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getListingId(
        address tokenContract,
        uint256 tokenId
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(tokenContract, tokenId));
    }

    function getUserBalance(
        address user,
        address eventContract
    )
        external
        view
        returns (
            uint256 totalDeposited,
            uint256 availableBalance,
            uint256 lockedBalance,
            uint256 totalWithdrawn,
            uint256 totalProfits,
            uint256 maxWithdrawable
        )
    {
        UserBalance storage balance = userBalances[user][eventContract];
        uint256 maxWithdraw = balance.totalDeposited > balance.totalWithdrawn
            ? balance.totalDeposited - balance.totalWithdrawn
            : 0;

        return (
            balance.totalDeposited,
            balance.availableBalance,
            balance.lockedBalance,
            balance.totalWithdrawn,
            balance.totalProfits,
            maxWithdraw > balance.availableBalance
                ? balance.availableBalance
                : maxWithdraw
        );
    }

    function getEventInfo(
        address eventContract
    )
        external
        view
        returns (bool eventEnded, bool emergencyRefund, uint256 totalDeposited)
    {
        EventInfo storage info = eventInfo[eventContract];
        return (info.eventEnded, info.emergencyRefund, info.totalDeposited);
    }

    function getUserOriginalDeposit(
        address user,
        address eventContract
    ) external view returns (uint256) {
        return eventInfo[eventContract].userOriginalDeposits[user];
    }

    function getRoyaltiesPayable(
        address eventContract,
        address recipient
    ) external view returns (uint256) {
        return royaltiesPayable[eventContract][recipient];
    }

    function getPlatformFeesPayable(
        address eventContract
    ) external view returns (uint256) {
        return platformFeesPayable[eventContract];
    }

    /*//////////////////////////////////////////////////////////////
                            OWNER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function updatePlatformFee(uint256 newFeePercent) external onlyOwner {
        if (newFeePercent > 1000) revert Marketplace__InvalidFeePercentage(newFeePercent, 1000);
        platformFeePercent = newFeePercent;
    }

    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
        emit MarketplacePaused(_paused);
    }

    function emergencyWithdraw() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }
}
