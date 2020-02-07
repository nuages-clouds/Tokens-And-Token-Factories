//============================================================
//
//  Digital Art ERC721 Token Implementation
// 
//      Art provenance --- show a clear line of ownership for
//      a work of art from the artist to the current owner.
// 
//      Artist : originator of the art work.
//      Owner : current owner of the artwork.
// 
//      Only one owner of an artwork at a time.
//      Artist can create new works of art.
//
//      BCDV1011 --- Design Patterns for Blockchain
//
//============================================================

pragma solidity ^0.5.2;

contract ERC721 {
    event Transfer(
        address indexed from,
        address indexed to,
        uint256 indexed tokenId
    );
    event Approval(
        address indexed owner,
        address indexed approved,
        uint256 indexed tokenId
    );
    event ApprovalForAll(
        address indexed owner,
        address indexed operator,
        bool approved
    );

    function balanceOf(address owner) public view returns (uint256 balance);
    
    function ownerOf(uint256 tokenId) public view returns (address owner);

    function approve(address to, uint256 tokenId) public;
    
    function getApproved(uint256 tokenId)
        public
        view
        returns (address operator);

    function setApprovalForAll(address operator, bool _approved) public;
    
    function isApprovedForAll(address owner, address operator)
        public
        view
        returns (bool);

    function transferFrom(address from, address to, uint256 tokenId) public;
    
    function safeTransferFrom(address from, address to, uint256 tokenId) public;

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) public;
}

