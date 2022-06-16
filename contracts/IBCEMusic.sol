// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/Counters.sol";

interface IBCEMusic {
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

    event OfferCreated(uint tokenId, uint256 offerId);
    event OfferFilled(uint tokenId, uint256 offerId);
    event OfferWithdrawn(uint tokenId, uint256 offerId);

    function airDropInitialOwner(address receiver, uint tokenId, uint amount) external;
    function offer(uint tokenId, uint amount, uint256 totalPrice) external returns (uint256);
    function acceptOffer(uint tokenId, uint256 offerId) external payable;
    function withdrawOffer(uint tokenId, uint256 offerId) external;
    function getOutstandingOfferById(uint tokenId, uint256 offerId) external view returns (OfferTerms memory);
    function getAllOutstandingOffersOnToken(uint tokenId) external view returns (OfferTerms[] memory);

    struct Bid {
        address bidder;
        uint amount;
        uint256 earnestMoney;
        bytes32 bidHash;
        bool revealed;
    }
    struct RevealedBid {
        uint256 id;
        uint256 totalPrice;
    }
    struct AuctionTerms {
        address seller;
        uint amount;
        uint256 reservePricePerUnit;
        uint256 biddingDeadline;
        uint256 revealingDeadline;
    }
    struct Auction {
        AuctionTerms terms;
        Bid[] bids;
        RevealedBid[] revealedBids;
        uint revealedAmount;
        uint256 nextAuction;
        uint256 prevAuction;
        uint256 totalHeldBalance;
    }
    struct AuctionWinner {
        address bidder;
        uint bidId;
        uint amount;
        uint256 pricePerUnit;
        uint256 actuallyPaid;
    }
    struct OutstandingAuctions {
        uint256 firstAuctionId;
        uint256 lastAuctionId;
        uint totalCount;
        Counters.Counter auctionIdCounter;
        mapping (uint256 => Auction) auctions;
        uint totalAuctionAmount;
        mapping (address => uint) auctionAmountBySeller;
    }
    event AuctionCreated(uint tokenId, uint256 id);
    event BidPlacedForAuction(uint tokenId, uint256 auctionId, uint256 bidId);
    event BidRevealedForAuction(uint tokenId, uint256 auctionId, uint256 bidId);
    event AuctionFinalized(uint tokenId, uint256 auctionId);

    function startAuction(uint tokenId, uint amount, uint256 reservePricePerUnit, uint256 biddingPeriodSeconds, uint256 revealingPeriodSeconds) external returns (uint256);
    function bidOnAuction(uint tokenId, uint256 auctionId, uint amount, bytes32 bidHash) external payable returns (uint256);
    function revealBidOnAuction(uint tokenId, uint256 auctionId, uint bidId, uint256 totalPrice, bytes32 nonce) external payable;
    function finalizeAuction(uint tokenId, uint256 auctionId) external;

    function getAuctionById(uint tokenId, uint256 auctionId) external view returns (AuctionTerms memory);
    function getAllAuctionsOnToken(uint tokenId) external view returns (AuctionTerms[] memory);
}
