// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "./IOracle.sol";
import "./ICollateralizationOracle.sol";
import "../refs/CoreRef.sol";
import "../pcv/IPCVDepositV2.sol";

interface IPausable {
    function paused() external view returns (bool);
}

/// @title Fei Protocol's Collateralization Oracle
/// @author eswak
/// @notice Reads a list of PCVDeposit that report their amount of collateral
///         and the amount of protocol-owned FEI they manage, to deduce the
///         protocol-wide collateralization ratio.
contract CollateralizationOracle is ICollateralizationOracle, CoreRef {
    using Decimal for Decimal.D256;

    // ----------- Events -----------

    event DepositAdd(address from, address indexed deposit, address indexed token);
    event DepositRemove(address from, address indexed deposit);
    event OracleUpdate(address from, address indexed token, address indexed oldOracle, address indexed newOracle);

    // ----------- Properties -----------

    /// @notice Array of PCVDeposits to inspect
    address[] public pcvDeposits;

    /// @notice Map of oracles to use to get USD values of assets held in
    ///         PCV deposits. This map is used to get the oracle address from
    ///         and ERC20 address.
    mapping(address => address) public tokenToOracle;
    /// @notice Map from token address to an array of deposit addresses. It is
    //          used to iterate on all deposits while making oracle requests
    //          only once.
    mapping(address => address[]) public tokenToDeposits;
    /// @notice Map from deposit address to token address. It is used like an
    ///         indexed version of the pcvDeposits array, to check existence
    ///         of a PCVdeposit in the current config.
    mapping(address => address) public depositToToken;
    /// @notice Array of all tokens held in the PCV. Used for iteration on tokens
    ///         and oracles.
    address[] public tokensInPcv;
    /// @notice Map to know if a given token is in the PCV. Used like an indexed
    ///         version of the tokensInPcv array.
    mapping(address => bool) public isTokenInPcv;

    // ----------- Constructor -----------

    /// @notice CollateralizationOracle constructor
    /// @param _core Fei Core for reference
    constructor(
        address _core
    ) CoreRef(_core) {}

    // ----------- State-changing methods -----------

    /// @notice Add a PCVDeposit to the list of deposits inspected by the
    ///         collateralization ratio oracle.
    ///         note : this function reverts if the deposit is already in the list.
    ///         note : this function reverts if the deposit's token has no oracle.
    /// @param _deposit : the PCVDeposit to add to the list.
    function addDeposit(address _deposit) external onlyGovernor {
        // if the PCVDeposit is already listed, revert.
        require(depositToToken[_deposit] == address(0), "CollateralizationOracle: deposit duplicate");

        // get the token in which the deposit reports its token
        address _token = IPCVDepositV2(_deposit).balanceReportedIn();

        // revert if there is no oracle of this deposit's token
        require(tokenToOracle[_token] != address(0), "CollateralizationOracle: no oracle");

        // add the PCVDeposit to the list
        pcvDeposits.push(_deposit);

        // update maps & arrays for faster access
        depositToToken[_deposit] = _token;
        tokenToDeposits[_token].push(_deposit);
        if (isTokenInPcv[_token] == false) {
          isTokenInPcv[_token] = true;
          tokensInPcv.push(_token);
        }

        // emit event
        emit DepositAdd(msg.sender, _deposit, _token);
    }

    /// @notice Remove a PCVDeposit from the list of deposits inspected by
    ///         the collateralization ratio oracle.
    ///         note : this function reverts if the input deposit is not found.
    /// @param _deposit : the PCVDeposit address to remove from the list.
    function removeDeposit(address _deposit) external onlyGovernor {
        // get the token in which the deposit reports its token
        address _token = depositToToken[_deposit];

        // revert if the deposit is not found
        require(_token != address(0), "CollateralizationOracle: deposit not found");

        // update maps & arrays for faster access
        // deposits array for the deposit's token
        depositToToken[_deposit] = address(0);
        bool found = false;
        for (uint256 i = 0; !found; i++) {
            if (tokenToDeposits[_token][i] == _deposit) {
                found = true;
                tokenToDeposits[_token][i] = tokenToDeposits[_token][tokenToDeposits[_token].length - 1];
                tokenToDeposits[_token].pop();
            }
        }
        // if it was the last deposit to have this token, remove this token from
        // the arrays also
        if (tokenToDeposits[_token].length == 0) {
          isTokenInPcv[_token] = false;
          found = false;
          for (uint256 i = 0; !found; i++) {
              if (tokensInPcv[i] == _token) {
                  found = true;
                  tokensInPcv[i] = tokensInPcv[tokensInPcv.length - 1];
                  tokensInPcv.pop();
              }
          }
        }
        // remove from the main array
        found = false;
        for (uint256 i = 0; !found; i++) {
            if (pcvDeposits[i] == _deposit) {
                found = true;
                pcvDeposits[i] = pcvDeposits[pcvDeposits.length - 1];
                pcvDeposits.pop();
            }
        }

        // emit event
        emit DepositRemove(msg.sender, _deposit);
    }

    /// @notice Set the price feed oracle (in USD) for a given asset.
    /// @param _token : the asset to add price oracle for
    /// @param _newOracle : price feed oracle for the given asset
    function setOracle(address _token, address _newOracle) external onlyGovernor {
        // add oracle to the map(ERC20Address) => OracleAddress
        address _oldOracle = tokenToOracle[_token];
        tokenToOracle[_token] = _newOracle;

        // emit event
        emit OracleUpdate(msg.sender, _token, _oldOracle, _newOracle);
    }

    // ----------- IOracle override methods -----------
    /// @notice update all oracles required for this oracle to work that are not
    ///         paused themselves.
    function update() external override whenNotPaused {
        for (uint256 i = 0; i < tokensInPcv.length; i++) {
            address _oracle = tokenToOracle[tokensInPcv[i]];
            if (!IPausable(_oracle).paused()) {
                IOracle(_oracle).update();
            }
        }
    }

    // @notice returns true if any of the oracles required for this oracle to
    //         work are outdated.
    function isOutdated() external override view returns (bool) {
        bool _outdated = false;
        for (uint256 i = 0; i < tokensInPcv.length && !_outdated; i++) {
            address _oracle = tokenToOracle[tokensInPcv[i]];
            if (!IPausable(_oracle).paused()) {
                _outdated = _outdated || IOracle(_oracle).isOutdated();
            }
        }
        return _outdated;
    }

    /// @notice Get the current collateralization ratio of the protocol.
    /// @return collateralRatio the current collateral ratio of the protocol.
    /// @return validityStatus the current oracle validity status (false if any
    ///         of the oracles for tokens held in the PCV are invalid, or if
    ///         this contract is paused).
    function read() public override view returns (Decimal.D256 memory collateralRatio, bool validityStatus) {
        // fetch PCV stats
        (
          uint256 _protocolControlledValue,
          uint256 _userCirculatingFei,
          , // we don't need protocol equity
          bool _valid
        ) = pcvStats();

        // The protocol collateralization ratio is defined as the total USD
        // value of assets held in the PCV, minus the circulating FEI.
        collateralRatio = Decimal.ratio(_protocolControlledValue, _userCirculatingFei);
        validityStatus = _valid;
    }

    // ----------- ICollateralizationOracle override methods -----------

    /// @notice returns the Protocol-Controlled Value, User-circulating FEI, and
    ///         Protocol Equity.
    /// @return protocolControlledValue : the total USD value of all assets held
    ///         by the protocol.
    /// @return userCirculatingFei : the number of FEI not owned by the protocol.
    /// @return protocolEquity : the difference between PCV and user circulating FEI.
    ///         If there are more circulating FEI than $ in the PCV, equity is 0.
    /// @return validityStatus : the current oracle validity status (false if any
    ///         of the oracles for tokens held in the PCV are invalid, or if
    ///         this contract is paused).
    function pcvStats() public override view returns (
      uint256 protocolControlledValue,
      uint256 userCirculatingFei,
      uint256 protocolEquity,
      bool validityStatus
    ) {
        uint256 _protocolControlledFei = 0;
        address _fei = address(fei());
        validityStatus = !paused();

        // For each token...
        for (uint256 i = 0; i < tokensInPcv.length; i++) {
            address _token = tokensInPcv[i];
            bool _oracleRead = false; // used to read oracle only once
            bool _oracleValid = false; // validity flag of oracle.read()
            Decimal.D256 memory _oraclePrice = Decimal.zero();

            // Use a price of 0 for FEI, because the deposits that report their
            // balance in FEI should add 0$ to the Protocol-controlled value.
            if (_token == _fei) {
              _oracleRead = true;
              _oracleValid = true;
            }

            // For each deposit...
            uint256 _nTokens = 0;
            for (uint256 j = 0; j < tokenToDeposits[_token].length; j++) {
                address _deposit = tokenToDeposits[_token][j];

                // ignore deposits that are paused
                if (!IPausable(_deposit).paused()) {
                  // On the first unpaused deposit, read the oracle.
                  // This is done inside the loop, after _deposit.paused() check,
                  // because if all deposits of an asset are paused, there is no
                  // need to read the oracle.
                  if (!_oracleRead) {
                    (_oraclePrice, _oracleValid) = IOracle(tokenToOracle[_token]).read();
                    _oracleRead = true;
                    if (!_oracleValid) {
                      validityStatus = false;
                    }
                  }

                  // read the deposit
                  (uint256 _depositBalance, uint256 _depositFei) = IPCVDepositV2(_deposit).balanceAndFei();
                  _nTokens += _depositBalance;
                  _protocolControlledFei += _depositFei;
                }
            }

            protocolControlledValue += _oraclePrice.mul(_nTokens).asUint256();
        }

        userCirculatingFei = fei().totalSupply() - _protocolControlledFei;
        if (protocolControlledValue > userCirculatingFei) {
            protocolEquity = protocolControlledValue - userCirculatingFei;
        }

        userCirculatingFei = fei().totalSupply() - _protocolControlledFei;
    }

    /// @notice returns true if the protocol is overcollateralized. Overcollateralization
    ///         is defined as the protocol having more assets in its PCV (Protocol
    ///         Controlled Value) than the circulating (user-owned) FEI, i.e.
    ///         a positive Protocol Equity.
    ///         Note: the validity status is ignored in this function.
    function isOvercollateralized() external view override whenNotPaused returns (bool) {
        (,, uint256 _protocolEquity,) = pcvStats();
        return _protocolEquity > 0;
    }
}
