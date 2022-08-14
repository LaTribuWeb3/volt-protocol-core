// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {PCVDepositV2} from "../PCVDepositV2.sol";
import {CToken} from "./CToken.sol";
import {CoreRef} from "../../refs/CoreRef.sol";
import {TribeRoles} from "../../core/TribeRoles.sol";

/// @title base class for a Compound PCV Deposit
/// @author Fei Protocol
abstract contract CompoundPCVDepositBase is PCVDepositV2 {
    CToken public immutable cToken;

    uint256 private constant EXCHANGE_RATE_SCALE = 1e18;

    /// @notice Compound PCV Deposit constructor
    /// @param _core Fei Core for reference
    /// @param _cToken Compound cToken to deposit
    constructor(address _core, address _cToken) CoreRef(_core) {
        cToken = CToken(_cToken);
        require(cToken.isCToken(), "CompoundPCVDeposit: Not a cToken");
    }

    /// @notice withdraw tokens from the PCV allocation
    /// @param amountUnderlying of tokens withdrawn
    /// @param to the address to send PCV to
    function withdraw(address to, uint256 amountUnderlying)
        external
        override
        hasAnyOfTwoRoles(TribeRoles.GOVERNOR, TribeRoles.PCV_CONTROLLER)
        whenNotPaused
    {
        _withdraw(to, amountUnderlying);
    }

    /// @notice withdraw all tokens from the PCV allocation
    /// @param to the address to send PCV to
    function withdrawAll(address to)
        external
        hasAnyOfTwoRoles(TribeRoles.GOVERNOR, TribeRoles.PCV_CONTROLLER)
        whenNotPaused
    {
        uint256 amountUnderlying = balance();
        _withdraw(to, amountUnderlying);
    }

    /// @notice returns total balance of PCV in the Deposit excluding the FEI
    /// @dev returns stale values from Compound if the market hasn't been updated
    function balance() public view override returns (uint256) {
        uint256 exchangeRate = cToken.exchangeRateStored();
        return
            (cToken.balanceOf(address(this)) * exchangeRate) /
            EXCHANGE_RATE_SCALE;
    }

    function _withdraw(address to, uint256 amountUnderlying) internal {
        require(
            cToken.redeemUnderlying(amountUnderlying) == 0,
            "CompoundPCVDeposit: redeem error"
        );
        _transferUnderlying(to, amountUnderlying);

        emit Withdrawal(msg.sender, to, amountUnderlying);
    }

    function _transferUnderlying(address to, uint256 amount) internal virtual;
}
