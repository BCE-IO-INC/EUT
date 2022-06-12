// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface IBCEMusic {
    error InsufficientNFT(uint ownedAmount, uint requiredAmount);
    error InsufficientBalance(uint paid, uint price);

    struct Offer {
        uint tokenId;
        uint amount;
        uint256 totalPrice;
        address seller;
        uint256 nextOffer; //this is a linked-list kind of structure
        uint256 prevOffer;
    }

    event OfferCreated(uint256 offerId, Offer offer);
    event OfferFilled(uint256 offerId, Offer offer);
    event OfferWithdrawn(uint256 offerId, Offer offer);

    function airDropInitialOwner(address receiver, uint tokenId, uint amount) external;
    function offer(uint tokenId, uint amount, uint256 totalPrice) external;
    function acceptOffer(uint256 offerId) external payable;
    function withdrawOffer(uint256 offerId) external;
    function getOutstandingOfferById(uint256 offerId) external view returns (Offer memory);
    function getAllOutstandingOffers() external view returns (Offer[] memory);

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
