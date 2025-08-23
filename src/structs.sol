// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

struct VIPConfig {
    uint256 totalVIPSeats; // Total number of VIP seats available
    uint256 vipSeatStart; // Starting seat number for VIP section
    uint256 vipSeatEnd; // Ending seat number for VIP section
    uint256 vipHoldingPeriod; // Time period VIP holders must hold previous tickets
    uint256 vipPriceMultiplier; // VIP price multiplier (basis points, 15000 = 1.5x)
    bool vipEnabled; // Enable/disable VIP functionality
}

struct TicketInfo {
    string eventName; // Name of the event
    string seatNumber; // Seat identifier (alphanumeric)
    bool isVIP; // Whether this is a VIP ticket
    uint256 mintedAt; // Timestamp when ticket was minted
    uint256 pricePaid; // Actual price paid for this ticket
    bool isUsed; // Whether ticket was used for event entry
    bool isTransferable; // Whether ticket can be transferred
    string venue; // Event venue information
}

struct EventTemplate {
    string name; // Template name
    VIPConfig defaultVipConfig; // Default VIP configuration
    uint256 defaultMaxSupply; // Default maximum ticket supply
    uint256 defaultDuration; // Default event duration
    uint256 basePrice; // Base ticket price
    bool isActive; // Whether template is active
}

struct SeatInfo {
    string section; // Seat section (A, B, C, etc.)
    uint256 row; // Row number
    uint256 number; // Seat number within row
    uint256 priceMultiplier; // Price multiplier for this seat (basis points)
    bool isVIP; // Whether this is a VIP seat
}