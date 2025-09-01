// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

interface MarketPlaceErrorsEnumsAndStruct {
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

    struct UserBalance {
        uint256 totalDeposited; // Total amount user has deposited (including mint payments)
        uint256 availableBalance; // Current available balance to spend/withdraw
        uint256 lockedBalance; // Balance locked in active listings/bids
        uint256 totalWithdrawn; // Total amount withdrawn (to enforce limits)
        uint256 totalProfits; // Lifetime profits earned from sales
    }

    struct EventInfo {
        bool eventEnded; // Whether event has ended
        bool emergencyRefund; // Whether emergency refunds are enabled
        uint256 totalDeposited; // Total amount deposited for this event
        mapping(address => uint256) userOriginalDeposits; // Original deposits per user for emergency refunds
    }

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/
    error Marketplace__ItemNotListed(address tokenContract, uint256 tokenId);
    error Marketplace__InsufficientDeposits(uint256 required, uint256 available);
    error Marketplace__CannotBuyOwnItem();
    error Marketplace__PaymentFailed();
    error Marketplace__NotAuthorized();
    error Marketplace__InvalidTime();
    error Marketplace__AuctionEnded();
    error Marketplace__AuctionActive();
    error Marketplace__BidTooLow();
    error Marketplace__PriceIncreaseTooHigh();
    error Marketplace__ResaleCooldownActive();
    error Marketplace__EventNotCompleted();
    error Marketplace__EventNotCancelled();
    error Marketplace__ContractPaused();
    error Marketplace__RoyaltyPaymentFailed();
    error Marketplace__NoDepositsForEvent();
    error Marketplace__InsufficientWithdrawalBalance();
    error Marketplace__NotEventContract();
    error Marketplace__InvalidAddress();
    error Marketplace__InvalidFeePercentage(uint256 provided, uint256 max);
    error Marketplace__PriceMustBeGreaterThanZero();
    error Marketplace__EmergencyRefundActive();
    error Marketplace__NotFixedPrice();
    error Marketplace__NotAuction();
    error Marketplace__AuctionNotActive();
    error Marketplace__NotTokenOwner();
    error Marketplace__NotApproved();
    error Marketplace__EventContractNotAuthorized();
    error Marketplace__InvalidDuration();
    error Marketplace__ReservePriceTooLow();
    error Marketplace__InvalidBidIncrement();
    error Marketplace__NoProfitsToCollect();
    error Marketplace__EventNotEnded();
    error Marketplace__NoRoyaltiesToWithdraw();
    error Marketplace__NoPlatformFeesToWithdraw();
    error Marketplace__EventAlreadyEnded();
    error Marketplace__EmergencyRefundNotEnabled();
    error Marketplace__NoDepositsToRefund();
    error Marketplace__FundsAlreadyReleased();
    error Marketplace__UserNotVerified(address user);
}
