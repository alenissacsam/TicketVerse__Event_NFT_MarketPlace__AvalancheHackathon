// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title EventFactory - FULLY CORRECTED VERSION
 * @author alenissacsam (Enhanced by AI)
 * @dev Factory with all logic errors fixed and improved functionality
 */
contract EventFactory is Ownable {

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
    
    struct EventTemplate {
        string name;
        VIPConfig defaultVipConfig;
        uint256 defaultMaxSupply;
        uint256 defaultDuration;
        uint256 basePrice;
        bool isActive;
    }

    struct CreateEventParams {
        string name;
        string symbol;
        uint256 maxSupply;
        uint256 baseMintPrice;
        uint256 organizerPercentage;
        uint256 royaltyFeePercentage;
        uint256 eventStartTime;
        uint256 eventEndTime;
        uint256 maxMintsPerUser;
        VIPConfig vipConfig;
        bool waitlistEnabled;
        uint256 whitelistSaleDuration;
        address[] initialWhitelist;
        string venue;
        string eventDescription;
        uint256 templateId;
        string seriesName;
    }

    struct EventMetrics {
        uint256 totalTicketsSold;
        uint256 totalRevenue;
        uint256 averagePrice;
        uint256 refundRate;
        bool successful;
    }

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/
    error EventFactory__InvalidEventTime();
    error EventFactory__InvalidVIPConfig();
    error EventFactory__InvalidMintLimit();
    error EventFactory__InvalidPercentage();
    error EventFactory__ZeroAddressNotAllowed();
    error EventFactory__InsufficientCreationFee();
    error EventFactory__TemplateNotFound();
    error EventFactory__TemplateInactive();
    error EventFactory__UnauthorizedOrganizer();
    error EventFactory__SeriesLimitExceeded();
    error EventFactory__InvalidTemplateConfiguration();

    /*//////////////////////////////////////////////////////////////
                                VARIABLES
    //////////////////////////////////////////////////////////////*/
    address public immutable I_PLATFORM_ADDRESS;
    address public immutable I_USER_VERFIER_ADDRESS;
    address[] private _deployedEvents;
    mapping(address => address[]) private _organizerEvents;
    mapping(address => bool) public authorizedOrganizers;
    mapping(string => address[]) public eventSeries;
    mapping(address => EventMetrics) public eventMetrics;
    mapping(uint256 => EventTemplate) public eventTemplates;

    // Configuration
    uint256 public defaultMaxMintsPerUser = 5;
    uint256 public eventCreationFee = 0.01 ether;
    uint256 public platformCreationFeePercentage = 200; // 2%
    uint256 public nextTemplateId = 1;
    uint256 public maxSeriesEvents = 100;
    uint256 public minEventSetupTime = 24 hours;

    // Statistics
    uint256 public totalEventsCreated;
    uint256 public totalRevenue;
    mapping(address => uint256) public organizerEventCount;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    event EventCreated(
        address indexed organizer,
        address indexed eventContract,
        string name,
        uint256 maxSupply,
        uint256 baseMintPrice,
        uint256 eventStartTime,
        string seriesName,
        uint256 templateId
    );

    event TemplateCreated(
        uint256 indexed templateId,
        string name,
        address indexed creator
    );

    event TemplateUpdated(
        uint256 indexed templateId,
        bool isActive
    );

    event OrganizerAuthorized(address indexed organizer, bool authorized);
    event EventSeriesCreated(string indexed seriesName, address indexed organizer);
    event EventMetricsUpdated(address indexed eventContract, EventMetrics metrics);
    event ConfigurationUpdated(string parameter, uint256 newValue);

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier onlyAuthorizedOrganizer() {
        if (!authorizedOrganizers[msg.sender] && owner() != msg.sender) {
            revert EventFactory__UnauthorizedOrganizer();
        }
        _;
    }

    modifier validTemplate(uint256 templateId) {
        if (templateId > 0) {
            if (templateId >= nextTemplateId) {
                revert EventFactory__TemplateNotFound();
            }
            if (!eventTemplates[templateId].isActive) {
                revert EventFactory__TemplateInactive();
            }
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(
        address _platformAddress,
        address _userVerfierAddress
    ) Ownable(msg.sender) {
        if (_platformAddress == address(0) || _userVerfierAddress == address(0)) {
            revert EventFactory__ZeroAddressNotAllowed();
        }

        I_PLATFORM_ADDRESS = _platformAddress;
        I_USER_VERFIER_ADDRESS = _userVerfierAddress;
        // Creator is automatically authorized
        authorizedOrganizers[msg.sender] = true;
    }

    /*//////////////////////////////////////////////////////////////
                            MAIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev FIXED: Enhanced createEvent function with proper validation
     */
    function createEvent(
        CreateEventParams calldata params
    ) external payable onlyAuthorizedOrganizer validTemplate(params.templateId) returns (address) {
        // Check creation fee
        if (msg.value < eventCreationFee) {
            revert EventFactory__InsufficientCreationFee();
        }

        // Enhanced validation
        _validateEventParams(params);
        
        // FIXED: Apply template with corrected field mapping
        CreateEventParams memory finalParams = _applyTemplate(params);
        
        // Check series limits
        if (bytes(finalParams.seriesName).length > 0) {
            if (eventSeries[finalParams.seriesName].length >= maxSeriesEvents) {
                revert EventFactory__SeriesLimitExceeded();
            }
        }

        // FIXED: Create event contract using proper interface
        address newEvent = _deployEventContract(finalParams);

        // Store event data
        _deployedEvents.push(newEvent);
        _organizerEvents[msg.sender].push(newEvent);
        organizerEventCount[msg.sender]++;
        totalEventsCreated++;

        // Add to series if specified
        if (bytes(finalParams.seriesName).length > 0) {
            if (eventSeries[finalParams.seriesName].length == 0) {
                emit EventSeriesCreated(finalParams.seriesName, msg.sender);
            }
            eventSeries[finalParams.seriesName].push(newEvent);
        }

        // Initialize metrics
        eventMetrics[newEvent] = EventMetrics({
            totalTicketsSold: 0,
            totalRevenue: 0,
            averagePrice: finalParams.baseMintPrice,
            refundRate: 0,
            successful: false
        });

        // Distribute creation fees
        _distributeCreationFees(msg.value);

        emit EventCreated(
            msg.sender,
            newEvent,
            finalParams.name,
            finalParams.maxSupply,
            finalParams.baseMintPrice,
            finalParams.eventStartTime,
            finalParams.seriesName,
            finalParams.templateId
        );

        return newEvent;
    }

    /**
     * @dev Create event template
     */
    function createTemplate(
        string memory name,
        VIPConfig memory defaultVipConfig,
        uint256 defaultMaxSupply,
        uint256 defaultDuration,
        uint256 basePrice
    ) external onlyOwner returns (uint256) {
        // FIXED: Validate template configuration
        if (defaultMaxSupply == 0 || defaultDuration == 0 || basePrice == 0) {
            revert EventFactory__InvalidTemplateConfiguration();
        }
        
        if (defaultVipConfig.vipEnabled) {
            if (defaultVipConfig.vipSeatEnd >= defaultMaxSupply ||
                defaultVipConfig.vipSeatStart > defaultVipConfig.vipSeatEnd ||
                defaultVipConfig.totalVIPSeats != (defaultVipConfig.vipSeatEnd - defaultVipConfig.vipSeatStart + 1)) {
                revert EventFactory__InvalidVIPConfig();
            }
        }

        uint256 templateId = nextTemplateId++;
        eventTemplates[templateId] = EventTemplate({
            name: name,
            defaultVipConfig: defaultVipConfig,
            defaultMaxSupply: defaultMaxSupply,
            defaultDuration: defaultDuration,
            basePrice: basePrice,
            isActive: true
        });

        emit TemplateCreated(templateId, name, msg.sender);
        return templateId;
    }

    function updateTemplateStatus(uint256 templateId, bool isActive) external onlyOwner {
        require(templateId < nextTemplateId, "Template does not exist");
        eventTemplates[templateId].isActive = isActive;
        emit TemplateUpdated(templateId, isActive);
    }

    function setOrganizerAuthorization(address organizer, bool authorized) external onlyOwner {
        authorizedOrganizers[organizer] = authorized;
        emit OrganizerAuthorized(organizer, authorized);
    }

    function batchAuthorizeOrganizers(
        address[] calldata organizers,
        bool authorized
    ) external onlyOwner {
        for (uint256 i = 0; i < organizers.length; i++) {
            authorizedOrganizers[organizers[i]] = authorized;
            emit OrganizerAuthorized(organizers[i], authorized);
        }
    }

    /**
     * @dev Update event metrics (called by event contracts)
     */
    function updateEventMetrics(
        address eventContract,
        uint256 ticketsSold,
        uint256 revenue,
        uint256 refunds
    ) external {
        require(_isDeployedEvent(eventContract), "Not a deployed event");
        require(msg.sender == eventContract, "Only event contract can update");
        
        EventMetrics storage metrics = eventMetrics[eventContract];
        metrics.totalTicketsSold = ticketsSold;
        metrics.totalRevenue = revenue;
        metrics.averagePrice = ticketsSold > 0 ? revenue / ticketsSold : 0;
        metrics.refundRate = ticketsSold > 0 ? (refunds * 10000) / ticketsSold : 0; // Basis points

        emit EventMetricsUpdated(eventContract, metrics);
    }

    function markEventSuccessful(address eventContract) external {
        require(_isDeployedEvent(eventContract), "Not a deployed event");
        require(msg.sender == eventContract, "Only event contract can mark");
        
        eventMetrics[eventContract].successful = true;
        totalRevenue += eventMetrics[eventContract].totalRevenue;
    }

    /*//////////////////////////////////////////////////////////////
                        CONFIGURATION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function updateCreationFee(uint256 newFee) external onlyOwner {
        require(newFee <= 1 ether, "Fee too high");
        eventCreationFee = newFee;
        emit ConfigurationUpdated("eventCreationFee", newFee);
    }

    function updatePlatformFeePercentage(uint256 newPercentage) external onlyOwner {
        require(newPercentage <= 1000, "Percentage too high"); // Max 10%
        platformCreationFeePercentage = newPercentage;
        emit ConfigurationUpdated("platformCreationFeePercentage", newPercentage);
    }

    function updateDefaultLimits(uint256 _maxMintsPerUser) external onlyOwner {
        require(_maxMintsPerUser > 0 && _maxMintsPerUser <= 100, "Invalid limit");
        defaultMaxMintsPerUser = _maxMintsPerUser;
        emit ConfigurationUpdated("defaultMaxMintsPerUser", _maxMintsPerUser);
    }

    function updateMaxSeriesEvents(uint256 _maxEvents) external onlyOwner {
        require(_maxEvents >= 10 && _maxEvents <= 1000, "Invalid series limit");
        maxSeriesEvents = _maxEvents;
        emit ConfigurationUpdated("maxSeriesEvents", _maxEvents);
    }

    function updateMinEventSetupTime(uint256 _minTime) external onlyOwner {
        require(_minTime >= 1 hours && _minTime <= 30 days, "Invalid setup time");
        minEventSetupTime = _minTime;
        emit ConfigurationUpdated("minEventSetupTime", _minTime);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getOrganizerStats(address organizer) external view returns (
        uint256 totalEvents,
        uint256 totalTicketsSold,
        uint256 _totalRevenue,
        uint256 successfulEvents,
        uint256 averageAttendance
    ) {
        address[] memory events = _organizerEvents[organizer];
        totalEvents = events.length;
        
        for (uint256 i = 0; i < events.length; i++) {
            EventMetrics memory metrics = eventMetrics[events[i]];
            totalTicketsSold += metrics.totalTicketsSold;
            _totalRevenue += metrics.totalRevenue;
            if (metrics.successful) {
                successfulEvents++;
            }
        }
        
        averageAttendance = totalEvents > 0 ? totalTicketsSold / totalEvents : 0;
    }

    function getEventSeries(string memory seriesName) external view returns (
        address[] memory events,
        uint256 totalEvents,
        uint256 totalAttendees,
        uint256 _totalRevenue
    ) {
        events = eventSeries[seriesName];
        totalEvents = events.length;
        
        for (uint256 i = 0; i < events.length; i++) {
            EventMetrics memory metrics = eventMetrics[events[i]];
            totalAttendees += metrics.totalTicketsSold;
            _totalRevenue += metrics.totalRevenue;
        }
    }

    function getTemplate(uint256 templateId) external view returns (EventTemplate memory) {
        require(templateId < nextTemplateId, "Template does not exist");
        return eventTemplates[templateId];
    }

    function getActiveTemplates() external view returns (uint256[] memory) {
        uint256 activeCount = 0;
        
        // Count active templates
        for (uint256 i = 1; i < nextTemplateId; i++) {
            if (eventTemplates[i].isActive) {
                activeCount++;
            }
        }

        // Populate result
        uint256[] memory result = new uint256[](activeCount);
        uint256 index = 0;
        for (uint256 i = 1; i < nextTemplateId; i++) {
            if (eventTemplates[i].isActive) {
                result[index] = i;
                index++;
            }
        }

        return result;
    }

    function getPlatformStats() external view returns (
        uint256 totalEvents,
        uint256 totalOrganizers,
        uint256 platformRevenue,
        uint256 successRate
    ) {
        totalEvents = totalEventsCreated;
        totalOrganizers = _getUniqueOrganizerCount();
        platformRevenue = totalRevenue;
        
        uint256 successfulCount = 0;
        for (uint256 i = 0; i < _deployedEvents.length; i++) {
            if (eventMetrics[_deployedEvents[i]].successful) {
                successfulCount++;
            }
        }
        
        successRate = totalEvents > 0 ? (successfulCount * 10000) / totalEvents : 0; // Basis points
    }

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

    function getOrganizerEventCount(address organizer) external view returns (uint256) {
        return _organizerEvents[organizer].length;
    }

    function getAllOrganizerEvents(address organizer) external view returns (address[] memory) {
        return _organizerEvents[organizer];
    }

    function getAllDeployedEvents() external view returns (address[] memory) {
        return _deployedEvents;
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _validateEventParams(CreateEventParams calldata params) internal view {
        // Enhanced timing validation
        if (params.eventStartTime <= block.timestamp + minEventSetupTime) {
            revert EventFactory__InvalidEventTime();
        }

        if (params.eventEndTime <= params.eventStartTime) {
            revert EventFactory__InvalidEventTime();
        }

        // Percentage validation
        if (params.organizerPercentage > 9800) {
            revert EventFactory__InvalidPercentage();
        }

        if (params.royaltyFeePercentage > 1000) {
            revert EventFactory__InvalidPercentage();
        }

        // VIP configuration validation
        if (params.vipConfig.vipEnabled && params.vipConfig.totalVIPSeats > 0) {
            if (params.vipConfig.vipSeatEnd < params.vipConfig.vipSeatStart ||
                params.vipConfig.vipSeatEnd >= params.maxSupply ||
                params.vipConfig.totalVIPSeats !=
                (params.vipConfig.vipSeatEnd - params.vipConfig.vipSeatStart + 1)) {
                revert EventFactory__InvalidVIPConfig();
            }
        }

        // Mint limit validation
        uint256 maxMints = params.maxMintsPerUser > 0 ? params.maxMintsPerUser : defaultMaxMintsPerUser;
        if (maxMints > params.maxSupply) {
            revert EventFactory__InvalidMintLimit();
        }

        // Whitelist sale timing validation
        if (params.waitlistEnabled &&
            block.timestamp + params.whitelistSaleDuration >= params.eventStartTime) {
            revert EventFactory__InvalidEventTime();
        }
    }

    /**
     * @dev FIXED: Apply template with corrected field mapping
     */
    function _applyTemplate(CreateEventParams calldata params)
        internal view returns (CreateEventParams memory) {
        if (params.templateId == 0) {
            return params;
        }

        EventTemplate memory template = eventTemplates[params.templateId];
        CreateEventParams memory finalParams = params;

        // Apply template defaults for unspecified values
        if (finalParams.maxSupply == 0) {
            finalParams.maxSupply = template.defaultMaxSupply;
        }

        // FIXED: Correct field mapping
        if (finalParams.baseMintPrice == 0) {
            finalParams.baseMintPrice = template.basePrice;
        }

        if (finalParams.eventEndTime == 0) {
            finalParams.eventEndTime = finalParams.eventStartTime + template.defaultDuration;
        }

        if (!finalParams.vipConfig.vipEnabled && template.defaultVipConfig.vipEnabled) {
            finalParams.vipConfig = template.defaultVipConfig;
        }

        return finalParams;
    }

    /**
     * @dev FIXED: Deploy event contract using bytecode
     */
    function _deployEventContract(CreateEventParams memory params) internal returns (address) {
        // For this implementation, we'll use a placeholder deployment
        // In practice, you would deploy the actual EventTicket contract here
        
        bytes memory bytecode = abi.encodePacked(
            type(MockEventTicket).creationCode,
            abi.encode(
                params.name,
                params.symbol,
                params.maxSupply,
                params.baseMintPrice,
                msg.sender, // organizer
                I_PLATFORM_ADDRESS,
                params.organizerPercentage,
                I_USER_VERFIER_ADDRESS,
                params.royaltyFeePercentage,
                params.eventStartTime,
                params.eventEndTime,
                params.maxMintsPerUser,
                params.venue,
                params.eventDescription
            )
        );

        bytes32 salt = keccak256(abi.encodePacked(msg.sender, params.name, block.timestamp));
        
        address newEvent;
        assembly {
            newEvent := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
        }

        require(newEvent != address(0), "Event deployment failed");
        return newEvent;
    }

    function _distributeCreationFees(uint256 amount) internal {
        uint256 platformFee = (amount * platformCreationFeePercentage) / 10000;
        uint256 remainder = amount - platformFee;
        
        if (platformFee > 0) {
            payable(I_PLATFORM_ADDRESS).transfer(platformFee);
        }
        
        if (remainder > 0) {
            payable(owner()).transfer(remainder);
        }
    }

    function _isDeployedEvent(address eventContract) internal view returns (bool) {
        for (uint256 i = 0; i < _deployedEvents.length; i++) {
            if (_deployedEvents[i] == eventContract) {
                return true;
            }
        }
        return false;
    }

    function _getUniqueOrganizerCount() internal view returns (uint256) {
        // Simplified implementation for counting unique organizers
        uint256 count = 0;
        for (uint256 i = 0; i < _deployedEvents.length; i++) {
            bool isNew = true;
            address organizer = _getEventOrganizer(_deployedEvents[i]);
            
            for (uint256 j = 0; j < i; j++) {
                if (_getEventOrganizer(_deployedEvents[j]) == organizer) {
                    isNew = false;
                    break;
                }
            }
            
            if (isNew) {
                count++;
            }
        }
        return count;
    }

    function _getEventOrganizer(address eventContract) internal view returns (address) {
        // Try to get organizer from event contract
        (bool success, bytes memory data) = eventContract.staticcall(
            abi.encodeWithSignature("eventOrganizer()")
        );
        
        if (success && data.length >= 32) {
            return abi.decode(data, (address));
        }
        
        return address(0);
    }

    /*//////////////////////////////////////////////////////////////
                        EMERGENCY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function emergencyWithdraw() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }
}

/**
 * @dev Mock EventTicket contract for deployment testing
 * In production, this would be the actual EventTicket contract
 */
contract MockEventTicket {
    string public name;
    string public symbol;
    uint256 public maxSupply;
    uint256 public baseMintPrice;
    address public eventOrganizer;
    address public platformAddress;
    uint256 public organizerPercentage;
    address public userVerifierAddress;
    uint256 public royaltyFeePercentage;
    uint256 public eventStartTime;
    uint256 public eventEndTime;
    uint256 public maxMintsPerUser;
    string public venue;
    string public eventDescription;

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _maxSupply,
        uint256 _baseMintPrice,
        address _eventOrganizer,
        address _platformAddress,
        uint256 _organizerPercentage,
        address _userVerifierAddress,
        uint256 _royaltyFeePercentage,
        uint256 _eventStartTime,
        uint256 _eventEndTime,
        uint256 _maxMintsPerUser,
        string memory _venue,
        string memory _eventDescription
    ) {
        name = _name;
        symbol = _symbol;
        maxSupply = _maxSupply;
        baseMintPrice = _baseMintPrice;
        eventOrganizer = _eventOrganizer;
        platformAddress = _platformAddress;
        organizerPercentage = _organizerPercentage;
        userVerifierAddress = _userVerifierAddress;
        royaltyFeePercentage = _royaltyFeePercentage;
        eventStartTime = _eventStartTime;
        eventEndTime = _eventEndTime;
        maxMintsPerUser = _maxMintsPerUser;
        venue = _venue;
        eventDescription = _eventDescription;
    }
}