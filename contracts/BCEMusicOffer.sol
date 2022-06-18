// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./IBCEMusic.sol";

library BCEMusicOffer {
    uint public constant AMOUNT_UPPER_LIMIT = 500;

    function offer(address seller, IBCEMusic.OutstandingOffers storage offers, uint16 amount, uint256 totalPrice) external returns (uint64) {
        require(amount > 0 && amount < AMOUNT_UPPER_LIMIT, "Invalid amount.");
        require(totalPrice > 0, "Invalid price.");
       
        //The logic simply inserts an offer into the double-linked list
        //and then update the overall statistics fields.
        ++offers.offerIdCounter;
        uint64 offerId = offers.offerIdCounter;
        offers.offers[offerId] = IBCEMusic.Offer({
            nextOffer: 0
            , prevOffer: offers.lastOfferId
            , terms: IBCEMusic.OfferTerms({
                amount: amount
                , totalPrice: totalPrice
                , seller: seller
            })
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
            offers.offerAmountBySeller[seller] += amount;
        }

        return offerId;
    }

    //This function removes an offer from the outstanding offers list
    //, and then returns a copy of the original term. 
    function _removeOffer(IBCEMusic.OutstandingOffers storage outstandingOffers, uint64 offerId, IBCEMusic.Offer storage theOffer) private returns (IBCEMusic.OfferTerms memory) {
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
        IBCEMusic.OfferTerms memory theOfferTermsCopy = theOffer.terms;
        theOffer.terms.amount = 0;
        
        unchecked {
            --outstandingOffers.totalCount;
            outstandingOffers.totalOfferAmount -= theOfferTermsCopy.amount;
            outstandingOffers.offerAmountBySeller[theOfferTermsCopy.seller] -= theOfferTermsCopy.amount;
        }

        delete(outstandingOffers.offers[offerId]);

        return theOfferTermsCopy;
    }

    //Because the actual transfers of the token happen outside of this
    //library function call, acceptOffer looks quite like withdrawOffer.
    function acceptOffer(uint256 value, IBCEMusic.OutstandingOffers storage outstandingOffers, uint64 offerId) external returns (IBCEMusic.OfferTerms memory) {
        require (offerId > 0, "Invalid order id.");

        IBCEMusic.Offer storage theOffer = outstandingOffers.offers[offerId];   
        require (theOffer.terms.amount > 0, "Invalid offer.");     

        require (value >= theOffer.terms.totalPrice, "Insufficient money.");

        return _removeOffer(outstandingOffers, offerId, theOffer);
    }

    function withdrawOffer(address seller, IBCEMusic.OutstandingOffers storage outstandingOffers, uint64 offerId) external returns (IBCEMusic.OfferTerms memory) {
        require (offerId > 0, "Invalid order id.");

        IBCEMusic.Offer storage theOffer = outstandingOffers.offers[offerId]; 
        require (theOffer.terms.amount > 0, "Invalid offer.");
        require (seller == theOffer.terms.seller, "Wrong seller");

        return _removeOffer(outstandingOffers, offerId, theOffer);
    }

    function getOutstandingOfferById(IBCEMusic.OutstandingOffers storage outstandingOffers, uint64 offerId) external view returns (IBCEMusic.OfferTerms memory) {
        require (offerId > 0, "Invalid offer id.");
        IBCEMusic.OfferTerms memory theOfferTermsCopy = outstandingOffers.offers[offerId].terms;
        return theOfferTermsCopy;
    }
    function getAllOutstandingOffers(IBCEMusic.OutstandingOffers storage outstandingOffers) external view returns (IBCEMusic.OfferTerms[] memory) {
        if (outstandingOffers.totalCount == 0) {
            return new IBCEMusic.OfferTerms[](0);
        }
        IBCEMusic.OfferTerms[] memory theOfferTerms = new IBCEMusic.OfferTerms[](outstandingOffers.totalCount);
        uint64 id = outstandingOffers.firstOfferId;
        uint outputIdx = 0;
        while (id != 0 && outputIdx < theOfferTerms.length) {
            IBCEMusic.Offer storage o = outstandingOffers.offers[id];
            theOfferTerms[outputIdx] = o.terms;
            unchecked {
                ++outputIdx;
            }
            id = o.nextOffer;
        }
        return theOfferTerms;
    }
}