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
        uint256 aPrice = a.totalPrice/bids[a.id].amount;
        uint256 bPrice = b.totalPrice/bids[b.id].amount;
        if (aPrice < bPrice) {
            return true;
        }
        if (aPrice == bPrice && a.id > b.id) {
            return true;
        }
        return false;
    }
    function _compareBids2(IBCEMusic.Bid[] storage bids, IBCEMusic.RevealedBid storage a, uint256 pricePerUnit, uint id) private view returns (bool) {
        uint256 aPrice = a.totalPrice/bids[a.id].amount;
        if (aPrice < pricePerUnit) {
            return true;
        }
        if (aPrice == pricePerUnit && a.id > id) {
            return true;
        }
        return false;
    }
    function _addRevealedBids(IBCEMusic.Bid[] storage bids, IBCEMusic.RevealedBid[] storage revealedBids, uint bidId, uint256 totalPrice) private {
        revealedBids.push(IBCEMusic.RevealedBid({
            id: bidId 
            , totalPrice: totalPrice
        }));
        uint256 pricePerUnit = totalPrice/bids[bidId].amount;
        uint idx = revealedBids.length-1;
        while (idx > 1) {
            uint parent = (idx-1)/2;
            if (_compareBids2(bids, revealedBids[parent], pricePerUnit, bidId)) {
                revealedBids[idx].id = revealedBids[parent].id;
                revealedBids[idx].totalPrice = revealedBids[parent].totalPrice;
                revealedBids[parent].id = bidId;
                revealedBids[parent].totalPrice = totalPrice;
                idx = parent;
            } else {
                break;
            }
        }
    }
    struct OneRefund {
        address receiver;
        uint256 value;
    }
    function _swap(IBCEMusic.RevealedBid storage a, IBCEMusic.RevealedBid storage b) private {
        uint256 p = a.totalPrice;
        uint id = a.id;
        a.totalPrice = b.totalPrice;
        a.id = b.id;
        b.totalPrice = p;
        b.id = id;
    }
    function _rebuildRevealedBids(uint totalAmount, IBCEMusic.Bid[] storage bids, IBCEMusic.RevealedBid[] storage revealedBids) private returns (OneRefund[] memory) {
        //the revealed bids must already be in a heap
        if (revealedBids.length == 0) {
            //always add one for possible revealer refund
            return new OneRefund[](1);
        }
        uint cumAmount = 0;
        IBCEMusic.RevealedBid[] memory orderedBids = new IBCEMusic.RevealedBid[](revealedBids.length);
        uint ii = 0;
        bool breakNextTime = false;
        for (; ii<revealedBids.length; ++ii) {
            orderedBids[ii] = revealedBids[0];
            cumAmount += bids[revealedBids[0].id].amount;
            revealedBids[0].id = revealedBids[revealedBids.length-1-ii].id;
            revealedBids[0].totalPrice = revealedBids[revealedBids.length-1-ii].totalPrice;
            uint jj=0;
            while (true) {
                uint left = jj*2+1;
                uint right = left+1;
                if (right < revealedBids.length-1-ii) {
                    if (_compareBids(bids, revealedBids[left], revealedBids[right])) {
                        if (_compareBids(bids, revealedBids[jj], revealedBids[right])) {
                            _swap(revealedBids[jj], revealedBids[right]);
                            jj = right;
                        } else {
                            break;
                        }
                    } else {
                        if (_compareBids(bids, revealedBids[jj], revealedBids[left])) {
                            _swap(revealedBids[jj], revealedBids[left]);
                            jj = left;
                        } else {
                            break;
                        }
                    }
                } else if (left < revealedBids.length-1-ii) {
                    if (_compareBids(bids, revealedBids[jj], revealedBids[left])) {
                        _swap(revealedBids[jj], revealedBids[left]);
                        jj = left;
                    } else {
                        break;
                    }
                } else {
                    break;
                }
            }
            if (breakNextTime) {
                break;
            } else {
                if (cumAmount >= totalAmount) {
                    breakNextTime = true;
                }
            }
        }
        if (ii < revealedBids.length) {
            //always add one for possible revealer refund
            OneRefund[] memory ret = new OneRefund[](revealedBids.length-ii);
            for (uint jj=0; jj<ret.length-1; ++jj) {
                ret[jj].receiver = bids[revealedBids[jj].id].bidder;
                ret[jj].value = revealedBids[jj].totalPrice;
                revealedBids.pop();
            }
            for (uint jj=0; jj<=ii; ++jj) {
                revealedBids[jj] = orderedBids[jj];
            }
            return ret;
        } else {
            return new OneRefund[](1);
        }
    }

    function revealBidOnAuction(address bidder, uint256 value, IBCEMusic.Auction storage auction, uint bidId, uint256 totalPrice, bytes32 nonce) external returns (OneRefund[] memory) {
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

        _addRevealedBids(auction.bids, auction.revealedBids, bidId, totalPrice);

        bid.revealed = true;
        auction.totalHeldBalance += value;

        uint256 refund;
        unchecked {
            refund = value+bid.earnestMoney-totalPrice;
        }

        OneRefund[] memory refunds = _rebuildRevealedBids(auction.terms.amount, auction.bids, auction.revealedBids);
        refunds[refunds.length-1].receiver = bidder;
        refunds[refunds.length-1].value = refund;

        address[] memory receivers = new address[](refunds.length);
        uint256[] memory refundValues = new uint256[](refunds.length);
        for (uint ii=0; ii<refunds.length; ++ii) {
            if (refunds[ii].value > 0) {
                for (uint jj=0; jj<receivers.length; ++jj) {
                    if (receivers[jj] == address(0)) {
                        receivers[jj] = refunds[ii].receiver;
                        refundValues[jj] = refunds[ii].value;
                        break;
                    } else if (receivers[jj] == refunds[ii].receiver) {
                        refundValues[jj] += refunds[ii].value;
                        break;
                    }
                }
            }
        }
        uint ll = 0;
        for (; ll<receivers.length; ++ll) {
            if (receivers[ll] == address(0)) {
                break;
            }
        }
        OneRefund[] memory ret = new OneRefund[](ll);
        uint256 totalRefund;
        for (uint ii=0; ii<ll; ++ii) {
            ret[ii].receiver = receivers[ii];
            ret[ii].value = refundValues[ii];
            totalRefund += refundValues[ii];
        }
        auction.totalHeldBalance -= totalRefund;
        return ret;
    }
    struct OneSend {
        address receiver;
        uint amount;
        uint256 value;
    }
    function _buildPotentialWinners(IBCEMusic.Auction storage auction) private returns (IBCEMusic.AuctionWinner[] memory) {
        IBCEMusic.AuctionWinner[] memory potentialWinners = new IBCEMusic.AuctionWinner[](auction.revealedBids.length);
        uint totalAmount = 0;
        uint auctionAmount = auction.terms.amount;
        bool breakNextTime = false;
        for (uint ii=0; ii<potentialWinners.length; ++ii) {
            IBCEMusic.RevealedBid storage r = auction.revealedBids[0];
            potentialWinners[ii] = IBCEMusic.AuctionWinner({
                bidder : auction.bids[r.id].bidder 
                , bidId : r.id
                , amount: auction.bids[r.id].amount
                , pricePerUnit: auction.revealedBids[0].totalPrice/auction.bids[auction.revealedBids[0].id].amount
                , actuallyPaid : r.totalPrice
            });
            totalAmount += auction.bids[r.id].amount;
            auction.revealedBids[0].id = auction.revealedBids[potentialWinners.length-1-ii].id;
            auction.revealedBids[0].totalPrice = auction.revealedBids[potentialWinners.length-1-ii].totalPrice;
            uint jj=0;
            while (true) {
                uint left = jj*2+1;
                uint right = left+1;
                if (right < potentialWinners.length-1-ii) {
                    if (_compareBids(auction.bids, auction.revealedBids[left], auction.revealedBids[right])) {
                        if (_compareBids(auction.bids, auction.revealedBids[jj], auction.revealedBids[right])) {
                            _swap(auction.revealedBids[jj], auction.revealedBids[right]);
                            jj = right;
                        } else {
                            break;
                        }
                    } else {
                        if (_compareBids(auction.bids, auction.revealedBids[jj], auction.revealedBids[left])) {
                            _swap(auction.revealedBids[jj], auction.revealedBids[left]);
                            jj = left;
                        } else {
                            break;
                        }
                    }
                } else if (left < potentialWinners.length-1-ii) {
                    if (_compareBids(auction.bids, auction.revealedBids[jj], auction.revealedBids[left])) {
                        _swap(auction.revealedBids[jj], auction.revealedBids[left]);
                        jj = left;
                    } else {
                        break;
                    }
                } else {
                    break;
                }
            }
            if (breakNextTime) {
                break;
            } else {
                if (totalAmount >= auctionAmount) {
                    breakNextTime = true;
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