// SPDX-License-Identifier: MIT
pragma solidity = 0.8.28;

//import the SafeERC20 interface
import "@openzeppelin/contracts@5.1.0/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable@5.1.0/proxy/utils/Initializable.sol";


contract PlantMeRouter is Initializable {
    address public owner;
    address public plantmeRouter;
    address public nativeCoin;
    address public emergencyWallet;
    // Storage slot for the implementation address
    bytes32 private constant _IMPLEMENTATION_SLOT = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);

    // Initialize PlantMeRouter
    function initialize(address _impl, address _owner, address _nativeCoin, address _emergencyWallet) external initializer {
        // Store the implementation address in the predefined slot
        _setImplementation(_impl);
        owner = _owner;
        plantmeRouter = address(this);
        nativeCoin = _nativeCoin;
        emergencyWallet = _emergencyWallet;
    }

    receive() payable external {}

    using SafeERC20 for IERC20;

    event UpdatePlantMeRouter(address plantmeRouter);
    event UpdateNativeCoin(address wrappedNativeCoin);
    event UpdateEmergencyWallet(address emergencyWallet);
    event TransferSent(address indexed, address indexed, uint indexed);

    modifier onlyOwner() {
        require(owner == msg.sender, "not owner");
        _;
    }

    function implementation() public view returns (address impl) {
        bytes32 slot = _IMPLEMENTATION_SLOT;
        assembly {
            impl := sload(slot)
        }
    }

    function _setImplementation(address newImplementation) internal {
        bytes32 slot = _IMPLEMENTATION_SLOT;
        assembly {
            sstore(slot, newImplementation)
        }
    }

    // Fallback function to delegate calls to the implementation contract
    fallback() external payable {
        _delegate(implementation());
    }

    // Internal function to delegate calls to the implementation contract
    function _delegate(address _implementation) internal {
        require(_implementation == implementation(), "mismatch");
        assembly {
            // Copy msg.data to memory
            calldatacopy(0, 0, calldatasize())

            // Delegate call to the implementation contract
            let result := delegatecall(gas(), _implementation, 0, calldatasize(), 0, 0)

            // Copy the returned data
            returndatacopy(0, 0, returndatasize())

            // Check the result and revert if the call failed
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    /**
     * router
     */
    function updateRouterAddress(address new_plantmeRouter) external onlyOwner {
        plantmeRouter = new_plantmeRouter;
        emit UpdatePlantMeRouter(new_plantmeRouter);
    }

    /**
     * native coin
     */
    function updateNativeCoin(address new_nativeCoin) external onlyOwner {
        nativeCoin = new_nativeCoin;
        emit UpdateNativeCoin(new_nativeCoin);
    }

    /**
     * emergency wallet
     */
    function updateEmergencyWallet(address new_emergencyWallet) external onlyOwner {
        emergencyWallet = new_emergencyWallet;
        emit UpdateEmergencyWallet(new_emergencyWallet);
    }

    /**
     * admin
     */
    function changeOwner(address _owner) external onlyOwner {
        require(_owner != address(0), "can't be zero address");
        owner = _owner;
    }

    /**
     * rescue native coin
     */
    function transferNativeCoin(uint256 amount, address to) external onlyOwner {
        require(amount <= address(this).balance, "exceed amount input"); // Checks
        (bool sent,) = payable(to).call{value: amount}(""); // Interaction
        require(sent, "failed to send");
        emit TransferSent(address(this), to, amount);
    }

    /**
     * rescue ERC-20 token
     */
    function transferERC20Token(address token, uint256 amount, address to) external onlyOwner {
        require(amount <= IERC20(token).balanceOf(address(this)), "exceed amount input");
        IERC20(token).safeTransfer(to, amount);
        emit TransferSent(address(this), to, amount);
    }
}