//SPDX-License-Identifier: Unlicensed

pragma solidity 0.8.19;

import "@thetrees1529/solutils/contracts/gamefi/Nft.sol";

contract Votes is AccessControl {

    struct NftInput {
        string uri;
        string name;
        string symbol;
    }

    struct VoteInput {
        uint nftIndex;
        uint count;
    }

    uint private _devFee;
    address private _devAddress;
    bool private _settled;
    uint private _referral;
    uint private _consolation;
    uint private _winningNftIndex;
    uint private _winningsPerNft;
    uint private _consolationPerNft;
    uint private _price;
    Nft[] private _nfts;

    constructor(uint newPrice, uint newReferral, uint newConsolation, uint newDevFee, address newDevAddress) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _devFee = newDevFee;
        _devAddress = newDevAddress;
        _consolation = newConsolation;
        _price = newPrice;
        _referral = newReferral;
    }

    function addNfts(NftInput[] memory newNfts) external onlyRole(DEFAULT_ADMIN_ROLE) {
        for(uint i; i < newNfts.length; i ++) {
            NftInput memory newNft = newNfts[i];
            Nft nft = new Nft(newNft.uri, newNft.name, newNft.symbol);
            nft.grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
            _nfts.push(nft);
        }
    }

    function getInfo() external view returns(bool settled, uint winningNftIndex, uint price, uint winningsPerNft, uint consolationPerNft, uint consolation, uint devFee, address devAddress, Nft[] memory nfts, uint[] memory totalSupplys) {
        {
            (
                settled,
                winningNftIndex,
                price,
                winningsPerNft,
                consolationPerNft,
                consolation,
                devFee,
                devAddress,
                nfts
            ) = (
                _settled,
                _winningNftIndex,
                _price,
                _winningsPerNft,
                _consolationPerNft,
                _consolation,
                _devFee,
                _devAddress,
                _nfts
            );
        }
        totalSupplys = new uint[](nfts.length);
        for(uint i; i < nfts.length; i ++) {
            totalSupplys[i] = nfts[i].totalSupply();
        }
    }

    function getInfoOf(address addr) external view returns(uint[] memory balances, uint pendingClaim) {
        balances = new uint[](_nfts.length);
        for(uint i; i < _nfts.length; i ++) {
            balances[i] = _nfts[i].balanceOf(addr);
        }
        if(_settled) {
            uint totalBalances;
            for(uint i; i < balances.length; i ++) {
                totalBalances += balances[i];
            }
            pendingClaim = balances[_winningNftIndex] * _winningsPerNft + totalBalances * _consolationPerNft;
        }
    }

    function vote(address referrer, VoteInput[] calldata inputs) external payable {
        require(!_settled, "Voting has already _settled.");
        uint funds = msg.value;
        for(uint i; i < inputs.length; i ++) {
            VoteInput calldata input = inputs[i];
            funds -= input.count * _price;
            _nfts[input.nftIndex].mint(msg.sender, input.count);
        }
        require(funds == 0, "Incorrect funds sent.");
        if(referrer != address(0)) {
            (bool success,) = referrer.call{value: (msg.value * _referral) / 100}("");
            require(success, "Referral transfer failed.");
        }
        (bool succ,) = _devAddress.call{value: (msg.value * _devFee) / 100}("");
        require(succ, "Dev fee transfer failed.");
    }

    function claim() external {
        require(_settled, "Voting has not _settled yet.");
        uint toPay;
        for(uint i; i < _nfts.length; i ++) {
            Nft nft = _nfts[i];
            uint[] memory tokenIds = nft.tokensOf(msg.sender);
            uint prizePerNft = _consolationPerNft + (i == _winningNftIndex ? _winningsPerNft : 0);
            toPay += tokenIds.length * prizePerNft;
            nft.burn(tokenIds);
        }
        (bool success,) = msg.sender.call{value: toPay}("");
        require(success, "Transfer failed.");
    }

    function settle(uint newWinningNftIndex) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(!_settled, "Voting has already _settled.");
        _settled = true;
        _winningNftIndex = newWinningNftIndex;
        uint consolation = address(this).balance * _consolation / 100;
        uint winnings = address(this).balance - consolation;

        Nft winningNft = _nfts[_winningNftIndex];
        _winningsPerNft = winnings / winningNft.totalSupply();

        uint totalSupplies;
        for(uint i; i < _nfts.length; i ++) {
            totalSupplies += _nfts[i].totalSupply();
        }

        _consolationPerNft = consolation / totalSupplies;
    }

    function emergencyWithdraw() external onlyRole(DEFAULT_ADMIN_ROLE) {
        (bool success,) = msg.sender.call{value: address(this).balance}("");
        require(success, "Transfer failed.");
    }

}
