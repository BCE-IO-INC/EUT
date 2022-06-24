// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./IBCEMusic.sol";
import "hardhat/console.sol";

library BCEMusicAuction {
    uint public constant AMOUNT_UPPER_LIMIT = 500;

    //This function simply adds an auction to the double-linked list and returns its ID
    function startAuction(address seller, IBCEMusic.OutstandingAuctions storage auctions, uint16 amount, uint256 reservePricePerUnit, uint256 biddingPeriodSeconds, uint256 revealingPeriodSeconds) external returns (uint64) {
        require(amount > 0 && amount < AMOUNT_UPPER_LIMIT, "Invalid amount.");
        require(reservePricePerUnit > 0, "Invalid reserve price.");
      
        ++auctions.auctionIdCounter;
        uint64 auctionId = auctions.auctionIdCounter;
        IBCEMusic.Auction storage auction = auctions.auctions[auctionId];
        auction.terms = IBCEMusic.AuctionTerms({
            amount: amount
            , seller: seller 
            , reservePricePerUnit: reservePricePerUnit
            , biddingDeadline: block.timestamp+biddingPeriodSeconds
            , revealingDeadline: block.timestamp+biddingPeriodSeconds+revealingPeriodSeconds
        });
        auction.prevAuction = auctions.lastAuctionId;
        if (auctions.firstAuctionId != 0) {
            auctions.auctions[auctions.lastAuctionId].nextAuction = auctionId;
        } else {
            auctions.firstAuctionId = auctionId;
        }
        auctions.lastAuctionId = auctionId;
        unchecked {
            ++auctions.totalCount;
            auctions.totalAuctionAmount += amount;
            auctions.auctionAmountBySeller[seller] += amount;
        }

        return auctionId;
    }
    //This function adds bid to the array in the auction and returns its it
    function bidOnAuction(address seller, uint256 value, IBCEMusic.Auction storage auction, uint16 amount, bytes32 bidHash) external returns (uint32) {
        require(auction.terms.amount > 0, "Invalid auction.");
        require(amount > 0 && amount <= auction.terms.amount, "Invalid amount.");
        require(value >= auction.terms.reservePricePerUnit*amount*2, "Insufficient earnest money");
        require(block.timestamp <= auction.terms.biddingDeadline, "Bidding has closed.");

        auction.bids.push(IBCEMusic.Bid({
            amountAndRevealed: amount
            , bidder: seller
            , earnestMoney: value
            , bidHash: bidHash
        }));
        uint32 bidId = (uint32) (auction.bids.length-1);
        auction.totalHeldBalance += value;
        
        return bidId;
    }
    //An revealed bid is smaller if either (1) its per-unit price is lower or
    //(2) its per-unit price is the same as the other one, but its bid id is
    //higher (i.e. it is later)
    function _compareBids(IBCEMusic.RevealedBid storage a, IBCEMusic.RevealedBid storage b) private view returns (bool) {
        if (a.pricePerUnit < b.pricePerUnit) {
            return true;
        }
        if (a.pricePerUnit == b.pricePerUnit && a.bidId > b.bidId) {
            return true;
        }
        return false;
    }
    struct AddedRevealedBid {
        uint32 revealedBidId;
        uint16 cumAmountInFront;
    }
    //This function adds revealed bid to the single-linked list and updates statistics
    //The returned value also includes cumulative amount of all revealed bids that are
    //higher than the newly added one
    function _addRevealedBid(IBCEMusic.Auction storage auction, uint32 bidId, uint256 pricePerUnit) private returns (AddedRevealedBid memory) {
        ++auction.revealedBidIdCounter;
        uint32 revealedBidId = auction.revealedBidIdCounter;
        auction.revealedBids[revealedBidId] = IBCEMusic.RevealedBid({
            bidId: bidId 
            , nextRevealedBidId: 0
            , pricePerUnit: pricePerUnit
        });
        auction.revealedAmount += (auction.bids[bidId].amountAndRevealed & 0x7f);
        auction.totalInPlayRevealedBidCount += 1;
        AddedRevealedBid memory ret = AddedRevealedBid({
            revealedBidId: revealedBidId
            , cumAmountInFront: 0
        });
        
        IBCEMusic.RevealedBid storage thisRevealedBid = auction.revealedBids[revealedBidId] ;

        if (auction.firstRevealedBidId == 0) {
            auction.firstRevealedBidId = revealedBidId;
            return ret;
        }
        if (_compareBids(auction.revealedBids[auction.firstRevealedBidId], thisRevealedBid)) {
            thisRevealedBid.nextRevealedBidId = auction.firstRevealedBidId;
            auction.firstRevealedBidId = revealedBidId;
            return ret;
        }
        uint32 prevId = auction.firstRevealedBidId;
        uint32 nextId = auction.revealedBids[prevId].nextRevealedBidId;
        while (true) {
            ret.cumAmountInFront += (auction.bids[auction.revealedBids[prevId].bidId].amountAndRevealed & 0x7f);
            if (nextId == 0) {
                auction.revealedBids[prevId].nextRevealedBidId = revealedBidId;
                break;
            } else if (_compareBids(auction.revealedBids[nextId], thisRevealedBid)) {
                thisRevealedBid.nextRevealedBidId = nextId;
                auction.revealedBids[prevId].nextRevealedBidId = revealedBidId;
                break;
            } else {
                prevId = nextId;
                nextId = auction.revealedBids[prevId].nextRevealedBidId;
            }
        }
        //console.log("inserted %s %s", ret.revealedBidId, ret.cumAmountInFront);
        //console.log("the info %s %s", auction.revealedBids[ret.revealedBidId].bidId, auction.revealedBids[ret.revealedBidId].pricePerUnit);
        return ret;
    }

    event ClaimIncreased(address claimant, uint256 increaseAmount);

    //This function starts from the newly added revealed bid and eliminates
    //all out-bidded revealed bids (except at most one, to provide a reference
    //price for the next higher one)
    function _eliminateOutBiddedRevealedBids(IBCEMusic.Auction storage auction, AddedRevealedBid memory newlyAdded, mapping (address => uint256) storage withdrawalAllowances) private {
        if (auction.revealedAmount <= auction.terms.amount) {
            return;
        }
        uint32 currentId = newlyAdded.revealedBidId;
        uint32 nextId = auction.revealedBids[currentId].nextRevealedBidId;
        uint16 cumAmount = newlyAdded.cumAmountInFront;
        while (true) {
            //console.log("Checking %s %s %s", currentId, nextId, cumAmount);
            if (cumAmount <= auction.terms.amount) {
                cumAmount += (auction.bids[auction.revealedBids[currentId].bidId].amountAndRevealed & 0x7f);
                if (cumAmount > auction.terms.amount) {
                    auction.revealedBids[currentId].nextRevealedBidId = 0;
                }
                if (nextId == 0) {
                    break;
                }
                currentId = nextId;
                nextId = auction.revealedBids[currentId].nextRevealedBidId;
            } else {
                auction.revealedAmount -= (auction.bids[auction.revealedBids[currentId].bidId].amountAndRevealed & 0x7f);
                auction.totalInPlayRevealedBidCount -= 1;
                uint256 totalPrice = auction.revealedBids[currentId].pricePerUnit*(auction.bids[auction.revealedBids[currentId].bidId].amountAndRevealed & 0x7f);
                auction.totalHeldBalance -= totalPrice;
                withdrawalAllowances[auction.bids[auction.revealedBids[currentId].bidId].bidder] += totalPrice;
                emit ClaimIncreased(auction.bids[auction.revealedBids[currentId].bidId].bidder, totalPrice);
                delete(auction.revealedBids[currentId]);
                if (nextId == 0) {
                    break;
                }
                currentId = nextId;
                nextId = auction.revealedBids[currentId].nextRevealedBidId;
            }
        }
    }

    //This function calls the two helper functions to first place the newly 
    //revealed bid, then eliminate the out-bidded ones
    function revealBidOnAuction(address bidder, uint256 value, IBCEMusic.Auction storage auction, uint32 bidId, uint256 pricePerUnit, bytes12 nonce, mapping (address => uint256) storage withdrawalAllowances) external {
        require(auction.terms.amount > 0, "Invalid auction.");
        require(bidId <= auction.bids.length, "Invalid bid id.");
        require(block.timestamp > auction.terms.biddingDeadline, "Bidding has not yet closed.");
        require(block.timestamp <= auction.terms.revealingDeadline, "Revealing has closed.");
        
        IBCEMusic.Bid storage bid = auction.bids[bidId];
        require(bidder == bid.bidder, "Not your bid.");
        require((bid.amountAndRevealed & 0x80) == 0, "Duplicate revealing");
        require(pricePerUnit >= auction.terms.reservePricePerUnit, "Cannot reveal an invalid price.");
        uint256 totalPrice = pricePerUnit*(bid.amountAndRevealed & 0x7f);
        require(totalPrice <= value+bid.earnestMoney, "Not enough money to reveal.");

        bytes memory toHash = abi.encodePacked(pricePerUnit, nonce, bidder); //because all three are fixed length types, encodePacked would be safe
        bytes32 theHash = keccak256(toHash);
        require(theHash == bid.bidHash, "Hash does not match.");

        AddedRevealedBid memory newlyAdded = _addRevealedBid(auction, bidId, pricePerUnit);

        bid.amountAndRevealed = (bid.amountAndRevealed | 0x80);
        if (value+bid.earnestMoney > totalPrice) {
            withdrawalAllowances[bidder] += value+bid.earnestMoney-totalPrice;
            emit ClaimIncreased(bidder, value+bid.earnestMoney-totalPrice);
            if (totalPrice < bid.earnestMoney) {
                auction.totalHeldBalance -= bid.earnestMoney-totalPrice;
            } else {
                auction.totalHeldBalance += totalPrice-bid.earnestMoney;
            }
        } else {
            auction.totalHeldBalance += value;
        }

        _eliminateOutBiddedRevealedBids(auction, newlyAdded, withdrawalAllowances);
    }
    //This function build an array of all potentional winners from the 
    //currently kept linked-list of revealed bids, and it deletes all
    //the revealed bids since they are no longer needed
    function _buildPotentialWinners(IBCEMusic.Auction storage auction) private returns (IBCEMusic.AuctionWinner[] memory) {
        IBCEMusic.AuctionWinner[] memory potentialWinners = new IBCEMusic.AuctionWinner[](auction.totalInPlayRevealedBidCount);
        if (auction.firstRevealedBidId > 0) {
            uint32 ii = 0;
            uint32 currentId = auction.firstRevealedBidId;
            IBCEMusic.RevealedBid storage r = auction.revealedBids[currentId];
            uint32 nextId = r.nextRevealedBidId;
            while (true) {
                potentialWinners[ii] = IBCEMusic.AuctionWinner({
                    amount: (auction.bids[r.bidId].amountAndRevealed & 0x7f)
                    , bidId : r.bidId
                    , bidder : auction.bids[r.bidId].bidder
                    , pricePerUnit: r.pricePerUnit
                    , refund: 0
                });
                ++ii;
                delete(auction.revealedBids[currentId]);
                if (nextId == 0) {
                    break;
                }
                currentId = nextId;
                r = auction.revealedBids[currentId];
                nextId = r.nextRevealedBidId;
            }
            auction.firstRevealedBidId = 0;
        }
        return potentialWinners;
    }
    //This function removes an auction from the double-linked list
    function _removeAuction(IBCEMusic.OutstandingAuctions storage auctions, uint64 auctionId, IBCEMusic.Auction storage auction) private returns (IBCEMusic.AuctionTerms memory) {
        if (auction.prevAuction == 0) {
            auctions.firstAuctionId = auction.nextAuction;
            if (auction.nextAuction != 0) {
                auctions.auctions[auction.nextAuction].prevAuction = 0;
            } else {
                auctions.lastAuctionId = 0;
            }
        } else {
            auctions.auctions[auction.prevAuction].nextAuction = auction.nextAuction;
            if (auction.nextAuction != 0) {
                auctions.auctions[auction.nextAuction].prevAuction = auction.prevAuction;
            } else {
                auctions.lastAuctionId = auction.prevAuction;
            }
        }
        
        unchecked {
            --auctions.totalCount;
            auctions.totalAuctionAmount -= auction.terms.amount;
            auctions.auctionAmountBySeller[auction.terms.seller] -= auction.terms.amount;
        }

        IBCEMusic.AuctionTerms memory terms = auction.terms;
        delete(auctions.auctions[auctionId]);

        return terms;
    }
    struct AuctionResult {
        IBCEMusic.AuctionWinner[] winners;
        uint256 totalReceipt;
        IBCEMusic.AuctionTerms terms;
    }
    //This function calls the helper functions to prepare a winner's list 
    //(deleting all revealed bids on the way), and then deletes the auction
    //(but keeping a copy of the terms first). It then allocates the amounts
    //among the winners and calculates refunds.

    function finalizeAuction(IBCEMusic.OutstandingAuctions storage auctions, uint64 auctionId) external returns (AuctionResult memory) {
        IBCEMusic.Auction storage auction = auctions.auctions[auctionId];
        require(auction.terms.amount > 0, "Invalid auction.");
        require(block.timestamp > auction.terms.revealingDeadline, "Immature finalizing");

        if (auction.totalInPlayRevealedBidCount == 0) {
            uint256 totalReceipt = auction.totalHeldBalance;
            IBCEMusic.AuctionTerms memory terms = _removeAuction(auctions, auctionId, auction);
            return AuctionResult({
                winners: new IBCEMusic.AuctionWinner[](0)
                , totalReceipt: totalReceipt
                , terms: terms
            });
        } else {
            IBCEMusic.AuctionWinner[] memory potentialWinners = _buildPotentialWinners(auction);
            uint16 cumAmount = 0;
            for (uint ii=0; ii<potentialWinners.length; ++ii) {
                uint256 originalPricePerUnit = potentialWinners[ii].pricePerUnit;
                if (ii+1 < potentialWinners.length) {
                    potentialWinners[ii].pricePerUnit = potentialWinners[ii+1].pricePerUnit;
                } else {
                    potentialWinners[ii].pricePerUnit = auction.terms.reservePricePerUnit;
                }
                if (cumAmount + potentialWinners[ii].amount >= auction.terms.amount) {
                    potentialWinners[ii].amount = auction.terms.amount-cumAmount;
                }
                potentialWinners[ii].refund = potentialWinners[ii].amount*(originalPricePerUnit-potentialWinners[ii].pricePerUnit);
                cumAmount += potentialWinners[ii].amount;
            }

            uint256 totalReceipt = auction.totalHeldBalance;
            IBCEMusic.AuctionTerms memory terms = _removeAuction(auctions, auctionId, auction);

            return AuctionResult({
                winners: potentialWinners
                , totalReceipt: totalReceipt
                , terms: terms
            });
        }
    }
    function getAuctionById(IBCEMusic.OutstandingAuctions storage auctions, uint64 auctionId) external view returns (IBCEMusic.AuctionTerms memory) {
        require (auctionId > 0, "Invalid auction id.");
        IBCEMusic.AuctionTerms memory theTermsCopy = auctions.auctions[auctionId].terms;
        return theTermsCopy;
    }
    function getAllAuctions(IBCEMusic.OutstandingAuctions storage auctions) external view returns (IBCEMusic.AuctionTerms[] memory) {
        if (auctions.totalCount == 0) {
            return new IBCEMusic.AuctionTerms[](0);
        }
        IBCEMusic.AuctionTerms[] memory theTerms = new IBCEMusic.AuctionTerms[](auctions.totalCount);
        uint64 id = auctions.firstAuctionId;
        uint outputIdx = 0;
        while (id != 0 && outputIdx < theTerms.length) {
            IBCEMusic.Auction storage o = auctions.auctions[id];
            theTerms[outputIdx] = o.terms;
            unchecked {
                ++outputIdx;
            }
            id = o.nextAuction;
        }
        return theTerms;
    }
}