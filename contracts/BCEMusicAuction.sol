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
    function bidOnAuction(address seller, uint256 value, uint bidLimit, IBCEMusic.Auction storage auction, uint amount, bytes32 bidHash) external returns (uint256) {
        require(auction.terms.amount > 0, "Invalid auction.");
        require(amount > 0 && amount <= auction.terms.amount, "Invalid amount.");
        require(value >= auction.terms.reservePricePerUnit*amount*2, "Insufficient earnest money");
        require(block.timestamp <= auction.terms.biddingDeadline, "Bidding has closed.");
        require(auction.bids.length < bidLimit, "Too many bids.");

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
    function revealBidOnAuction(address bidder, uint256 value, IBCEMusic.Auction storage auction, uint bidId, uint256 totalPrice, bytes32 nonce) external returns (uint256) {
        require(auction.terms.amount > 0, "Invalid auction.");
        require(bidId <= auction.bids.length, "Invalid bid id.");
        require(block.timestamp <= auction.terms.revealingDeadline, "Revealing has closed.");
        
        IBCEMusic.Bid storage bid = auction.bids[bidId];
        require(bidder == bid.bidder, "Not your bid.");
        require(!bid.revealed, "Duplicate revealing");
        require(totalPrice <= value+bid.earnestMoney, "Not enough money to reveal.");

        bytes memory toHash = abi.encodePacked(totalPrice, nonce);
        bytes32 theHash = keccak256(toHash);
        require(theHash == bid.bidHash, "Hash does not match.");

        auction.revealedBids.push(IBCEMusic.RevealedBid({
            id: bidId 
            , totalPrice: totalPrice
        }));
        bid.revealed = true;
        auction.totalHeldBalance += value;

        uint256 refund;
        unchecked {
            refund = value+bid.earnestMoney-totalPrice;
            if (refund > 0) {
                auction.totalHeldBalance -= refund;
            }
        }
        return refund;
    }
    struct OneSend {
        address receiver;
        uint amount;
        uint256 value;
    }
    function _buildFinalBids(IBCEMusic.Auction storage auction) private view returns (uint256[] memory) {
        uint256[] memory finalBids = new uint256[](auction.revealedBids.length);
        for (uint ii=0; ii<finalBids.length; ++ii) {
            IBCEMusic.RevealedBid storage b = auction.revealedBids[ii];
            finalBids[ii] = (b.totalPrice/auction.bids[b.id].amount)*1000+(200-ii);
            uint jj = ii;
            while (jj > 0) {
                uint upper = (jj-1)/2;
                if (finalBids[jj] > finalBids[upper]) {
                    uint t = finalBids[upper];
                    finalBids[upper] = finalBids[jj];
                    finalBids[jj] = t;
                }
                jj = upper;
            }
        }
        return finalBids;
    }
    function _buildPotentialWinners(IBCEMusic.Auction storage auction, uint256[] memory finalBids) private view returns (IBCEMusic.AuctionWinner[] memory) {
        IBCEMusic.AuctionWinner[] memory potentialWinners = new IBCEMusic.AuctionWinner[](auction.revealedBids.length);
        uint totalAmount = 0;
        uint auctionAmount = auction.terms.amount;
        bool breakNextTime = false;
        for (uint ii=0; ii<potentialWinners.length; ++ii) {
            IBCEMusic.RevealedBid storage r = auction.revealedBids[finalBids[200-((uint) (finalBids[0]%1000))]];
            potentialWinners[ii] = IBCEMusic.AuctionWinner({
                bidder : auction.bids[r.id].bidder 
                , amount: auction.bids[r.id].amount
                , pricePerUnit: finalBids[0]/1000
                , actuallyPaid : r.totalPrice
            });
            if (breakNextTime) {
                break;
            }
            totalAmount += auction.bids[r.id].amount;
            if (totalAmount >= auctionAmount) {
                breakNextTime = true;
            }
            finalBids[0] = finalBids[potentialWinners.length-1-ii];
            uint jj=0;
            while (true) {
                uint left = jj*2+1;
                uint right = left+1;
                if (right < potentialWinners.length-1-ii) {
                    if (finalBids[left] > finalBids[right]) {
                        if (finalBids[jj] < finalBids[left]) {
                            uint t = finalBids[jj];
                            finalBids[jj] = finalBids[left];
                            finalBids[left] = t;
                            jj = left;
                        } else {
                            break;
                        }
                    } else {
                        if (finalBids[jj] < finalBids[right]) {
                            uint t = finalBids[jj];
                            finalBids[jj] = finalBids[right];
                            finalBids[right] = t;
                            jj = right;
                        } else {
                            break;
                        }
                    }
                } else if (left < potentialWinners.length-1-ii) {
                    if (finalBids[jj] < finalBids[left]) {
                        uint t = finalBids[jj];
                        finalBids[jj] = finalBids[left];
                        finalBids[left] = t;
                        jj = left;
                    } else {
                        break;
                    }
                } else {
                    break;
                }
            }
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

        if (auction.revealedBids.length == 0) {
            uint256 totalReceipt = auction.totalHeldBalance;
            IBCEMusic.AuctionTerms memory terms = _removeAuction(auctions, auctionId, auction);
            return AuctionResult({
                sends: new OneSend[](0)
                , winners: new IBCEMusic.AuctionWinner[](0)
                , totalReceipt: totalReceipt
                , terms: terms
            });
        } else {
            uint256[] memory finalBids = _buildFinalBids(auction);
            IBCEMusic.AuctionWinner[] memory potentialWinners = _buildPotentialWinners(auction, finalBids);
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