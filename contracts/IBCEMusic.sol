// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/Counters.sol";

interface IBCEMusic {
    error InsufficientNFT(uint ownedAmount, uint requiredAmount);
    error InsufficientBalance(uint paid, uint price);

    struct OfferTerms {
        address seller;
        uint amount;
        uint256 totalPrice;
    }
    struct Offer {
        OfferTerms terms;
        uint256 nextOffer; //this is a linked-list kind of structure
        uint256 prevOffer;
    }
    struct OutstandingOffers {
        uint256 firstOfferId;
        uint256 lastOfferId;
        uint totalCount;
        Counters.Counter offerIdCounter;
        mapping (uint256 => Offer) offers;
        uint totalOfferAmount;
        mapping (address => uint) offerAmountBySeller;
    }

    event OfferCreated(uint tokenId, uint256 offerId, OfferTerms offerTerms);
    event OfferFilled(uint tokenId, uint256 offerId, OfferTerms offerTerms);
    event OfferWithdrawn(uint tokenId, uint256 offerId, OfferTerms offerTerms);

    function airDropInitialOwner(address receiver, uint tokenId, uint amount) external;
    function offer(uint tokenId, uint amount, uint256 totalPrice) external;
    function acceptOffer(uint tokenId, uint256 offerId) external payable;
    function withdrawOffer(uint tokenId, uint256 offerId) external;
    function getOutstandingOfferById(uint tokenId, uint256 offerId) external view returns (OfferTerms memory);
    function getAllOutstandingOffersOnToken(uint tokenId) external view returns (OfferTerms[] memory);

    struct Bid {
        address bidder;
        uint amount;
        uint256 earnestMoney;
        uint256 bidHash;
    }
    struct RevealedBid {
        uint256 id;
        uint256 pricePerUnit;
    }
    struct AuctionTerms {
        uint tokenId;
        uint amount;
        uint256 reservePricePerUnit;
        address seller;
        uint256 biddingDeadline;
        uint256 revealDeadline;
    }
    struct Auction {
        AuctionTerms terms;
        Bid[] bids;
        RevealedBid[] revealedBids;
        uint256 nextAuction;
    }
    struct AuctionWinner {
        address bidder;
        uint amount;
        uint256 totalPayment;
    }
    event AuctionCreated(uint256 id, AuctionTerms auctionTerms);
    event BidPlacedForAuction(uint256 auctionId, uint256 bidId, Bid bid);
    event BidRevealedForAuction(uint256 auctionId, uint256 bidId, Bid bid, RevealedBid revealedBid);
    event AuctionCompleted(uint256 auctionId, AuctionTerms auctionTerms, AuctionWinner[] winners);
}