contract DigitalArt is ERC721 {
    string private _name;
    string private _symbol;
    Art[] public arts;
    uint256 private pendingArtCount;
    mapping(uint256 => address) private _tokenOwner;
    mapping(address => uint256) private _ownedTokensCount;
    mapping(uint256 => address) private _tokenApprovals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;
    mapping(uint256 => ArtTxn[]) private artTxns;
    uint256 public index;
    
    struct Art {
        uint256 id;
        string title;
        string description;
        uint256 price;
        string date;
        string artistName;
        address payable artist;
        address payable owner;
        uint256 status;
        uint256 hashIPFS;
    }
    struct ArtTxn {
        uint256 id;
        uint256 price;
        address seller;
        address buyer;
        uint256 txnDate;
        uint256 status;
    }
    
    event LogArtSold(
        uint256 _tokenId,
        string _title,
        string _artistName,
        uint256 _price,
        address _artist,
        address _current_owner,
        address _buyer
    );
    
    event LogArtTokenCreate(
        uint256 _tokenId,
        string _title,
        string _category,
        string _artistName,
        uint256 _price,
        address _artist,
        address _current_owner
    );
    
    event LogArtResell(uint256 _tokenId, uint256 _status, uint256 _price);
    
    constructor(string memory name, string memory symbol) public {
        _name = name;
        _symbol = symbol;
    }
    
    function name() external view returns (string memory) {
        return _name;
    }
    
    function symbol() external view returns (string memory) {
        return _symbol;
    }
    
    //===============================================================
    //
    //  Create the token representing the artwork
    //
    //===============================================================
    function createTokenAndSellArt(
        string memory _title,
        string memory _description,
        string memory _date,
        string memory _artistName,
        uint256 _price,
        uint256 _hashIPFS
    ) public {
        require(bytes(_title).length > 0, "The title cannot be empty");
        require(bytes(_date).length > 0, "The Date cannot be empty");
        require(bytes(_description).length > 0, "The Description cannot be empty");
        require(_price > 0, "The price cannot be empty");
        require(_hashIPFS > 0, "The hashIPFS cannot be empty");
        Art memory _art = Art({
            id: index,
            title: _title,
            description: _description,
            price: _price,
            date: _date,
            artistName: _artistName,
            artist: msg.sender,
            owner: msg.sender,
            status: 1,
            hashIPFS: _hashIPFS
        });
        uint256 tokenId = arts.push(_art) - 1;
        _mint(msg.sender, tokenId);
        emit LogArtTokenCreate(
            tokenId,
            _title,
            _date,
            _artistName,
            _price,
            msg.sender,
            msg.sender
        );
        index++;
        pendingArtCount++;
    }

    function buyArt(uint256 _tokenId) public payable {
        (uint256 _id, string memory _title, , uint256 _price, uint256 _status, , string memory _artistName, address _artist, address payable _current_owner, ) = findArt(
            _tokenId
        );
        require(_current_owner != address(0));
        require(msg.sender != address(0));
        
        // buyer and seller cannot be the same
        require(msg.sender != _current_owner);
        
        // price must be met or exceeded
        require(msg.value >= _price);
        
        require(arts[_tokenId].owner != address(0));
        //===================================================================
        //
        //  Transfer ownership of art
        //
        //===================================================================
        _transfer(_current_owner, msg.sender, _tokenId);
        
        // being nice and returning extra payment above asking price
        if (msg.value > _price) msg.sender.transfer(msg.value - _price);
        
        // make a payment
        _current_owner.transfer(_price);
        
        arts[_tokenId].owner = msg.sender;
        arts[_tokenId].status = 0;
        ArtTxn memory _artTxn = ArtTxn({
            id: _id,
            price: _price,
            seller: _current_owner,
            buyer: msg.sender,
            txnDate: now,
            status: _status
        });
        artTxns[_id].push(_artTxn);
        pendingArtCount--;

        emit LogArtSold(
            _tokenId,
            _title,
            _artistName,
            _price,
            _artist,
            _current_owner,
            msg.sender
        );
    }
    
    //===================================================================
    //
    //  An artwork can change ownership via reselling.
    //  Artwork (token) must be actually owned by the account address.
    //
    //===================================================================
    function resellArt(uint256 _tokenId, uint256 _price) public payable {
        require(msg.sender != address(0));
        require(isOwnerOf(_tokenId, msg.sender));
        arts[_tokenId].status = 1;
        arts[_tokenId].price = _price;
        pendingArtCount++;
        emit LogArtResell(_tokenId, 1, _price);
    }
    
    //===================================================================
    //
    //  Return information on artwork corresponding to a token ID
    //
    //====================================================================
    function findArt(uint256 _tokenId)
        public
        view
        returns (
            uint256,
            string memory,
            string memory,
            uint256,
            uint256 status,
            string memory,
            string memory,
            address,
            address payable,
            uint256 
        )
    {
        Art memory art = arts[_tokenId];
        return (
            art.id,
            art.title,
            art.description,
            art.price,
            art.status,
            art.date,
            art.artistName,
            art.artist,
            art.owner,
            art.hashIPFS
        );
    }

    //===================================================================
    //
    //  Returns token ID, Artist, Current Owner, and Status of all
    //  artworks (tokens) that have been created. Status tracks whether
    //  an artwork is currently for sale or has been sold and is
    //  not on the market.
    //
    //====================================================================
    function findAllArt()
        public
        view
        returns (
            uint256[] memory,
            address[] memory,
            address[] memory,
            uint256[] memory
        )
    {
        uint256 arrLength = arts.length;
        uint256[] memory ids = new uint256[](arrLength);
        address[] memory artists = new address[](arrLength);
        address[] memory owners = new address[](arrLength);
        uint256[] memory status = new uint256[](arrLength);
        for (uint256 i = 0; i < arrLength; ++i) {
            Art memory art = arts[i];
            ids[i] = art.id;
            artists[i] = art.artist;
            owners[i] = art.owner;
            status[i] = art.status;
        }
        return (ids, artists, owners, status);
    }
    
    function findAllPendingArt()
        public
        view
        returns (
            uint256[] memory,
            address[] memory,
            address[] memory,
            uint256[] memory
        )
    {
        if (pendingArtCount == 0) {
            return (
                new uint256[](0),
                new address[](0),
                new address[](0),
                new uint256[](0)
            );
        } else {
            uint256 arrLength = arts.length;
            uint256[] memory ids = new uint256[](pendingArtCount);
            address[] memory artists = new address[](pendingArtCount);
            address[] memory owners = new address[](pendingArtCount);
            uint256[] memory status = new uint256[](pendingArtCount);
            uint256 idx = 0;
            for (uint256 i = 0; i < arrLength; ++i) {
                Art memory art = arts[i];
                if (art.status == 1) {
                    ids[idx] = art.id;
                    artists[idx] = art.artist;
                    owners[idx] = art.owner;
                    status[idx] = art.status;
                    idx++;
                }
            }
            return (ids, artists, owners, status);
        }

    }
    
    //===================================================================
    //
    //  Return list of artworks (token IDs) owned by account address
    //
    //====================================================================
    function findMyArts() public view returns (uint256[] memory _myArts) {
        require(msg.sender != address(0));
        uint256 numOftokens = balanceOf(msg.sender);
        if (numOftokens == 0) {
            return new uint256[](0);
        } else {
            uint256[] memory myArts = new uint256[](numOftokens);
            uint256 idx = 0;
            uint256 arrLength = arts.length;
            for (uint256 i = 0; i < arrLength; i++) {
                if (_tokenOwner[i] == msg.sender) {
                    myArts[idx] = i;
                    idx++;
                }
            }
            return myArts;
        }
    }

    function getArtAllTxn(uint256 _tokenId)
        public
        view
        returns (
            uint256[] memory _id,
            uint256[] memory _price,
            address[] memory seller,
            address[] memory buyer,
            uint256[] memory _txnDate
        )
    {
        ArtTxn[] memory artTxnList = artTxns[_tokenId];
        uint256 arrLength = artTxnList.length;
        uint256[] memory ids = new uint256[](arrLength);
        uint256[] memory prices = new uint256[](arrLength);
        address[] memory sellers = new address[](arrLength);
        address[] memory buyers = new address[](arrLength);
        uint256[] memory txnDates = new uint256[](arrLength);
        for (uint256 i = 0; i < artTxnList.length; ++i) {
            ArtTxn memory artTxn = artTxnList[i];
            ids[i] = artTxn.id;
            prices[i] = artTxn.price;
            sellers[i] = artTxn.seller;
            buyers[i] = artTxn.buyer;
            txnDates[i] = artTxn.txnDate;
        }
        return (ids, prices, sellers, buyers, txnDates);
    }
    
    function _transfer(address _from, address _to, uint256 _tokenId) private {
        _ownedTokensCount[_to]++;
        _ownedTokensCount[_from]--;
        _tokenOwner[_tokenId] = _to;
        emit Transfer(_from, _to, _tokenId);
    }
    
    function _mint(address _to, uint256 tokenId) internal {
        require(_to != address(0));
        require(!_exists(tokenId));
        _tokenOwner[tokenId] = _to;
        _ownedTokensCount[_to]++;
        emit Transfer(address(0), _to, tokenId);
    }
    
    //===================================================================
    //
    //  Return T/F indicating if an artwork (token) is owned
    //
    //====================================================================
    function _exists(uint256 tokenId) internal view returns (bool) {
        address owner = _tokenOwner[tokenId];
        return owner != address(0);
    }

    //===================================================================
    //
    //  Return number of artworks (tokens) owned by a particular owner
    //
    //====================================================================
    function balanceOf(address _owner) public view returns (uint256) {
        return _ownedTokensCount[_owner];
    }
    
    //===================================================================
    //
    //  Return account address of owner of artwork (token)
    //
    //====================================================================
    function ownerOf(uint256 _tokenId) public view returns (address _owner) {
        _owner = _tokenOwner[_tokenId];
    }
    
    function approve(address _to, uint256 _tokenId) public {
        require(isOwnerOf(_tokenId, msg.sender));
        _tokenApprovals[_tokenId] = _to;
        emit Approval(msg.sender, _to, _tokenId);
    }

    function transferFrom(address _from, address _to, uint256 _tokenId) public {
        require(_to != address(0));
        require(isOwnerOf(_tokenId, _from));
        require(isApproved(_to, _tokenId));
        _transfer(_from, _to, _tokenId);
    }

    function transfer(address _to, uint256 _tokenId) public {
        require(_to != address(0));
        require(isOwnerOf(_tokenId, msg.sender));
        _transfer(msg.sender, _to, _tokenId);
    }

    function getApproved(uint256 tokenId)
        public
        view
        returns (address operator)
    {
        require(_exists(tokenId));
        return _tokenApprovals[tokenId];
    }

    function setApprovalForAll(address operator, bool _approved) public {
        require(operator != msg.sender);
        _operatorApprovals[msg.sender][operator] = _approved;
        emit ApprovalForAll(msg.sender, operator, _approved);
    }
    
    function isApprovedForAll(address owner, address operator)
        public
        view
        returns (bool)
    {
        return _operatorApprovals[owner][operator];
    }
    
    function safeTransferFrom(address from, address to, uint256 tokenId)
        public
    {
        // not implemented in this contract
    }
    
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) public {
        //  not implemented in this contract
    }

    //===================================================================
    //
    //  Return T/F indicating if account address owns an artwork (token)
    //
    //====================================================================
    function isOwnerOf(uint256 tokenId, address account)
        public
        view
        returns (bool)
    {
        address owner = _tokenOwner[tokenId];
        require(owner != address(0));
        return owner == account;
    }
    
    function isApproved(address _to, uint256 _tokenId)
        private
        view
        returns (bool)
    {
        return _tokenApprovals[_tokenId] == _to;
    }

}
