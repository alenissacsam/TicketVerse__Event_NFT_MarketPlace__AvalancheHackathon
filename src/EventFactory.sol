// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {EventTicket} from "./EventTicket.sol";

contract EventFactory is Ownable {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/
    error UnauthorizedOrganizer();
    error ZeroAddress();
    error InsufficientCreationFee();
    error DeploymentFailed();
    error FeeTooHigh();
    error PercentageTooHigh();
    error InvalidLimit();
    error InvalidSetupTime();

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    address public immutable I_PLATFORM_ADDRESS;
    address public immutable I_USER_VERFIER_ADDRESS;

    address[] private _deployedEvents;
    mapping(address => address[]) private _organizerEvents;
    mapping(address => bool) public authorizedOrganizers;

    // Config
    uint256 public defaultMaxMintsPerUser = 5;
    uint256 public eventCreationFee = 0.01 ether;
    uint256 public platformCreationFeePercentage = 200; // 2%
    uint256 public minEventSetupTime = 24 hours;

    address public _marketplaceAddress;

    // Counters
    uint256 public totalEventsCreated;
    mapping(address => uint256) public organizerEventCount;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    event EventCreated(
        address indexed organizer,
        address indexed eventContract
    );
    event OrganizerAuthorized(address indexed organizer, bool authorized);
    event ConfigUpdated(bytes32 key, uint256 value);

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier onlyAuthorizedOrganizer() {
        if (!authorizedOrganizers[msg.sender] && owner() != msg.sender) {
            revert UnauthorizedOrganizer();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(
        address _platformAddress,
        address _userVerifierAddress
    ) Ownable(msg.sender) {
        if (
            _platformAddress == address(0) || _userVerifierAddress == address(0)
        ) revert ZeroAddress();
        I_PLATFORM_ADDRESS = _platformAddress;
        I_USER_VERFIER_ADDRESS = _userVerifierAddress;

        // Bootstrap deployer as authorized organizer
        authorizedOrganizers[msg.sender] = true;
        emit OrganizerAuthorized(msg.sender, true);
    }

    /*//////////////////////////////////////////////////////////////
                           CREATE EVENT (THIN)
    //////////////////////////////////////////////////////////////*/
    struct VIPConfig {
        uint256 totalVIPSeats;
        uint256 vipSeatStart;
        uint256 vipSeatEnd;
        uint256 vipHoldingPeriod;
        bool vipEnabled;
    }

    struct CreateEventParams {
        string name;
        string symbol;
        uint256 maxSupply;
        uint256 baseMintPrice;
        uint256 organizerPercentage; // bps
        uint256 royaltyFeePercentage; // bps
        uint256 eventStartTime;
        uint256 eventEndTime;
        uint256 maxMintsPerUser; // if 0, factory uses defaultMaxMintsPerUser
        VIPConfig vipConfig;
        uint256 vipMintPrice;
        bool waitlistEnabled;
        uint256 whitelistSaleDuration;
        address[] initialWhitelist;
        string venue;
        string eventDescription;
        // If your EventTicket supports these additional params (from your extended version),
        // keep them; otherwise remove.
        uint256 seatCount; // optional: must equal maxSupply in EventTicket
        string vipTokenURIBase; // optional: base URI for VIP seats
        string nonVipTokenURIBase; // optional: base URI for regular seats
    }

    function addMarketplaceAddress(address _marketplace) public isAdmin {
        _marketplaceAddress = _marketplace;
    }

    function createEvent(
        CreateEventParams calldata p
    ) external payable onlyAuthorizedOrganizer returns (address deployed) {
        if (msg.value < eventCreationFee) revert InsufficientCreationFee();

        // Delegate detailed validation to EventTicket constructor to save factory bytecode.
        uint256 mintsPerUser = p.maxMintsPerUser > 0
            ? p.maxMintsPerUser
            : defaultMaxMintsPerUser;

        // Deploy the event ticket contract
        // Note: Keep the constructor signature aligned with your EventTicket implementation.
        EventTicket newEvent = new EventTicket(
            p.name,
            p.symbol,
            p.maxSupply,
            p.baseMintPrice,
            msg.sender, // organizer
            I_PLATFORM_ADDRESS,
            p.organizerPercentage,
            I_USER_VERFIER_ADDRESS,
            p.royaltyFeePercentage,
            p.eventStartTime,
            p.eventEndTime,
            mintsPerUser,
            EventTicket.VIPConfig(
                p.vipConfig.totalVIPSeats,
                p.vipConfig.vipSeatStart,
                p.vipConfig.vipSeatEnd,
                p.vipConfig.vipHoldingPeriod,
                p.vipConfig.vipEnabled
            ),
            p.vipMintPrice,
            p.waitlistEnabled,
            p.whitelistSaleDuration,
            p.initialWhitelist,
            p.venue,
            p.eventDescription,
            p.seatCount,
            p.vipTokenURIBase,
            p.nonVipTokenURIBase
        );
        newEvent.addMarketPlaceAddress(_marketplaceAddress);

        deployed = address(newEvent);
        if (deployed == address(0)) revert DeploymentFailed();

        // Bookkeeping
        _deployedEvents.push(deployed);
        _organizerEvents[msg.sender].push(deployed);
        organizerEventCount[msg.sender] += 1;
        totalEventsCreated += 1;

        // Fee split (platform + owner)
        _distributeCreationFees(msg.value);

        emit EventCreated(msg.sender, deployed);
        return deployed;
    }

    /*//////////////////////////////////////////////////////////////
                           AUTHORIZATION
    //////////////////////////////////////////////////////////////*/
    function setOrganizerAuthorization(
        address organizer,
        bool authorized
    ) external isAdmin {
        authorizedOrganizers[organizer] = authorized;
        emit OrganizerAuthorized(organizer, authorized);
    }

    /*//////////////////////////////////////////////////////////////
                               GETTERS
    //////////////////////////////////////////////////////////////*/
    function getAllDeployedEvents() external view returns (address[] memory) {
        return _deployedEvents;
    }

    function getAllOrganizerEvents(
        address organizer
    ) external view returns (address[] memory) {
        return _organizerEvents[organizer];
    }

    function getTotalEventsCreated() external view returns (uint256) {
        return _deployedEvents.length;
    }

    function getOrganizerEventCount(
        address organizer
    ) external view returns (uint256) {
        return _organizerEvents[organizer].length;
    }

    /*//////////////////////////////////////////////////////////////
                              CONFIG SETTERS
    //////////////////////////////////////////////////////////////*/
    function updateCreationFee(uint256 newFee) external isAdmin {
        if (newFee > 1 ether) revert FeeTooHigh();
        eventCreationFee = newFee;
        emit ConfigUpdated("eventCreationFee", newFee);
    }

    function updatePlatformFeePercentage(uint256 newPct) external isAdmin {
        if (newPct > 1000) revert PercentageTooHigh(); // Max 10%
        platformCreationFeePercentage = newPct;
        emit ConfigUpdated("platformCreationFeePercentage", newPct);
    }

    function updateDefaultLimits(uint256 _maxMintsPerUser) external isAdmin {
        if (!(_maxMintsPerUser > 0 && _maxMintsPerUser <= 100))
            revert InvalidLimit();
        defaultMaxMintsPerUser = _maxMintsPerUser;
        emit ConfigUpdated("defaultMaxMintsPerUser", _maxMintsPerUser);
    }

    function updateMinEventSetupTime(uint256 _minTime) external isAdmin {
        if (!(_minTime >= 1 hours && _minTime <= 30 days))
            revert InvalidSetupTime();
        minEventSetupTime = _minTime;
        emit ConfigUpdated("minEventSetupTime", _minTime);
    }

    /*//////////////////////////////////////////////////////////////
                               INTERNAL
    //////////////////////////////////////////////////////////////*/
    function _distributeCreationFees(uint256 amount) internal {
        uint256 platformFee = (amount * platformCreationFeePercentage) / 10000;
        uint256 remainder = amount - platformFee;
        if (platformFee > 0) {
            (bool success, ) = I_PLATFORM_ADDRESS.call{value: platformFee}("");
            // Using a more specific error than DeploymentFailed would be ideal,
            // but this prevents the transaction from silently failing.
            if (!success) revert DeploymentFailed();
        }
        if (remainder > 0) {
            (bool success, ) = owner().call{value: remainder}("");
            if (!success) revert DeploymentFailed();
        }
    }

    /*//////////////////////////////////////////////////////////////
                               EMERGENCY
    //////////////////////////////////////////////////////////////*/
    function emergencyWithdraw() external isAdmin {
        payable(owner()).transfer(address(this).balance);
    }
}
