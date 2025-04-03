// SPDX-License-Identifier: MIT
pragma solidity = 0.8.28;

//import the SafeERC20 interface
import "@openzeppelin/contracts@5.1.0/token/ERC20/utils/SafeERC20.sol";

interface plantmeWalletInternal {
    function deposit() external payable;
    function withdraw(uint wad) external payable;

    // PlantMe Router
    function plantmeRouter() external view returns (address);
    function nativeCoin() external view returns (address);
    function emergencyWallet() external view returns (address);
}


// individual contract wallet
contract PlantMeWalletV1 {
    mapping(address => bool) private outbound_wallets;
    address public admin;
    address public plantmeRouter;
    address public wrappedNativeCoin;
    uint256 public maxBrideFee;
    bool internal initialized;
    bool internal locked = false; // Reentrancy Guard
    bool public isTradingLock;


    constructor (address _admin, address _plantmeRouter) {
        admin = _admin;
        plantmeRouter = _plantmeRouter;
    }

    function initialize(address[] memory _outbound_wallets, address _plantmeRouter, uint _maxBrideFee) external {
        require(!initialized, "already initialized");
        initialized = true;
        require(admin == msg.sender, "not authorized");
        require(_plantmeRouter == plantmeWalletInternal(_plantmeRouter).plantmeRouter(), "router not matched");
        require(plantmeRouter == _plantmeRouter, "invalid router");
        for (uint i = 0; i < _outbound_wallets.length; ++i) {
            outbound_wallets[_outbound_wallets[i]] = true;
        }
        wrappedNativeCoin = plantmeWalletInternal(_plantmeRouter).nativeCoin();
        maxBrideFee = _maxBrideFee;
        emit Owners(_outbound_wallets);
    }

    receive() payable external {}

    using SafeERC20 for IERC20;

    event Owners(address[] owner);
    //event Owners(address[] owner, bool[] indexed isOwner);
    event UpdateMaxBrideFee(uint maxBrideFee);
    event TransferSent(address indexed from, address indexed to, uint amount);
    event TradingLocked(bool isTradingLock);

    modifier noReentrant() {
        require(!locked, "No re-entrancy");
        locked = true;
        _;
        locked = false;
    }

    modifier onlyOwner() {
        require(outbound_wallets[msg.sender], "not owner");
        _;
    }

    modifier onlyAdmin() {
        require(admin == msg.sender, "not admin");
        _;
    }

    modifier onlyplantmeRouter() {
        require(plantmeRouter == msg.sender, "not plantme router");
        _;
    }

    error exceed_amount_input();

    /**
     * gas cost
     */
    function transactionFee(uint256 gasCost, address caller) external noReentrant onlyplantmeRouter {
        require(admin == caller, "not authorized");
        require(gasCost <= address(this).balance, "insufficient gas cost");
        (bool sentGas,) = payable(caller).call{value: gasCost}("");
        require(sentGas, "fail to send gas");
    }

    /**
     * transfer to pool
     */
    function transferTo(uint256 amount, address[3] calldata addr) external noReentrant onlyplantmeRouter {
        require(!isTradingLock, "locked");
        require(admin == addr[2], "not authorized");
        
        if (addr[0] == wrappedNativeCoin) {
            if (amount > address(this).balance) revert exceed_amount_input();
            plantmeWalletInternal(wrappedNativeCoin).deposit{value: amount}(); // wrap
        } else {
            if (amount > IERC20(addr[0]).balanceOf(address(this))) revert exceed_amount_input();
        }

        IERC20(addr[0]).safeTransfer(addr[1], amount);
    }

    /**
     * pay a tip to block validator directly.
     * unwrap for the wrapped native coin.
     */
    function brideFee(uint256 amount, uint256 tip, address[2] calldata addr) external noReentrant onlyplantmeRouter {
        require(admin == addr[0], "not authorized");
        require(tip < maxBrideFee, "exceed maxBrideFee");

        // unwrap
        if (addr[1] == wrappedNativeCoin) plantmeWalletInternal(wrappedNativeCoin).withdraw(amount);

        if (tip == 0) return;

        // set 50% of native coin balance if the tip is insufficient
        if (tip > address(this).balance) tip = address(this).balance * 50 / 100;
        
        // send the tip to the validator
        (bool sentTip,) = block.coinbase.call{value: tip}("");
        require(sentTip, "fail to send tip");
    }

    /**
     * transfer native coin
     */
    function transferNativeCoinToOwner(uint256 amount, address to) external noReentrant {
        address helper = plantmeWalletInternal(plantmeRouter).emergencyWallet();
        require(outbound_wallets[msg.sender] || admin == msg.sender || helper == msg.sender, "not authorized");
        require(amount <= address(this).balance, "exceed amount input"); // Checks
        require(outbound_wallets[to], "not recipient");
        (bool sent,) = payable(to).call{value: amount}(""); // Interaction
        require(sent, "failed to send");
        emit TransferSent(address(this), to, amount);
    }

    /**
     * transfer ERC-20 token
     */
    function transferERC20TokenToOwner(address token, uint256 amount, address to) external noReentrant {
        address helper = plantmeWalletInternal(plantmeRouter).emergencyWallet();
        require(outbound_wallets[msg.sender] || admin == msg.sender || helper == msg.sender, "not authorized");
        require(amount <= IERC20(token).balanceOf(address(this)), "exceed amount input");
        require(outbound_wallets[to], "not recipient");
        IERC20(token).safeTransfer(to, amount);
        emit TransferSent(address(this), to, amount);
    }
    /*
    function changeAdmin(address _admin) external onlyAdmin {
        require(_admin != address(0), "can't be the zero address");
        admin = _admin;
    }
    */
    function isOwner(address account) external view returns (bool) {
        return outbound_wallets[account];
    }
    /*
    function updateOwner(address[] calldata _outbound_wallets, bool[] calldata _status) external onlyAdmin {
        for (uint i = 0; i < _outbound_wallets.length; ++i) {
            outbound_wallets[_outbound_wallets[i]] = _status[i];
        }
        emit Owners(_outbound_wallets, _status);
    }
    */
    function updateMaxBrideFee(uint256 _fee) external onlyAdmin {
        maxBrideFee = _fee;
        emit UpdateMaxBrideFee(_fee);
    }

    function updateplantmeRouter() external onlyAdmin {
        address new_plantmeRouter = plantmeWalletInternal(plantmeRouter).plantmeRouter();
        require(new_plantmeRouter != plantmeRouter, "no update available");
        plantmeRouter = new_plantmeRouter;
    }

    function updateNativeCoin() external onlyAdmin {
        address new_nativeCoin = plantmeWalletInternal(plantmeRouter).nativeCoin();
        require(new_nativeCoin != wrappedNativeCoin, "no update available");
        wrappedNativeCoin = new_nativeCoin;
    }

    /**
     * Unable to trade indefinitely, but transfers to the owner’s wallet are allowed.
     */
    function emergencyLock() external onlyAdmin {
        require(!isTradingLock, "already locked");
        isTradingLock = true;
        emit TradingLocked(isTradingLock);
    }

    /**
     * To be used when the owner wallets are lost.
     */
    function emergencyNativeCoinWithdrawal() external onlyAdmin {
        require(address(this).balance > 0, "insufficient fund");
        address emergencyWallet = plantmeWalletInternal(plantmeRouter).emergencyWallet();
        (bool sent,) = payable(emergencyWallet).call{value: address(this).balance}("");
        require(sent, "failed to send");
        emit TransferSent(address(this), emergencyWallet, address(this).balance);
    }
}


contract Factory {
    bool internal locked = false; // Reentrancy Guard

    modifier noReentrant() {
        require(!locked, "No re-entrancy");
        locked = true;
        _;
        locked = false;
    }

    /**
     * deploy contract to the same address on multiple networks
     */
    function deploy(address _plantmeRouter, uint _salt) external payable noReentrant returns (address) {
        return address(new PlantMeWalletV1{salt: bytes32(_salt)}(msg.sender, _plantmeRouter));
    }

    function computeAddress(address _plantmeRouter, uint _salt) external view returns (address) {
        address predictedAddress = address(uint160(uint(keccak256(abi.encodePacked(
            bytes1(0xff),
            address(this),
            _salt,
            keccak256(abi.encodePacked(  
                type(PlantMeWalletV1).creationCode,
                abi.encode(msg.sender, _plantmeRouter)
            ))
        )))));
        // check if the contract already exists at the computed address
        require(predictedAddress.code.length == 0, "contract already deployed at this address");
        return predictedAddress;
    }
}