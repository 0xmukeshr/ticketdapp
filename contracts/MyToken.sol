// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";


contract EventTicketNFT is ERC721URIStorage, Ownable {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;
    Counters.Counter private _eventIds;

    // PYUSD token contract address
    IERC20 public constant PYUSD_TOKEN = IERC20(0xCaC524BcA292aaade2DF8A05cC58F0a65B1B3bB9);
    
    // Discount percentage for PYUSD purchases (15%)
    uint256 public constant PYUSD_DISCOUNT = 15;

    struct EventDetails {
        string name;
        uint256 ethPrice;     // Price in ETH (18 decimals)
        uint256 pyusdPrice;   // Price in PYUSD (6 decimals)
        uint256 totalTickets;
        uint256 remainingTickets;
        string baseTokenURI;
        address eventOwner;
        bool isActive;
    }

    mapping(uint256 => EventDetails) public events;
 
    mapping(uint256 => mapping(address => uint256)) public ticketsPurchased;

    event EventCreated(
        uint256 indexed eventId, 
        string eventName, 
        uint256 ethPrice,
        uint256 pyusdPrice,
        uint256 totalTickets,
        address indexed eventOwner
    );

    event TicketPurchased(
        address indexed buyer, 
        uint256 indexed eventId, 
        uint256 quantity, 
        uint256 totalPrice,
        string paymentMethod
    );

    event EventStatusUpdated(
        uint256 indexed eventId,
        bool isActive
    );

    event PriceUpdated(
        uint256 indexed eventId,
        uint256 newEthPrice,
        uint256 newPyusdPrice
    );

    constructor() ERC721("Event Ticket", "TKT") Ownable(msg.sender) {}

    function createEvent(
        string memory _eventName,
        uint256 _ethPrice,
        uint256 _pyusdPrice,
        uint256 _totalTickets,
        string memory _baseTokenURI
    ) external returns (uint256 eventId) {
        require(bytes(_eventName).length > 0, "Event name cannot be empty");
        require(_ethPrice > 0, "ETH price must be greater than 0");
        require(_pyusdPrice > 0, "PYUSD price must be greater than 0");
        require(_totalTickets > 0, "Total tickets must be greater than 0");
        require(bytes(_baseTokenURI).length > 0, "Base URI cannot be empty");

        eventId = _eventIds.current();
        _eventIds.increment();

        events[eventId] = EventDetails({
            name: _eventName,
            ethPrice: _ethPrice,
            pyusdPrice: _pyusdPrice,
            totalTickets: _totalTickets,
            remainingTickets: _totalTickets,
            baseTokenURI: _baseTokenURI,
            eventOwner: msg.sender,
            isActive: true
        });

        emit EventCreated(
            eventId, 
            _eventName, 
            _ethPrice, 
            _pyusdPrice,
            _totalTickets,
            msg.sender
        );

        return eventId;
    }

    function calculatePyusdPrice(uint256 _eventId, uint256 _quantity) public view returns (uint256) {
        EventDetails storage eventDetails = events[_eventId];
        uint256 basePrice = eventDetails.pyusdPrice * _quantity;
        uint256 discount = (basePrice * PYUSD_DISCOUNT) / 100;
        return basePrice - discount;
    }

    function checkPyusdAllowance(
    uint256 _eventId,
    uint256 _quantity,
    address _buyer
    ) public view returns (
    bool isApproved,
    uint256 currentAllowance,
    uint256 requiredAmount,
    uint256 buyerBalance
    ) {
    uint256 totalPrice = calculatePyusdPrice(_eventId, _quantity);
    uint256 allowance = PYUSD_TOKEN.allowance(_buyer, address(this));
    uint256 balance = PYUSD_TOKEN.balanceOf(_buyer);
    
    return (
        allowance >= totalPrice && balance >= totalPrice,
        allowance,
        totalPrice,
        balance
    );
   }

    function checkRequiredEth(uint256 _eventId, uint256 _quantity) public view returns (
    uint256 requiredAmount,
    uint256 ticketPriceInWei,
    uint256 remainingTickets,
    bool isEventActive
    ) {
    require(_eventId < _eventIds.current(), "Invalid event");
    EventDetails storage eventDetails = events[_eventId];
    
    return (
        eventDetails.ethPrice * _quantity,  
        eventDetails.ethPrice,              
        eventDetails.remainingTickets,
        eventDetails.isActive               
    );
    }


    
    function purchaseTicketWithEth(uint256 _eventId, uint256 _quantity) external payable {
        require(_eventId < _eventIds.current(), "Invalid event");
        EventDetails storage eventDetails = events[_eventId];
        
        require(eventDetails.isActive, "Event is not active");
        require(eventDetails.remainingTickets >= _quantity, "Not enough tickets available");
        require(_quantity > 0, "Must purchase at least one ticket");

        uint256 totalPrice = eventDetails.ethPrice * _quantity;
        require(msg.value >= totalPrice, "Insufficient ETH sent");

        // Process the purchase
        _processTicketPurchase(_eventId, _quantity, msg.sender);
        
        // Transfer ETH to event owner
        payable(eventDetails.eventOwner).transfer(totalPrice);
        
        // Refund excess ETH if any
        if (msg.value > totalPrice) {
            payable(msg.sender).transfer(msg.value - totalPrice);
        }

        emit TicketPurchased(msg.sender, _eventId, _quantity, totalPrice, "ETH");
    }


    function purchaseTicketWithPyusd(uint256 _eventId, uint256 _quantity) external {
        require(_eventId < _eventIds.current(), "Invalid event");
        EventDetails storage eventDetails = events[_eventId];
        
        require(eventDetails.isActive, "Event is not active");
        require(eventDetails.remainingTickets >= _quantity, "Not enough tickets available");
        require(_quantity > 0, "Must purchase at least one ticket");

        uint256 totalPrice = calculatePyusdPrice(_eventId, _quantity);

        // Check PYUSD balance
        uint256 buyerBalance = PYUSD_TOKEN.balanceOf(msg.sender);
        require(buyerBalance >= totalPrice, "Insufficient PYUSD balance");

        // Check allowance
        uint256 currentAllowance = PYUSD_TOKEN.allowance(msg.sender, address(this));
        require(currentAllowance >= totalPrice, "Insufficient PYUSD allowance");

        // Transfer PYUSD tokens
        bool transferSuccess = PYUSD_TOKEN.transferFrom(
            msg.sender, 
            eventDetails.eventOwner, 
            totalPrice
        );
        require(transferSuccess, "PYUSD transfer failed");

        _processTicketPurchase(_eventId, _quantity, msg.sender);

        emit TicketPurchased(msg.sender, _eventId, _quantity, totalPrice, "PYUSD");
    }

    function _processTicketPurchase(
        uint256 _eventId,
        uint256 _quantity,
        address _buyer
    ) internal {
        EventDetails storage eventDetails = events[_eventId];
        
        for (uint256 i = 0; i < _quantity; i++) {
            uint256 newTicketId = _tokenIds.current();
            _tokenIds.increment();

            _safeMint(_buyer, newTicketId);

            string memory tokenURI = string(
                abi.encodePacked(
                    eventDetails.baseTokenURI,
                    "/",
                    Strings.toString(newTicketId),
                    ".json"
                )
            );
            _setTokenURI(newTicketId, tokenURI);
        }
        
        eventDetails.remainingTickets -= _quantity;
        ticketsPurchased[_eventId][_buyer] += _quantity;
    }


    function getEventDetails(uint256 _eventId) 
        external 
        view 
        returns (
            string memory name,
            uint256 ethPrice,
            uint256 pyusdPrice,
            uint256 discountedPyusdPrice,
            uint256 totalTickets,
            uint256 remainingTickets,
            string memory baseTokenURI,
            address eventOwner,
            bool isActive
        )
    {
        require(_eventId < _eventIds.current(), "Invalid event");
        EventDetails memory eventDetails = events[_eventId];
        uint256 discountedPrice = (eventDetails.pyusdPrice * (100 - PYUSD_DISCOUNT)) / 100;
        
        return (
            eventDetails.name,
            eventDetails.ethPrice,
            eventDetails.pyusdPrice,
            discountedPrice,
            eventDetails.totalTickets,
            eventDetails.remainingTickets,
            eventDetails.baseTokenURI,
            eventDetails.eventOwner,
            eventDetails.isActive
        );
    }

    /**
     * Update ticket prices (only event owner)
     */
    function updateTicketPrices(
        uint256 _eventId, 
        uint256 _newEthPrice,
        uint256 _newPyusdPrice
    ) external {
        require(_eventId < _eventIds.current(), "Invalid event");
        EventDetails storage eventDetails = events[_eventId];
        require(msg.sender == eventDetails.eventOwner, "Only event owner can update price");
        require(_newEthPrice > 0, "ETH price must be greater than 0");
        require(_newPyusdPrice > 0, "PYUSD price must be greater than 0");

        eventDetails.ethPrice = _newEthPrice;
        eventDetails.pyusdPrice = _newPyusdPrice;
        emit PriceUpdated(_eventId, _newEthPrice, _newPyusdPrice);
    }

    function updateEventStatus(uint256 _eventId, bool _isActive) external {
        require(_eventId < _eventIds.current(), "Invalid event");
        EventDetails storage eventDetails = events[_eventId];
        require(msg.sender == eventDetails.eventOwner, "Only event owner can update status");

        eventDetails.isActive = _isActive;
        emit EventStatusUpdated(_eventId, _isActive);
    }

    function getTicketsOwned(uint256 _eventId, address _owner) external view returns (uint256) {
        return ticketsPurchased[_eventId][_owner];
    }

    function getRemainingTickets(uint256 _eventId) external view returns (uint256) {
        require(_eventId < _eventIds.current(), "Invalid event");
        return events[_eventId].remainingTickets;
    }
}