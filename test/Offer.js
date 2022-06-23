const { expect } = require("chai");
const { ethers } = require("hardhat");
describe("Offer test", () => {
    it("Settings deploy", async () => {
        const [owner] = await ethers.getSigners();
        const BCEMusicSettings = await ethers.getContractFactory("BCEMusicSettings");
        const bceMusicSettings = await BCEMusicSettings.deploy();
        const pct = await bceMusicSettings.ownerFeePercentForAuction();
        expect(pct == 10);
    });
    it("Music deploy", async () => {
        const [owner] = await ethers.getSigners();
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
    });
});