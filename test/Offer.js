const { expect } = require("chai");
const { ethers } = require("hardhat");
const util = require('node:util');

describe("Offer test", () => {
    it("Music offer and take", async () => {
        const [owner, offeree] = await ethers.getSigners();
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
        const ownership = await bceMusic.balanceOf(owner.address, 2);
        expect(ownership.toNumber() == 499);
        const offerTx = await bceMusic.offer(2, 10, 1000);
        const offerRes = await offerTx.wait();
        const offerCreatedEvent = offerRes.events.find(event => event.event === 'OfferCreated');
        expect(offerCreatedEvent.args.tokenId.toNumber() == 2 && offerCreatedEvent.args.offerId.toNumber() == 1);
        console.log(`\t\tOffer created, gas used=${offerRes.gasUsed.toNumber()}, offerId=${offerCreatedEvent.args.offerId}`);
        const acceptOfferTx = await bceMusic.connect(offeree).acceptOffer(2, offerCreatedEvent.args.offerId, {
            value: ethers.BigNumber.from(1200)
        });
        const acceptOfferRes = await acceptOfferTx.wait();
        const offerFilledEvent = acceptOfferRes.events.find(event => event.event === 'OfferFilled');
        expect(offerFilledEvent.args.tokenId.toNumber() == 2 && offerFilledEvent.args.offerId.toNumber() == 1);
        const newOwnership = await bceMusic.balanceOf(owner.address, 2);
        expect(newOwnership.toNumber() == 489);
        const offereeOwnership = await bceMusic.balanceOf(offeree.address, 2);
        expect(offereeOwnership.toNumber() == 10);
        for (const event of acceptOfferRes.events) {
            if (event.event === 'TransferSingle') {
                console.log(`\t\tOffer transfer: from ${event.args.from} to ${event.args.to}: ${event.args.value} tokens`);
            } else if (event.event === 'ClaimIncreased') {
                console.log(`\t\tClaim increase: ${event.args.claimant} got ${event.args.increaseAmount}`);
            }
        }
        console.log(`\t\tOffer filled, gas used=${acceptOfferRes.gasUsed.toNumber()}`);
        const claimTx = await bceMusic.connect(offeree).claimWithdrawal();
        const claimRes = await claimTx.wait();
        const withdrawalClaimedEvent = claimRes.events.find(event => event.event === 'ClaimWithdrawn');
        expect(withdrawalClaimedEvent.args.withdrawalAmount.toNumber() == 200);
        console.log(`\t\tExtra payment withdrawn, gas used=${claimRes.gasUsed.toNumber()}`);
    });
});