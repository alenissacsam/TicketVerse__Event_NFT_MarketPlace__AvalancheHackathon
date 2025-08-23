// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {EventTicket} from "./EventTicket.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "./structs.sol";

/**
 * @title EventFactory
 * @author alenissacsam
 * @dev Enhanced factory contract for creating and managing custom event ticket contracts with advanced features.
 */
contract EventFactory is Ownable {
    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/
    struct CreateEventParams {
        string name;
        string symbol;
        uint256 maxSupply;
        uint256 mintPrice;
        uint256 organizerPercentage;
        uint256 royaltyFeePercentage;
        uint256 eventStartTime;
        uint256 maxMintsPerUser;
        VIPConfig vipConfig;
        bool waitlistEnabled;
        uint256 whitelistSaleDuration;
        address[] initialWhitelist;
    }

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/
    error EventFactory__InvalidEventTime();
    error EventFactory__InvalidVIPConfig();
    error EventFactory__InvalidMintLimit();

    /*//////////////////////////////////////////////////////////////
                                VARIABLES
    //////////////////////////////////////////////////////////////*/
    address public immutable I_PLATFORM_ADDRESS;
    address public immutable I_USER_VERFIER_ADDRESS;

    address[] private _deployedEvents;
    mapping(address => address[]) private _organizerEvents;

    // Default limits that can be overridden per event
    uint256 public defaultMaxMintsPerUser = 5;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    event EventCreated(
        address indexed organizer,
        address indexed eventContract,
        string name,
        uint256 maxSupply,
        uint256 mintPrice,
        uint256 eventStartTime
    );

    event DefaultLimitsUpdated(uint256 maxMintsPerUser);

    /*//////////////////////////////////////////////////////////////
                                FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    constructor(
        address _platformAddress,
        address _userVerfierAddress
    ) Ownable(msg.sender) {
        I_PLATFORM_ADDRESS = _platformAddress;
        I_USER_VERFIER_ADDRESS = _userVerfierAddress;
    }

    /**
     * @dev Enhanced createEvent function with all new features
     */
    function createEvent(
        CreateEventParams calldata params
    ) external returns (EventTicket) {
        // Validation
        if (params.eventStartTime <= block.timestamp + 1 hours) {
            revert EventFactory__InvalidEventTime();
        }

        if (params.vipConfig.totalVIPSeats > 0) {
            if (
                params.vipConfig.vipSeatEnd < params.vipConfig.vipSeatStart ||
                params.vipConfig.vipSeatEnd >= params.maxSupply ||
                params.vipConfig.totalVIPSeats !=
                (params.vipConfig.vipSeatEnd -
                    params.vipConfig.vipSeatStart +
                    1)
            ) {
                revert EventFactory__InvalidVIPConfig();
            }
        }

        uint256 maxMints = params.maxMintsPerUser;
        // Use default if not specified
        if (maxMints == 0) {
            maxMints = defaultMaxMintsPerUser;
        }

        if (maxMints > params.maxSupply) {
            revert EventFactory__InvalidMintLimit();
        }

        EventTicket newEvent = new EventTicket(
            params.name,
            params.symbol,
            params.maxSupply,
            params.mintPrice,
            msg.sender, // organizer
            I_PLATFORM_ADDRESS,
            params.organizerPercentage,
            I_USER_VERFIER_ADDRESS,
            params.royaltyFeePercentage,
            params.eventStartTime,
            maxMints,
            params.vipConfig,
            params.waitlistEnabled,
            params.whitelistSaleDuration,
            params.initialWhitelist
        );

        _deployedEvents.push(address(newEvent));
        _organizerEvents[msg.sender].push(address(newEvent));

        emit EventCreated(
            msg.sender,
            address(newEvent), // eventContract
            params.name,
            params.maxSupply,
            params.mintPrice,
            params.eventStartTime
        );

        return newEvent;
    }

    /**
     * @dev Update default limits (only owner)
     */
    function updateDefaultLimits(uint256 _maxMintsPerUser) external onlyOwner {
        defaultMaxMintsPerUser = _maxMintsPerUser;

        emit DefaultLimitsUpdated(_maxMintsPerUser);
    }

    /*//////////////////////////////////////////////////////////////
                            EXTERNAL VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @dev Get a paginated list of all deployed event contracts.
     * @param offset The starting index.
     * @param limit The maximum number of items to return.
     * @return An array of event contract addresses.
     */
    function getDeployedEvents(
        uint256 offset,
        uint256 limit
    ) external view returns (address[] memory) {
        uint256 count = _deployedEvents.length;
        if (offset >= count) {
            return new address[](0);
        }

        uint256 end = offset + limit > count ? count : offset + limit;
        address[] memory result = new address[](end - offset);
        for (uint256 i = 0; i < result.length; i++) {
            result[i] = _deployedEvents[offset + i];
        }
        return result;
    }

    /**
     * @dev Get a paginated list of event contracts for a specific organizer.
     * @param organizer The address of the event organizer.
     * @param offset The starting index.
     * @param limit The maximum number of items to return.
     * @return An array of event contract addresses for the given organizer.
     */
    function getOrganizerEvents(
        address organizer,
        uint256 offset,
        uint256 limit
    ) external view returns (address[] memory) {
        address[] storage events = _organizerEvents[organizer];
        uint256 count = events.length;
        if (offset >= count) {
            return new address[](0);
        }

        uint256 end = offset + limit > count ? count : offset + limit;
        address[] memory result = new address[](end - offset);
        for (uint256 i = 0; i < result.length; i++) {
            result[i] = events[offset + i];
        }
        return result;
    }

    function getTotalEventsCreated() external view returns (uint256) {
        return _deployedEvents.length;
    }
}
