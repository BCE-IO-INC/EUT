const Web3 = require('web3');
const fs = require('fs');
const contract = require("@truffle/contract");
const util = require('node:util');
const _ = require('lodash');

const settingsContractArtifact = JSON.parse(fs.readFileSync(__dirname+"/../build/contracts/BCEMusicSettings.json")); //produced by Truffle compile
const SettingsContract = contract(settingsContractArtifact);

const musicArtifact = JSON.parse(fs.readFileSync(__dirname+"/../build/contracts/BCEMusic.json")); //produced by Truffle compile
const MusicContract = contract(musicArtifact);

const provider = new Web3.providers.WebsocketProvider("ws://localhost:8545");
const web3 = new Web3(provider);
SettingsContract.setProvider(provider);
MusicContract.setProvider(provider);

var ownership = {};

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
                var id = event.returnValues.id;
                var from = event.returnValues.from;
                var to = event.returnValues.to;
                var value = event.returnValues.value;
                if (new web3.utils.BN(from).toNumber() !== 0) {
                    if (ownership[from] === undefined) {
                        ownership[from] = {};
                    }
                    if (ownership[from][id] === undefined) {
                        ownership[from][id] = 0;
                    }
                    ownership[from][id] -= parseInt(value);
                }
                if (ownership[to] === undefined) {
                    ownership[to] = {};
                }
                if (ownership[to][id] === undefined) {
                    ownership[to][id] = 0;
                }
                ownership[to][id] += parseInt(value);
                console.log(`${event.blockNumber}:`); 
                _.forEach(ownership, (v, k) => {
                    _.forEach(v, (v1, k1) => {
                        console.log(`\t${k} has ${v1} tokens of token ${k1} on address ${event.address}`);
                    });
                });
            }
        });
    
    musicContract.offer(2, 10, 1000, {from: accts[0]});
})();
