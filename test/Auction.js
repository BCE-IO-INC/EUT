const { expect } = require("chai");
const { ethers, network } = require("hardhat");
const util = require('node:util');

function asUint256ByteArray(x) {
    const n = ethers.BigNumber.from(x);
    const arr = ethers.utils.arrayify(n);
    var ret = new Uint8Array(32);
    for (var ii=0; ii<arr.length; ++ii) {
        ret[32-arr.length+ii] = arr[ii];
    }
    return ret;
}
function asByte32String(x) {
    return ethers.utils.hexlify(asUint256ByteArray(x));
}
function xorUint256ByteArray(x, y) {
    var ret = new Uint8Array(32);
    for (var ii=0; ii<32; ++ii) {
        ret[ii] = x[ii] ^ y[ii];
    }
    return ret;
}
function bidHash(price, nonce, address) {
    const y = [
        xorUint256ByteArray(
            asUint256ByteArray(price)
            , asUint256ByteArray(nonce)
        )
        , ethers.utils.arrayify(ethers.BigNumber.from(address))
    ];
    var arr = new Uint8Array(y[0].length+y[1].length);
    arr.set(y[0]);
    arr.set(y[1], y[0].length);
    return ethers.utils.keccak256(arr);
}

describe("Auction test", () => {
    it("Music auction (10 participants)", async () => {
        const signers = await ethers.getSigners();
        const owner = signers[0];

        const BCEMusicSettings = await ethers.getContractFactory("BCEMusicSettings");
        const bceMusicSettings = await BCEMusicSettings.deploy();
        const BCEMusicOffer = await ethers.getContractFactory("BCEMusicOffer");
        const bceMusicOffer = await BCEMusicOffer.deploy();
        const BCEMusicAuction = await ethers.getContractFactory("BCEMusicAuction");
        const bceMusicAuction = await BCEMusicAuction.deploy();
        const BCEMusic = await ethers.getContractFactory("BCEMusic", {
            libraries : {
                BCEMusicOffer: bceMusicOffer.address
                , BCEMusicAuction: bceMusicAuction.address
            }
        });
        const bceMusic = await BCEMusic.deploy("abc", bceMusicSettings.address);

        const auctionTx = await bceMusic.startAuction(2, 100, 0, 0, 10, 120, 120);
        const auctionRes = await auctionTx.wait();
        const auctionCreatedEvent = auctionRes.events.find(event => event.event === 'AuctionCreated');
        expect(auctionCreatedEvent.args.tokenId.toNumber() == 2 && auctionCreatedEvent.args.auctionId.toNumber() == 1);

        for (var ii=1; ii<=10; ++ii) {
            //person 1 bid for 2 tokens at price 20 (nonce 1)
            //person 2 bid for 4 tokens at price 19 (nonce 2)
            //person 3 bid for 6 tokens at price 18 (nonce 3)
            //...
            //person 10 bid for 20 tokens at price 11 (nonce 10)
            var placeBidTx = await bceMusic.connect(signers[ii]).bidOnAuction(
                2, 1, ii*2, bidHash(21-ii, ii, signers[ii].address)
                , {
                    value: ethers.BigNumber.from(ii*40)
                }
            );
            var placeBidRes = await placeBidTx.wait();
            var bidPlacedEvent = placeBidRes.events.find(event => event.event === 'BidPlacedForAuction');
            console.log(`\t\tBid id ${bidPlacedEvent.args.bidId} placed, gas used=${placeBidRes.gasUsed.toNumber()}`);
        }
        await network.provider.send("evm_increaseTime", [120]);
        await network.provider.send("evm_mine");
        for (var ii=1; ii<=10; ++ii) {
            var toSend = (21-ii)*ii*2-ii*40;
            if (toSend <= 0) {
                toSend = 10;
            }
            var revealBidTx = await bceMusic.connect(signers[ii]).revealBidOnAuction(
                2, 1, ii-1, 21-ii, asByte32String(ii)
                , {
                    value: ethers.BigNumber.from(toSend)
                }
            );
            var revealBidRes = await revealBidTx.wait();
            for (const event of revealBidRes.events) {
                if (event.event === 'ClaimIncreased') {
                    console.log(`\t\tClaim increase: ${event.args.claimant} got ${event.args.increaseAmount}`);
                }
            }
            var bidRevealedEvent = revealBidRes.events.find(event => event.event === 'BidRevealedForAuction');
            console.log(`\t\tBid id ${bidRevealedEvent.args.bidId} revealed, gas used=${revealBidRes.gasUsed.toNumber()}`);
        }
        await network.provider.send("evm_increaseTime", [120]);
        await network.provider.send("evm_mine");
        var finalizeTx = await bceMusic.finalizeAuction(2, 1);
        var finalizeRes = await finalizeTx.wait();
        for (const event of finalizeRes.events) {
            if (event.event === 'TransferSingle') {
                console.log(`\t\tAuction transfer: from ${event.args.from} to ${event.args.to}: ${event.args.value} tokens`);
            } else if (event.event === 'ClaimIncreased') {
                console.log(`\t\tClaim increase: ${event.args.claimant} got ${event.args.increaseAmount}`);
            }
        }
        var finalizeEvent = finalizeRes.events.find(event => event.event === 'AuctionFinalized');
        console.log(`\t\tAuction ${finalizeEvent.args.auctionId} finalized, gas used=${finalizeRes.gasUsed.toNumber()}`);
    });
    
    it("Music auction (pressure test)", async () => {
        const signers = await ethers.getSigners();
        const owner = signers[0];

        const BCEMusicSettings = await ethers.getContractFactory("BCEMusicSettings");
        const bceMusicSettings = await BCEMusicSettings.deploy();
        const BCEMusicOffer = await ethers.getContractFactory("BCEMusicOffer");
        const bceMusicOffer = await BCEMusicOffer.deploy();
        const BCEMusicAuction = await ethers.getContractFactory("BCEMusicAuction");
        const bceMusicAuction = await BCEMusicAuction.deploy();
        const BCEMusic = await ethers.getContractFactory("BCEMusic", {
            libraries : {
                BCEMusicOffer: bceMusicOffer.address
                , BCEMusicAuction: bceMusicAuction.address
            }
        });
        const bceMusic = await BCEMusic.deploy("abc", bceMusicSettings.address);

        const auctionTx = await bceMusic.startAuction(2, 499, 0, 0, 10, 3000, 3000);
        const auctionRes = await auctionTx.wait();
        const auctionCreatedEvent = auctionRes.events.find(event => event.event === 'AuctionCreated');
        expect(auctionCreatedEvent.args.tokenId.toNumber() == 2 && auctionCreatedEvent.args.auctionId.toNumber() == 1);

        for (var ii=0; ii<1000; ++ii) {
            //each person bids for 1 token at increasing price, with nonce=person number 
            var signerIdx = (ii%10)+1;
            var placeBidTx = await bceMusic.connect(signers[signerIdx]).bidOnAuction(
                2, 1, 1, bidHash(11+ii, signerIdx, signers[signerIdx].address)
                , {
                    value: ethers.BigNumber.from(20)
                }
            );
            var placeBidRes = await placeBidTx.wait();
            var bidPlacedEvent = placeBidRes.events.find(event => event.event === 'BidPlacedForAuction');
            console.log(`\t\tBid id ${bidPlacedEvent.args.bidId} placed, gas used=${placeBidRes.gasUsed.toNumber()}`);
        }
        await network.provider.send("evm_increaseTime", [3000]);
        await network.provider.send("evm_mine");
        for (var ii=0; ii<1000; ++ii) {
            var toSend = 11+ii-20;
            if (toSend <= 0) {
                toSend = 10;
            }
            var signerIdx = (ii%10)+1;
            var revealBidTx = await bceMusic.connect(signers[signerIdx]).revealBidOnAuction(
                2, 1, ii, 11+ii, asByte32String(signerIdx)
                , {
                    value: ethers.BigNumber.from(toSend)
                }
            );
            var revealBidRes = await revealBidTx.wait();
            for (const event of revealBidRes.events) {
                if (event.event === 'ClaimIncreased') {
                    console.log(`\t\tClaim increase: ${event.args.claimant} got ${event.args.increaseAmount}`);
                }
            }
            var bidRevealedEvent = revealBidRes.events.find(event => event.event === 'BidRevealedForAuction');
            console.log(`\t\tBid id ${bidRevealedEvent.args.bidId} revealed, gas used=${revealBidRes.gasUsed.toNumber()}`);
        }
        await network.provider.send("evm_increaseTime", [3000]);
        await network.provider.send("evm_mine");
        var finalizeTx = await bceMusic.finalizeAuction(2, 1);
        var finalizeRes = await finalizeTx.wait();
        for (const event of finalizeRes.events) {
            if (event.event === 'TransferSingle') {
                console.log(`\t\tAuction transfer: from ${event.args.from} to ${event.args.to}: ${event.args.value} tokens`);
            } else if (event.event === 'ClaimIncreased') {
                console.log(`\t\tClaim increase: ${event.args.claimant} got ${event.args.increaseAmount}`);
            }
        }
        var finalizeEvent = finalizeRes.events.find(event => event.event === 'AuctionFinalized');
        console.log(`\t\tAuction ${finalizeEvent.args.auctionId} finalized, gas used=${finalizeRes.gasUsed.toNumber()}`);
    });
    /*
    it("Music auction (medium pressure test)", async () => {
        const signers = await ethers.getSigners();
        const owner = signers[0];

        const BCEMusicSettings = await ethers.getContractFactory("BCEMusicSettings");
        const bceMusicSettings = await BCEMusicSettings.deploy();
        const BCEMusicOffer = await ethers.getContractFactory("BCEMusicOffer");
        const bceMusicOffer = await BCEMusicOffer.deploy();
        const BCEMusicAuction = await ethers.getContractFactory("BCEMusicAuction");
        const bceMusicAuction = await BCEMusicAuction.deploy();
        const BCEMusic = await ethers.getContractFactory("BCEMusic", {
            libraries : {
                BCEMusicOffer: bceMusicOffer.address
                , BCEMusicAuction: bceMusicAuction.address
            }
        });
        const bceMusic = await BCEMusic.deploy("abc", bceMusicSettings.address);

        const auctionTx = await bceMusic.startAuction(2, 100, 0, 0, 10, 3000, 3000);
        const auctionRes = await auctionTx.wait();
        const auctionCreatedEvent = auctionRes.events.find(event => event.event === 'AuctionCreated');
        expect(auctionCreatedEvent.args.tokenId.toNumber() == 2 && auctionCreatedEvent.args.auctionId.toNumber() == 1);

        for (var ii=0; ii<200; ++ii) {
            //each person bids for 1 token at increasing price, with nonce=person number 
            var signerIdx = (ii%10)+1;
            var placeBidTx = await bceMusic.connect(signers[signerIdx]).bidOnAuction(
                2, 1, 1, bidHash(11+ii, signerIdx, signers[signerIdx].address)
                , {
                    value: ethers.BigNumber.from(20)
                }
            );
            var placeBidRes = await placeBidTx.wait();
            var bidPlacedEvent = placeBidRes.events.find(event => event.event === 'BidPlacedForAuction');
            console.log(`\t\tBid id ${bidPlacedEvent.args.bidId} placed, gas used=${placeBidRes.gasUsed.toNumber()}`);
        }
        await network.provider.send("evm_increaseTime", [3000]);
        await network.provider.send("evm_mine");
        for (var ii=0; ii<200; ++ii) {
            var toSend = 11+ii-20;
            if (toSend <= 0) {
                toSend = 10;
            }
            var signerIdx = (ii%10)+1;
            var revealBidTx = await bceMusic.connect(signers[signerIdx]).revealBidOnAuction(
                2, 1, ii, 11+ii, asByte32String(signerIdx)
                , {
                    value: ethers.BigNumber.from(toSend)
                }
            );
            var revealBidRes = await revealBidTx.wait();
            for (const event of revealBidRes.events) {
                if (event.event === 'ClaimIncreased') {
                    console.log(`\t\tClaim increase: ${event.args.claimant} got ${event.args.increaseAmount}`);
                }
            }
            var bidRevealedEvent = revealBidRes.events.find(event => event.event === 'BidRevealedForAuction');
            console.log(`\t\tBid id ${bidRevealedEvent.args.bidId} revealed, gas used=${revealBidRes.gasUsed.toNumber()}`);
        }
        await network.provider.send("evm_increaseTime", [3000]);
        await network.provider.send("evm_mine");
        var finalizeTx = await bceMusic.finalizeAuction(2, 1);
        var finalizeRes = await finalizeTx.wait();
        for (const event of finalizeRes.events) {
            if (event.event === 'TransferSingle') {
                console.log(`\t\tAuction transfer: from ${event.args.from} to ${event.args.to}: ${event.args.value} tokens`);
            } else if (event.event === 'ClaimIncreased') {
                console.log(`\t\tClaim increase: ${event.args.claimant} got ${event.args.increaseAmount}`);
            }
        }
        var finalizeEvent = finalizeRes.events.find(event => event.event === 'AuctionFinalized');
        console.log(`\t\tAuction ${finalizeEvent.args.auctionId} finalized, gas used=${finalizeRes.gasUsed.toNumber()}`);
    });
    */
});
