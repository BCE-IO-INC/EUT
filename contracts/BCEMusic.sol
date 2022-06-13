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
    uint public constant AMOUNT_UPPER_LIMIT = 500;

    uint public constant DIAMOND_TOKEN_ID = 1;
    uint public constant GOLDEN_TOKEN_ID = 2;

    bytes private constant EMPTY_BYTES = "";

    uint public constant OWNER_FEE_PERCENT_FOR_SECONDARY_MARKET = 5;

    mapping (uint => OutstandingOffers) private _outstandingOffers;

    constructor(string memory uri) ERC1155(uri) Ownable() ReentrancyGuard() {
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
        require(amount < AMOUNT_UPPER_LIMIT, "Invalid amount.");
        require(totalPrice > 0, "Invalid price.");

        uint balance = balanceOf(msg.sender, tokenId);
        OutstandingOffers storage offers = _outstandingOffers[tokenId];
        uint requiredAmount = amount+offers.offerAmountBySeller[msg.sender];
        if (balance < requiredAmount) {
            revert InsufficientNFT({
                    ownedAmount: balanceOf(msg.sender, tokenId), 
                    requiredAmount: requiredAmount
                });
        }
        
        Counters.increment(offers.offerIdCounter);
        uint256 offerId = Counters.current(offers.offerIdCounter);
        offers.offers[offerId] = Offer({
            terms: OfferTerms({
                seller: msg.sender 
                , amount: amount
                , totalPrice: totalPrice
            })
            , nextOffer: 0
            , prevOffer: offers.lastOfferId
        });
        if (offers.firstOfferId != 0) {
            offers.offers[offers.lastOfferId].nextOffer = offerId;
        } else {
            offers.firstOfferId = offerId;
        }
        offers.lastOfferId = offerId;
        unchecked {
            ++offers.totalCount;
            offers.totalOfferAmount += amount;
            offers.offerAmountBySeller[msg.sender] += amount;
        }
        emit OfferCreated(tokenId, offerId, offers.offers[offerId].terms);
    }

    function _removeOffer(OutstandingOffers storage outstandingOffers, Offer storage theOffer) private returns (OfferTerms memory) {
        if (theOffer.prevOffer == 0) {
            outstandingOffers.firstOfferId = theOffer.nextOffer;
            if (theOffer.nextOffer != 0) {
                outstandingOffers.offers[theOffer.nextOffer].prevOffer = 0;
            } else {
                outstandingOffers.lastOfferId = 0;
            }
        } else {
            outstandingOffers.offers[theOffer.prevOffer].nextOffer = theOffer.nextOffer;
            if (theOffer.nextOffer != 0) {
                outstandingOffers.offers[theOffer.nextOffer].prevOffer = theOffer.prevOffer;
            } else {
                outstandingOffers.lastOfferId = theOffer.prevOffer;
            }
        }
        OfferTerms memory theOfferTermsCopy = theOffer.terms;
        theOffer.terms.amount = 0;
        
        unchecked {
            --outstandingOffers.totalCount;
            outstandingOffers.totalOfferAmount -= theOfferTermsCopy.amount;
            outstandingOffers.offerAmountBySeller[theOfferTermsCopy.seller] -= theOfferTermsCopy.amount;
        }

        return theOfferTermsCopy;
    }

    function acceptOffer(uint tokenId, uint256 offerId) external payable override nonReentrant {
        require (tokenId == DIAMOND_TOKEN_ID || tokenId == GOLDEN_TOKEN_ID, "Invalid token id.");
        require (offerId > 0, "Invalid order id.");

        OutstandingOffers storage outstandingOffers = _outstandingOffers[tokenId];
        Offer storage theOffer = outstandingOffers.offers[offerId];   
        require (theOffer.terms.amount > 0, "Invalid offer.");     

        if (msg.value < theOffer.terms.totalPrice){
            revert InsufficientBalance({
                paid: msg.value,
                price: theOffer.terms.totalPrice
            });
        }

        OfferTerms memory theOfferTermsCopy = _removeOffer(outstandingOffers, theOffer);
        uint256 ownerFee = theOfferTermsCopy.totalPrice*OWNER_FEE_PERCENT_FOR_SECONDARY_MARKET/100;
        
        _safeTransferFrom(theOfferTermsCopy.seller, msg.sender, tokenId, theOfferTermsCopy.amount, EMPTY_BYTES);
        payable(theOfferTermsCopy.seller).transfer(theOfferTermsCopy.totalPrice-ownerFee);
        payable(owner()).transfer(ownerFee);
        if (msg.value > theOfferTermsCopy.totalPrice) {
            unchecked {
                //because of the condition, no need to check for underflow
                payable(msg.sender).transfer(msg.value-theOfferTermsCopy.totalPrice);
            }
        }
        emit OfferFilled(tokenId, offerId, theOfferTermsCopy);
    }

    function withdrawOffer(uint tokenId, uint256 offerId) external override {
        require (tokenId == DIAMOND_TOKEN_ID || tokenId == GOLDEN_TOKEN_ID, "Invalid token id.");
        require (offerId > 0, "Invalid order id.");

        OutstandingOffers storage outstandingOffers = _outstandingOffers[tokenId];
        Offer storage theOffer = outstandingOffers.offers[offerId]; 
        require (theOffer.terms.amount > 0, "Invalid offer.");
        require (msg.sender == theOffer.terms.seller, "Wrong seller");

        OfferTerms memory theOfferTermsCopy = _removeOffer(outstandingOffers, theOffer);

        emit OfferWithdrawn(tokenId, offerId, theOfferTermsCopy);
    }

    function getOutstandingOfferById(uint tokenId, uint256 offerId) external view override returns (OfferTerms memory) {
        require (tokenId == DIAMOND_TOKEN_ID || tokenId == GOLDEN_TOKEN_ID, "Invalid token id.");
        require (offerId > 0, "Invalid offer id.");
        OfferTerms memory theOfferTermsCopy = _outstandingOffers[tokenId].offers[offerId].terms;
        return theOfferTermsCopy;
    }
    function getAllOutstandingOffersOnToken(uint tokenId) external view override returns (OfferTerms[] memory) {
        require (tokenId == DIAMOND_TOKEN_ID || tokenId == GOLDEN_TOKEN_ID, "Invalid token id.");

        OutstandingOffers storage outstandingOffers = _outstandingOffers[tokenId];
        if (outstandingOffers.totalCount == 0) {
            return new OfferTerms[](0);
        }
        OfferTerms[] memory theOfferTerms = new OfferTerms[](outstandingOffers.totalCount);
        uint256 id = outstandingOffers.firstOfferId;
        uint outputIdx = 0;
        while (id != 0 && outputIdx < theOfferTerms.length) {
            Offer storage o = outstandingOffers.offers[id];
            theOfferTerms[outputIdx] = o.terms;
            unchecked {
                ++outputIdx;
            }
            id = o.nextOffer;
        }
        return theOfferTerms;
    }
}
