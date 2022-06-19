// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface IBCEMusic {
    //offer is a firm offer on one or more tokens of the same type
    struct OfferTerms {
        uint16 amount; //since we hard-code each token type to at most 500 copies, uint16 is enough
        uint256 totalPrice; 
        address seller;  
    }
    //We use double-linked list because we may need to delete an offer
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
        uint16 amountAndRevealed; //the top bit is revealed or not, the remaining 15 bits hold the amount (which only needs 9 bits anyway)
        address bidder;
        uint256 earnestMoney;
        bytes32 bidHash;
    }
    //since bids only live for one auction, uint32 is more than enough
    //for bid IDs and revealed bid IDs
    struct RevealedBid {
        uint32 bidId;
        uint32 nextRevealedBidId;
        uint256 totalPrice;
    }
    struct AuctionTerms {
        uint16 amount;
        address seller;
        uint256 reservePricePerUnit;
        uint256 biddingDeadline;
        uint256 revealingDeadline;
    }
    //Auction is also a double-linked list, and uint64 would be enough for auction IDs
    struct Auction {
        uint16 totalInPlayRevealedBidCount; //since revealed bids may be eliminated when they are outbidded, we need to maintain a separate counter for in-play ones. And this counter cannot exceed 501 anyway
        uint16 revealedAmount;
        uint32 firstRevealedBidId;
        uint32 revealedBidIdCounter;
        uint64 nextAuction;
        uint64 prevAuction;
        uint256 totalHeldBalance;
        AuctionTerms terms;
        Bid[] bids;
        mapping(uint32 => RevealedBid) revealedBids;
    }
    struct AuctionWinner {
        uint16 amount;
        uint32 bidId;
        uint256 pricePerUnit;
        uint256 actuallyPaid;
        address bidder;
    }
    struct OutstandingAuctions {
        uint16 totalAuctionAmount;
        uint48 totalCount; //I can't imagine there would be more than uint48 worth of outstanding auctions
                           //In fact, uint8 would probably be enough, but if we do multi-song in the same contract
                           //then we need to be somewhat conservative. Even then, uint48 would stretch the imagination.
        uint64 firstAuctionId;
        uint64 lastAuctionId;
        uint64 auctionIdCounter;
        mapping (uint64 => Auction) auctions;
        mapping (address => uint16) auctionAmountBySeller;
    }
    event AuctionCreated(uint256 tokenId, uint64 auctionId);
    event BidPlacedForAuction(uint256 tokenId, uint64 auctionId, uint32 bidId);
    event BidRevealedForAuction(uint256 tokenId, uint64 auctionId, uint32 bidId);
    event AuctionFinalized(uint256 tokenId, uint64 auctionId);

    //the returned value is auction ID
    function startAuction(uint256 tokenId, uint16 amount, uint256 reservePricePerUnit, uint256 biddingPeriodSeconds, uint256 revealingPeriodSeconds) external returns (uint64);
    //the returned value is bid ID
    //This is payable because the earnest money must be paid at this time
    function bidOnAuction(uint256 tokenId, uint64 auctionId, uint16 amount, bytes32 bidHash) external payable returns (uint32);
    //This is payable because the whole price must be fully paid at this time
    function revealBidOnAuction(uint256 tokenId, uint64 auctionId, uint32 bidId, uint256 totalPrice, bytes32 nonce) external payable;
    //Anyone can call finalizeAuction after the reveal period passes
    function finalizeAuction(uint256 tokenId, uint64 auctionId) external;

    function getAuctionById(uint256 tokenId, uint64 auctionId) external view returns (AuctionTerms memory);
    function getAllAuctionsOnToken(uint256 tokenId) external view returns (AuctionTerms[] memory);

    function claimWithdrawal() external;
}
