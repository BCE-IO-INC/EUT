// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./IBCEMusic.sol";

contract BCEMusic is ERC1155, Ownable, ReentrancyGuard, IBCEMusic {

    uint public constant DIAMOND_TOKEN_AMOUNT = 1;
    uint public constant GOLDEN_TOKEN_AMOUNT = 499;

    uint public constant DIAMOND_TOKEN_ID = 1;
    uint public constant GOLDEN_TOKEN_ID = 2;

    bytes private constant EMPTY_BYTES = "";

    uint public constant OWNER_FEE_PERCENT_FOR_SECONDARY_MARKET = 5;

    mapping (uint256 => Offer) private _offers;
    uint256 private _firstOffer;
    Counters.Counter private _offerIdCounter;

    constructor(string memory uri) ERC1155(uri) Ownable() ReentrancyGuard() {
        _firstOffer = 0;
        Counters.reset(_offerIdCounter);
        _mint(msg.sender, DIAMOND_TOKEN_ID, DIAMOND_TOKEN_AMOUNT, EMPTY_BYTES);
        _mint(msg.sender, GOLDEN_TOKEN_ID, GOLDEN_TOKEN_AMOUNT, EMPTY_BYTES);
    }

    function airDropInitialOwner(address receiver, uint tokenId, uint amount) external override onlyOwner {
        if (balanceOf(msg.sender, tokenId) < amount){
            revert InsufficientNFT({
                    ownedAmount: balanceOf(msg.sender, tokenId), 
                    requiredAmount: amount
                });
        }
        safeTransferFrom(msg.sender, receiver, tokenId, amount, "");
    }

    function offer(uint tokenId, uint amount, uint256 totalPrice) external override {
        require((tokenId == DIAMOND_TOKEN_ID || tokenId == GOLDEN_TOKEN_ID), "Invalid token id.");
        require(amount > 0, "Invalid amount.");
        require(totalPrice > 0, "Invalid price.");
        uint balance = balanceOf(msg.sender, tokenId);
        if (balance < amount) {
            revert InsufficientNFT({
                    ownedAmount: balanceOf(msg.sender, tokenId), 
                    requiredAmount: amount
                });
        }
        uint256 outstandingOffers = 0;
        uint256 lastOffer = 0;
        if (_firstOffer != 0) {
            uint256 currentId = _firstOffer;
            while (currentId != 0) {
                Offer storage currentOffer = _offers[currentId];
                if (currentOffer.tokenId == tokenId && currentOffer.seller == msg.sender) {
                    unchecked {
                        //since the total outstanding offers can never exceed to fixed token supply
                        //there cannot be overflow
                        outstandingOffers += currentOffer.amount;
                    }
                }
                lastOffer = currentId;
                currentId = currentOffer.nextOffer;
            }
        }
        if (balance < amount+outstandingOffers) {
            revert InsufficientNFT({
                    ownedAmount: balanceOf(msg.sender, tokenId), 
                    requiredAmount: amount
                });
        }

        Counters.increment(_offerIdCounter);
        uint256 offerId = Counters.current(_offerIdCounter);
        _offers[offerId] = Offer(
            tokenId, amount, totalPrice, msg.sender, 0, lastOffer
        );
        if (_firstOffer == 0) {
            _firstOffer = offerId;
        }
        if (lastOffer != 0) {
            _offers[lastOffer].nextOffer = offerId;
        }
        emit OfferCreated(offerId, _offers[offerId]);
    }

    function _removeOffer(Offer storage theOffer) private returns (Offer memory) {
        if (theOffer.prevOffer == 0) {
            _firstOffer = theOffer.nextOffer;
            if (theOffer.nextOffer != 0) {
                _offers[theOffer.nextOffer].prevOffer = 0;
            }
        } else {
            _offers[theOffer.prevOffer].nextOffer = theOffer.nextOffer;
            if (theOffer.nextOffer != 0) {
                _offers[theOffer.nextOffer].prevOffer = theOffer.prevOffer;
            }
        }
        Offer memory theOfferCopy = theOffer;
        theOffer.tokenId = 0;

        return theOfferCopy;
    }

    function acceptOffer(uint256 offerId) external payable override nonReentrant {
        require (offerId > 0, "Invalid order id.");
        Offer storage theOffer = _offers[offerId]; 
        require (theOffer.tokenId > 0, "Invalid order id.");
        require (theOffer.tokenId == DIAMOND_TOKEN_ID || theOffer.tokenId == GOLDEN_TOKEN_ID, "Invalid token id.");

        uint256 ownerFee = theOffer.totalPrice*OWNER_FEE_PERCENT_FOR_SECONDARY_MARKET/100;
        if (msg.value < theOffer.totalPrice+ownerFee){
            revert InsufficientBalance({
                paid: msg.value,
                price: theOffer.totalPrice
            });
        }

        Offer memory theOfferCopy = _removeOffer(theOffer);

        _safeTransferFrom(theOfferCopy.seller, msg.sender, theOfferCopy.tokenId, theOfferCopy.amount, EMPTY_BYTES);
        payable(theOfferCopy.seller).transfer(theOfferCopy.totalPrice);
        payable(owner()).transfer(ownerFee);
        if (msg.value > theOfferCopy.totalPrice+ownerFee) {
            unchecked {
                //because of the condition, no need to check for underflow
                payable(msg.sender).transfer(msg.value-theOfferCopy.totalPrice-ownerFee);
            }
        }
        emit OfferFilled(offerId, theOfferCopy);
    }

    function withdrawOffer(uint256 offerId) external override {
        require (offerId > 0, "Invalid order id.");
        Offer storage theOffer = _offers[offerId]; 
        require (theOffer.tokenId > 0, "Invalid order id.");
        require (theOffer.tokenId == DIAMOND_TOKEN_ID || theOffer.tokenId == GOLDEN_TOKEN_ID, "Invalid token id.");
        require (msg.sender == theOffer.seller, "Wrong seller");

        Offer memory theOfferCopy = _removeOffer(theOffer);

        emit OfferWithdrawn(offerId, theOfferCopy);
    }
}
