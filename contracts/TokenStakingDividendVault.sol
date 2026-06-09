// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/IOpenFourVault.sol";
import "./interfaces/IOpenFourModuleSchema.sol";
import "./interfaces/ITagDescriptor.sol";

/// @title TokenStakingDividendVault — 代币质押分红金库
/// @notice 质押代币到金库，按比例获得BNB分红
contract TokenStakingDividendVault is IOpenFourVault, IOpenFourModuleSchema, ITagDescriptor {
    struct StakeConfig {
        uint256 minStakeAmount;   // 最小质押量
        uint256 lockDuration;     // 锁定期
    }

    struct StakerInfo {
        uint256 staked;
        uint256 stakeTime;
        uint256 rewardDebt;
    }

    mapping(address => StakeConfig) internal _configs;
    mapping(address => mapping(address => StakerInfo)) internal _stakers;
    mapping(address => uint256) internal _accumulated;
    mapping(address => uint256) internal _totalStaked;
    mapping(address => uint256) internal _accRewardPerShare;
    address internal _fourCore;

    uint256 internal constant MAGNITUDE = 1e18;

    modifier onlyCore() { require(msg.sender == _fourCore, "!core"); _; }
    error AlreadyInitialized();

    function init(address token, address fourCore, bytes calldata params, string calldata) external {
        if (address(_fourCore) != address(0)) revert AlreadyInitialized();
        _fourCore = fourCore;
        _configs[token] = abi.decode(params, (StakeConfig));
    }

    function onBuy(address, uint256, uint256 payment, uint256, bytes calldata) external onlyCore {
        _accumulated[msg.sender] += payment;
        if (_totalStaked[msg.sender] > 0) {
            _accRewardPerShare[msg.sender] += payment * MAGNITUDE / _totalStaked[msg.sender];
        }
    }

    function onSell(address, uint256, uint256 payment, uint256, bytes calldata) external onlyCore {
        _accumulated[msg.sender] += payment;
        if (_totalStaked[msg.sender] > 0) {
            _accRewardPerShare[msg.sender] += payment * MAGNITUDE / _totalStaked[msg.sender];
        }
    }

    function vaultBalance() external view returns (uint256) {
        return _accumulated[msg.sender];
    }

    function stake(address token, uint256 amount) external {
        StakeConfig storage cfg = _configs[token];
        require(amount >= cfg.minStakeAmount, "below min");
        StakerInfo storage s = _stakers[token][msg.sender];
        s.staked += amount;
        s.stakeTime = block.timestamp;
        s.rewardDebt = _accRewardPerShare[token];
        _totalStaked[token] += amount;
    }

    function unstake(address token, uint256 amount) external {
        StakeConfig storage cfg = _configs[token];
        StakerInfo storage s = _stakers[token][msg.sender];
        require(s.staked >= amount, "insufficient");
        require(block.timestamp >= s.stakeTime + cfg.lockDuration, "locked");
        _claimReward(token, msg.sender);
        s.staked -= amount;
        _totalStaked[token] -= amount;
    }

    function claimReward(address token) external {
        _claimReward(token, msg.sender);
    }

    function _claimReward(address token, address staker) internal {
        StakerInfo storage s = _stakers[token][staker];
        uint256 pending = s.staked * _accRewardPerShare[token] / MAGNITUDE - s.rewardDebt;
        if (pending > 0 && pending <= _accumulated[token]) {
            s.rewardDebt += pending;
            _accumulated[token] -= pending;
            payable(staker).transfer(pending);
        }
    }

    function getInitParams() external pure returns (bytes memory) {
        return abi.encode(StakeConfig({minStakeAmount: 1000 ether, lockDuration: 7 days}));
    }

    function moduleEncodeSchema() external pure returns (ModuleEncodeSchema memory) {
        ParamDescriptor[] memory params = new ParamDescriptor[](2);
        params[0] = ParamDescriptor("minStakeAmount", "最小质押量", "至少质押多少代币", "uint256", false, bytes32(uint256(1000 ether)), bytes32(uint256(0)), bytes32(type(uint256).max));
        params[1] = ParamDescriptor("lockDuration", "锁定期(秒)", "质押后多久才能取出", "uint256", false, bytes32(uint256(7 days)), bytes32(uint256(0)), bytes32(uint256(365 days)));
        return ModuleEncodeSchema(1, "module.vault.token-staking-dividend", params);
    }

    function descriptor() external pure returns (bytes8 tagId, string memory tag, string memory version) {
        tagId = bytes8(keccak256(bytes("module.vault.token-staking-dividend")));
        tag = "module.vault.token-staking-dividend";
        version = "v1.0.0";
    }
}
