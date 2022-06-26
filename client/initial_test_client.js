const Web3 = require('web3');
const fs = require('fs');
const contract = require("@truffle/contract");

const settingsContractArtifact = JSON.parse(fs.readFileSync(__dirname+"/../build/contracts/BCEMusicSettings.json")); //produced by Truffle compile
const SettingsContract = contract(settingsContractArtifact);

const musicArtifact = JSON.parse(fs.readFileSync(__dirname+"/../build/contracts/BCEMusic.json")); //produced by Truffle compile
const MusicContract = contract(musicArtifact);

const provider = new Web3.providers.HttpProvider("http://localhost:8545");
SettingsContract.setProvider(provider);
MusicContract.setProvider(provider);

(async () => {
    const settingsContract = await SettingsContract.deployed();
    const result = await settingsContract.ownerFeePercentForAuction();
    console.log(result.toNumber());

    const musicContract = await MusicContract.deployed();
    const auctions = await musicContract.getAllAuctionsOnToken(2);
    console.log(auctions);
})();