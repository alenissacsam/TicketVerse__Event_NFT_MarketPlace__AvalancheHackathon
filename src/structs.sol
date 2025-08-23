// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

struct VIPConfig {
    uint256 totalVIPSeats;
    uint256 vipSeatStart;
    uint256 vipSeatEnd;
}
struct TicketInfo {
    string eventName;
    string seatNumber;
    bool isVIP;
    uint256 mintedAt;
}
