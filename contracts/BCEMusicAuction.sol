// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./IBCEMusic.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

library BCEMusicAuction {
    uint public constant AMOUNT_UPPER_LIMIT = 500;

    function startAuction(address seller, IBCEMusic.OutstandingAuctions storage auctions, uint amount, uint256 reservePricePerUnit, uint256 biddingPeriodSeconds, uint256 revealingPeriodSeconds) external returns (uint256) {
        require(amount > 0 && amount < AMOUNT_UPPER_LIMIT, "Invalid amount.");
        require(reservePricePerUnit > 0, "Invalid reserve price.");
      
        Counters.increment(auctions.auctionIdCounter);
        uint256 auctionId = Counters.current(auctions.auctionIdCounter);
        IBCEMusic.Auction storage auction = auctions.auctions[auctionId];
        auction.terms = IBCEMusic.AuctionTerms({
            seller: seller 
            , amount: amount
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
    function bidOnAuction(address seller, uint256 value, IBCEMusic.Auction storage auction, uint amount, bytes32 bidHash) external returns (uint256) {
        require(auction.terms.amount > 0, "Invalid auction.");
        require(amount > 0 && amount <= auction.terms.amount, "Invalid amount.");
        require(value >= auction.terms.reservePricePerUnit*amount*2, "Insufficient earnest money");
        require(block.timestamp <= auction.terms.biddingDeadline, "Bidding has closed.");

        auction.bids.push(IBCEMusic.Bid({
            bidder: seller
            , amount: amount
            , earnestMoney: value
            , bidHash: bidHash
            , revealed: false
        }));
        uint bidId = auction.bids.length-1;
        auction.totalHeldBalance += value;
        
        return bidId;
    }
    function _compareBids(IBCEMusic.Bid[] storage bids, IBCEMusic.RevealedBid storage a, IBCEMusic.RevealedBid storage b) private view returns (bool) {
        uint256 aPrice = a.totalPrice/bids[a.bidId].amount;
        uint256 bPrice = b.totalPrice/bids[b.bidId].amount;
        if (aPrice < bPrice) {
            return true;
        }
        if (aPrice == bPrice && a.bidId > b.bidId) {
            return true;
        }
        return false;
    }
    struct AddedRevealedBid {
        uint revealedBidId;
        uint cumAmountInFront;
    }
    function _addRevealedBid(IBCEMusic.Auction storage auction, uint bidId, uint256 totalPrice) private returns (AddedRevealedBid memory) {
        Counters.increment(auction.revealedBidIdCounter);
        uint revealedBidId = Counters.current(auction.revealedBidIdCounter);
        auction.revealedBids[revealedBidId] = IBCEMusic.RevealedBid({
            bidId: bidId 
            , totalPrice: totalPrice
            , nextRevealedBidId: 0
        });
        auction.revealedAmount += auction.bids[bidId].amount;
        auction.totalRevealedBidCount += 1;
        AddedRevealedBid memory ret = AddedRevealedBid({
            revealedBidId: revealedBidId
            , cumAmountInFront: 0
        });
        
        IBCEMusic.RevealedBid storage thisRevealedBid = auction.revealedBids[revealedBidId] ;

        if (auction.firstRevealedBidId == 0) {
            auction.firstRevealedBidId = revealedBidId;
            return ret;
        }
        if (_compareBids(auction.bids, auction.revealedBids[auction.firstRevealedBidId], thisRevealedBid)) {
            thisRevealedBid.nextRevealedBidId = auction.firstRevealedBidId;
            auction.firstRevealedBidId = revealedBidId;
            return ret;
        }
        uint prevId = auction.firstRevealedBidId;
        uint nextId = auction.revealedBids[prevId].nextRevealedBidId;
        while (true) {
            ret.cumAmountInFront += auction.bids[auction.revealedBids[prevId].bidId].amount;
            if (nextId == 0) {
                auction.revealedBids[prevId].nextRevealedBidId = revealedBidId;
                break;
            } else if (_compareBids(auction.bids, auction.revealedBids[nextId], thisRevealedBid)) {
                thisRevealedBid.nextRevealedBidId = nextId;
                auction.revealedBids[prevId].nextRevealedBidId = revealedBidId;
                break;
            } else {
                prevId = nextId;
                nextId = auction.revealedBids[prevId].nextRevealedBidId;
            }
        }
        return ret;
    }
    function _eliminateOutBiddedRevealedBids(IBCEMusic.Auction storage auction, AddedRevealedBid memory newlyAdded, mapping (address => uint256) storage withdrawalAllowances) private {
        if (auction.revealedAmount <= auction.terms.amount) {
            return;
        }
        uint currentId = newlyAdded.revealedBidId;
        uint nextId = auction.revealedBids[currentId].nextRevealedBidId;
        uint cumAmount = newlyAdded.cumAmountInFront;
        while (true) {
            if (cumAmount <= auction.terms.amount) {
                cumAmount += auction.bids[auction.revealedBids[currentId].bidId].amount;
                if (cumAmount > auction.terms.amount) {
                    auction.revealedBids[currentId].nextRevealedBidId = 0;
                }
                if (nextId == 0) {
                    break;
                }
                currentId = nextId;
                nextId = auction.revealedBids[currentId].nextRevealedBidId;
            } else {
                auction.revealedAmount -= auction.bids[auction.revealedBids[currentId].bidId].amount;
                auction.totalRevealedBidCount -= 1;
                auction.totalHeldBalance -= auction.revealedBids[currentId].totalPrice;
                withdrawalAllowances[auction.bids[auction.revealedBids[currentId].bidId].bidder] += auction.revealedBids[currentId].totalPrice;
                if (nextId == 0) {
                    break;
                }
                delete(auction.revealedBids[currentId]);
                currentId = nextId;
                nextId = auction.revealedBids[currentId].nextRevealedBidId;
            }
        }
    }

    function revealBidOnAuction(address bidder, uint256 value, IBCEMusic.Auction storage auction, uint bidId, uint256 totalPrice, bytes32 nonce, mapping (address => uint256) storage withdrawalAllowances) external {
        require(auction.terms.amount > 0, "Invalid auction.");
        require(bidId <= auction.bids.length, "Invalid bid id.");
        require(block.timestamp <= auction.terms.revealingDeadline, "Revealing has closed.");
        
        IBCEMusic.Bid storage bid = auction.bids[bidId];
        require(bidder == bid.bidder, "Not your bid.");
        require(!bid.revealed, "Duplicate revealing");
        require(totalPrice <= value+bid.earnestMoney, "Not enough money to reveal.");
        require(totalPrice >= bid.amount*auction.terms.reservePricePerUnit, "Cannot reveal an invalid price.");

        bytes memory toHash = abi.encodePacked(totalPrice, nonce);
        bytes32 theHash = keccak256(toHash);
        require(theHash == bid.bidHash, "Hash does not match.");

        AddedRevealedBid memory newlyAdded = _addRevealedBid(auction, bidId, totalPrice);

        bid.revealed = true;
        if (value+bid.earnestMoney > totalPrice) {
            withdrawalAllowances[bidder] += value+bid.earnestMoney-totalPrice;
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
    struct OneSend {
        address receiver;
        uint amount;
        uint256 value;
    }
    function _buildPotentialWinners(IBCEMusic.Auction storage auction) private returns (IBCEMusic.AuctionWinner[] memory) {
        IBCEMusic.AuctionWinner[] memory potentialWinners = new IBCEMusic.AuctionWinner[](auction.totalRevealedBidCount);
        if (auction.firstRevealedBidId > 0) {
            uint ii = 0;
            uint currentId = auction.firstRevealedBidId;
            IBCEMusic.RevealedBid storage r = auction.revealedBids[currentId];
            uint nextId = r.nextRevealedBidId;
            while (true) {
                potentialWinners[ii] = IBCEMusic.AuctionWinner({
                    bidder : auction.bids[r.bidId].bidder 
                    , bidId : r.bidId
                    , amount: auction.bids[r.bidId].amount
                    , pricePerUnit: r.totalPrice/auction.bids[r.bidId].amount
                    , actuallyPaid : r.totalPrice
                });
                ++ii;
                delete(auction.revealedBids[currentId]);
                if (nextId == 0) {
                    break;
                }
                currentId = auction.firstRevealedBidId;
                r = auction.revealedBids[currentId];
                nextId = r.nextRevealedBidId;
            }
            auction.firstRevealedBidId = 0;
        }
        return potentialWinners;
    }
    function _removeAuction(IBCEMusic.OutstandingAuctions storage auctions, uint256 auctionId, IBCEMusic.Auction storage auction) private returns (IBCEMusic.AuctionTerms memory) {
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
        OneSend[] sends;
        IBCEMusic.AuctionWinner[] winners;
        uint256 totalReceipt;
        IBCEMusic.AuctionTerms terms;
    }
    function finalizeAuction(IBCEMusic.OutstandingAuctions storage auctions, uint256 auctionId) external returns (AuctionResult memory) {
        IBCEMusic.Auction storage auction = auctions.auctions[auctionId];
        require(auction.terms.amount > 0, "Invalid auction.");
        require(block.timestamp > auction.terms.revealingDeadline, "Immature finalizing");

        if (auction.totalRevealedBidCount == 0) {
            uint256 totalReceipt = auction.totalHeldBalance;
            IBCEMusic.AuctionTerms memory terms = _removeAuction(auctions, auctionId, auction);
            return AuctionResult({
                sends: new OneSend[](0)
                , winners: new IBCEMusic.AuctionWinner[](0)
                , totalReceipt: totalReceipt
                , terms: terms
            });
        } else {
            IBCEMusic.AuctionWinner[] memory potentialWinners = _buildPotentialWinners(auction);
            uint winnerCount = 0;
            OneSend[] memory sends = new OneSend[](potentialWinners.length);
            uint cumAmount = 0;
            for (uint ii=0; ii<potentialWinners.length; ++ii) {
                if (ii+1 < potentialWinners.length) {
                    potentialWinners[ii].pricePerUnit = potentialWinners[ii+1].pricePerUnit;
                } else {
                    potentialWinners[ii].pricePerUnit = auction.terms.reservePricePerUnit;
                }
                if (cumAmount + potentialWinners[ii].amount >= auction.terms.amount) {
                    potentialWinners[ii].amount = auction.terms.amount-cumAmount;
                }
                for (uint jj=0; jj<winnerCount; ++ii) {
                    if (sends[jj].receiver == potentialWinners[ii].bidder) {
                        sends[jj].amount += potentialWinners[ii].amount;
                        sends[jj].value += potentialWinners[ii].actuallyPaid-potentialWinners[ii].pricePerUnit*potentialWinners[ii].amount;
                        break;
                    } else if (sends[jj].receiver == address(0)) {
                        sends[jj].receiver = potentialWinners[ii].bidder;
                        sends[jj].amount += potentialWinners[ii].amount;
                        sends[jj].value += potentialWinners[ii].actuallyPaid-potentialWinners[ii].pricePerUnit*potentialWinners[ii].amount;
                        break;
                    }
                }
                cumAmount += potentialWinners[ii].amount;
            }

            uint256 totalReceipt = auction.totalHeldBalance;
            IBCEMusic.AuctionTerms memory terms = _removeAuction(auctions, auctionId, auction);

            return AuctionResult({
                sends: sends
                , winners: potentialWinners
                , totalReceipt: totalReceipt
                , terms: terms
            });
        }
    }
    function getAuctionById(IBCEMusic.OutstandingAuctions storage auctions, uint256 auctionId) external view returns (IBCEMusic.AuctionTerms memory) {
        require (auctionId > 0, "Invalid auction id.");
        IBCEMusic.AuctionTerms memory theTermsCopy = auctions.auctions[auctionId].terms;
        return theTermsCopy;
    }
    function getAllAuctions(IBCEMusic.OutstandingAuctions storage auctions) external view returns (IBCEMusic.AuctionTerms[] memory) {
        if (auctions.totalCount == 0) {
            return new IBCEMusic.AuctionTerms[](0);
        }
        IBCEMusic.AuctionTerms[] memory theTerms = new IBCEMusic.AuctionTerms[](auctions.totalCount);
        uint256 id = auctions.firstAuctionId;
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