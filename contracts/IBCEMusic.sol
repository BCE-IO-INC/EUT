// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/Counters.sol";

interface IBCEMusic {
    //offer is a firm offer on one or more tokens of the same type
    struct OfferTerms {
        uint16 amount; //since we hard-code each token type to at most 500 copies, uint16 is enough
        uint256 totalPrice; 
        address seller;  
    }
    //We use double linked list because we may need to delete an offer
    //from the list using only its id for lookup.
    struct Offer {
        uint64 nextOffer; //this is a linked-list kind of structure
        uint64 prevOffer; //uint64 would be enough for all the offer history
        OfferTerms terms;
    }
    struct OutstandingOffers {
        uint16 totalOfferAmount;
        uint48 totalCount;  //the first two sizes are designed to be packed together
        uint64 firstOfferId;
        uint64 lastOfferId;
        uint64 offerIdCounter;
        mapping (uint64 => Offer) offers;
        mapping (address => uint16) offerAmountBySeller;
    }

    //In our current design, token id can only be 1 or 2, but it doesn't hurt to 
    //use the full uint256 since ERC1155 gives us uint256 for token ID anyway
    event OfferCreated(uint256 tokenId, uint64 offerId);
    event OfferFilled(uint256 tokenId, uint64 offerId);
    event OfferWithdrawn(uint256 tokenId, uint64 offerId);

    function airDropInitialOwner(address receiver, uint256 tokenId, uint16 amount) external;
    //the return value is offer ID
    function offer(uint256 tokenId, uint16 amount, uint256 totalPrice) external returns (uint64);
    function acceptOffer(uint256 tokenId, uint64 offerId) external payable;
    function withdrawOffer(uint256 tokenId, uint64 offerId) external;
    function getOutstandingOfferById(uint256 tokenId, uint64 offerId) external view returns (OfferTerms memory);
    function getAllOutstandingOffersOnToken(uint256 tokenId) external view returns (OfferTerms[] memory);

    struct Bid {
        address bidder;
        uint amount;
        uint256 earnestMoney;
        bytes32 bidHash;
        bool revealed;
    }
    struct RevealedBid {
        uint256 bidId;
        uint256 totalPrice;
        uint nextRevealedBidId;
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
        mapping(uint => RevealedBid) revealedBids;
        uint firstRevealedBidId;
        Counters.Counter revealedBidIdCounter;
        uint totalRevealedBidCount;
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

    function claimWithdrawal() external;
}
