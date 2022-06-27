const Web3 = require('web3');
const fs = require('fs');
const contract = require("@truffle/contract");
const util = require('node:util');

const settingsContractArtifact = JSON.parse(fs.readFileSync(__dirname+"/../build/contracts/BCEMusicSettings.json")); //produced by Truffle compile
const SettingsContract = contract(settingsContractArtifact);

const musicArtifact = JSON.parse(fs.readFileSync(__dirname+"/../build/contracts/BCEMusic.json")); //produced by Truffle compile
const MusicContract = contract(musicArtifact);

const provider = new Web3.providers.WebsocketProvider("ws://localhost:8545");
const web3 = new Web3(provider);
SettingsContract.setProvider(provider);
MusicContract.setProvider(provider);

(async () => {
    const settingsContract = await SettingsContract.deployed();
    const result = await settingsContract.ownerFeePercentForAuction();
    console.log(result.toNumber());

    const musicContract = await MusicContract.deployed();
    const auctions = await musicContract.getAllAuctionsOnToken(2);
    console.log(auctions);

    const lastBlockNumber = await web3.eth.getBlockNumber();
    const accts = await web3.eth.getAccounts();
    
    musicContract.contract.events.allEvents({
        fromBlock: 0
    })
        .on('data', (event) => {
            if (event.event === 'OfferCreated' && event.blockNumber > lastBlockNumber && event.returnValues.seller === accts[0]) {
                console.log(`withdrawing offer ${event.returnValues.offerId}`);
                musicContract.withdrawOffer(event.returnValues.tokenId, event.returnValues.offerId, {from: accts[0]});
            } else if (event.event === 'TransferSingle') {
                var from = event.returnValues.from;
                var to = event.returnValues.to;
                var value = event.returnValues.value;
                console.log(`${event.blockNumber} transfer ${value}`);
            }
        });
    
    musicContract.offer(2, 10, 1000, {from: accts[0]});
})();