// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;
import "./interfaces/IERC20.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import {NotInvestor, WholeClaimed, EmptyTokenClaim, OutofRange, NotYet} from "./Errors.sol";

interface IKolsIDO {
    struct User {
        uint256 userTotalClaimableAmount;
        uint256 updateLastClaimTimestamp;
        uint256 userTotalClaimed;
    }

    function defaultReleaseTime() external view returns (uint256);

    function kolsInvestorInfo(address _user) external view returns (User memory);
}

contract NewKolsIDO is Pausable {
    event Claim(address user, uint256 claimAmount, uint256 claimTime);
    event ChangeOwner(address oldOwner, address newOwner);
    event ChangeTGEtime(uint256 oldTime, uint256 newTime);

    IERC20 private immutable AIR_TOKEN;
    address public oldKolsIDO;
    address public owner;

    uint256 public claimStartTime;

    address[] internal signerList;
    mapping(address => uint256) confirmTime;
    mapping(address => User) public kolsInvestorInfo;

    struct User {
        uint256 userTotalClaimableAmount;
        uint256 updateLastClaimTimestamp;
        uint256 userTotalClaimed;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "No permission");
        _;
    }

    constructor(address _airAddress, address _oldKolsIDO) {
        AIR_TOKEN = IERC20(_airAddress);
        oldKolsIDO = _oldKolsIDO;
        owner = msg.sender;
    }

    function setClaimStartTime(uint256 _claimStartTime) external onlyOwner {
        claimStartTime = _claimStartTime;
    }

    function setOwner(address _newOwner) public onlyOwner {
        require(_newOwner != address(0));
        owner = _newOwner;
        emit ChangeOwner(msg.sender, _newOwner);
    }

    function pauseOnOff() external onlyOwner {
        if (!paused()) {
            _pause();
        } else {
            _unpause();
        }
    }

    function _calculmonth(uint256 _num) internal pure returns (uint256) {
        return _num * 30 days;
    }

    function callAirBalance() public view returns (uint256) {
        return AIR_TOKEN.balanceOf(address(this));
    }

    function _defaultReleaseTime() public view returns (uint256) {
        return IKolsIDO(oldKolsIDO).defaultReleaseTime();
    }

    function kolsClaimableAir(address _user) public view returns (uint256) {
        User memory kolsUser = kolsInvestorInfo[_user];

        if (kolsUser.updateLastClaimTimestamp == 0) {
            kolsUser.userTotalClaimed = IKolsIDO(oldKolsIDO).kolsInvestorInfo(_user).userTotalClaimed;
            kolsUser.userTotalClaimableAmount = IKolsIDO(oldKolsIDO).kolsInvestorInfo(_user).userTotalClaimableAmount;
            kolsUser.updateLastClaimTimestamp = IKolsIDO(oldKolsIDO).kolsInvestorInfo(_user).updateLastClaimTimestamp;
        }
        uint256 remainClaimableAmount = kolsUser.userTotalClaimableAmount;
        uint256 claimableAmount;
        uint256 defaultReleaseTime = _defaultReleaseTime();

        if (block.timestamp >= defaultReleaseTime && block.timestamp < defaultReleaseTime + _calculmonth(5)) {
            if (kolsUser.userTotalClaimed >= kolsUser.userTotalClaimableAmount) revert WholeClaimed();
            uint256 perSecondClaimableAmount = remainClaimableAmount / _calculmonth(5);

            if (kolsUser.updateLastClaimTimestamp <= defaultReleaseTime) {
                claimableAmount = (block.timestamp - defaultReleaseTime) * perSecondClaimableAmount;
            } else {
                claimableAmount = (block.timestamp - kolsUser.updateLastClaimTimestamp) * perSecondClaimableAmount;
            }
        } else if (block.timestamp >= defaultReleaseTime + _calculmonth(5)) {
            if (kolsUser.updateLastClaimTimestamp == 0) {
                claimableAmount = kolsUser.userTotalClaimableAmount;
            } else {
                if (kolsUser.userTotalClaimed >= kolsUser.userTotalClaimableAmount) revert WholeClaimed();
                claimableAmount = kolsUser.userTotalClaimableAmount - kolsUser.userTotalClaimed;
            }
        } else {
            revert OutofRange();
        }
        return claimableAmount;
    }

    function kolsClaimAir() external whenNotPaused {
        if (block.timestamp < claimStartTime) revert NotYet();
        User storage kolsUser = kolsInvestorInfo[msg.sender];
        if (kolsUser.updateLastClaimTimestamp == 0) {
            kolsUser.userTotalClaimed = IKolsIDO(oldKolsIDO).kolsInvestorInfo(msg.sender).userTotalClaimed;
            kolsUser.userTotalClaimableAmount = IKolsIDO(oldKolsIDO).kolsInvestorInfo(msg.sender).userTotalClaimableAmount;
            kolsUser.updateLastClaimTimestamp = IKolsIDO(oldKolsIDO).kolsInvestorInfo(msg.sender).updateLastClaimTimestamp;
        }
        if (kolsUser.userTotalClaimableAmount == 0) revert NotInvestor();
        uint256 claimableAmount = kolsClaimableAir(msg.sender);
        if (claimableAmount == 0) revert EmptyTokenClaim();
        kolsUser.userTotalClaimed += claimableAmount;
        kolsUser.updateLastClaimTimestamp = block.timestamp;
        AIR_TOKEN.transfer(msg.sender, claimableAmount);
        emit Claim(msg.sender, claimableAmount, block.timestamp);
    }

    function kolsUserInfo(address user) external view returns (uint256 total, uint256 claimable, uint256 claimed) {
        User memory kolsUser = kolsInvestorInfo[user];
        if (kolsUser.updateLastClaimTimestamp == 0) {
            claimed = IKolsIDO(oldKolsIDO).kolsInvestorInfo(user).userTotalClaimed;
            total = IKolsIDO(oldKolsIDO).kolsInvestorInfo(user).userTotalClaimableAmount;
        } else {
            total = kolsUser.userTotalClaimableAmount;
            claimed = kolsUser.userTotalClaimed;
        }
        claimable = kolsClaimableAir(user);
    }

    function setSigner(address[] memory _signer) external onlyOwner {
        require(_signer.length >= 3);
        for (uint256 i = 0; i < _signer.length; i++) {
            signerList.push(_signer[i]);
        }
    }

    function viewSigner() external view returns (address[] memory) {
        return signerList;
    }

    function signerConfirm() external {
        bool check;
        uint256 length = signerList.length;
        for (uint256 i; i < length; i++) {
            if (msg.sender == signerList[i]) {
                check = true;
                break;
            }
        }
        require(check);
        confirmTime[msg.sender] = block.timestamp;
    }
}
