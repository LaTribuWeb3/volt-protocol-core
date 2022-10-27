// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {Decimal} from "../external/Decimal.sol";
import {Constants} from "../Constants.sol";
import {OracleRef} from "./../refs/OracleRef.sol";
import {PCVDeposit} from "./../pcv/PCVDeposit.sol";
import {IPCVDeposit} from "./../pcv/IPCVDeposit.sol";
import {IPegStabilityModule} from "./IPegStabilityModule.sol";

contract PegStabilityModule is
    IPegStabilityModule,
    OracleRef,
    PCVDeposit,
    ReentrancyGuard
{
    using Decimal for Decimal.D256;
    using SafeCast for *;
    using SafeERC20 for IERC20;

    /// @notice the token this PSM will exchange for FEI
    /// This token will be set to WETH9 if the bonding curve accepts eth
    IERC20 public immutable override underlyingToken;

    /// @notice boolean switch that indicates whether redemptions are paused
    bool public redeemPaused;

    /// @notice event that is emitted when redemptions are paused
    event RedemptionsPaused(address account);

    /// @notice event that is emitted when redemptions are unpaused
    event RedemptionsUnpaused(address account);

    /// @notice boolean switch that indicates whether minting is paused
    bool public mintPaused;

    /// @notice event that is emitted when minting is paused
    event MintingPaused(address account);

    /// @notice event that is emitted when minting is unpaused
    event MintingUnpaused(address account);

    /// @notice struct for passing constructor parameters related to OracleRef
    struct OracleParams {
        address coreAddress;
        address oracleAddress;
        address backupOracle;
        int256 decimalsNormalizer;
        bool doInvert;
    }

    /// @notice constructor
    /// @param params PSM constructor parameter struct
    constructor(OracleParams memory params, IERC20 _underlyingToken)
        OracleRef(
            params.coreAddress,
            params.oracleAddress,
            params.backupOracle,
            params.decimalsNormalizer,
            params.doInvert
        )
    {
        underlyingToken = _underlyingToken;
    }

    /// @notice modifier that allows execution when redemptions are not paused
    modifier whileRedemptionsNotPaused() {
        require(!redeemPaused, "PegStabilityModule: Redeem paused");
        _;
    }

    /// @notice modifier that allows execution when minting is not paused
    modifier whileMintingNotPaused() {
        require(!mintPaused, "PegStabilityModule: Minting paused");
        _;
    }

    /// @notice set secondary pausable methods to paused
    function pauseRedeem() external onlyGuardianOrGovernor {
        redeemPaused = true;
        emit RedemptionsPaused(msg.sender);
    }

    /// @notice set secondary pausable methods to unpaused
    function unpauseRedeem() external onlyGuardianOrGovernor {
        redeemPaused = false;
        emit RedemptionsUnpaused(msg.sender);
    }

    /// @notice set secondary pausable methods to paused
    function pauseMint() external onlyGuardianOrGovernor {
        mintPaused = true;
        emit MintingPaused(msg.sender);
    }

    /// @notice set secondary pausable methods to unpaused
    function unpauseMint() external onlyGuardianOrGovernor {
        mintPaused = false;
        emit MintingUnpaused(msg.sender);
    }

    /// @notice withdraw assets from PSM to an external address
    function withdraw(address to, uint256 amount)
        external
        virtual
        override
        onlyPCVController
    {
        _withdrawERC20(address(underlyingToken), to, amount);
    }

    /// @notice internal helper method to redeem fei in exchange for an external asset
    function _redeem(
        address to,
        uint256 amountFeiIn,
        uint256 minAmountOut
    ) internal virtual returns (uint256 amountOut) {
        updateOracle();

        amountOut = _getRedeemAmountOut(amountFeiIn);
        require(
            amountOut >= minAmountOut,
            "PegStabilityModule: Redeem not enough out"
        );

        IERC20(volt()).safeTransferFrom(msg.sender, address(this), amountFeiIn);

        _transfer(to, amountOut);

        emit Redeem(to, amountFeiIn, amountOut);
    }

    /// @notice internal helper method to mint fei in exchange for an external asset
    function _mint(
        address to,
        uint256 amountIn,
        uint256 minAmountOut
    ) internal virtual returns (uint256 amountVoltOut) {
        updateOracle();

        amountVoltOut = _getMintAmountOut(amountIn);
        require(
            amountVoltOut >= minAmountOut,
            "PegStabilityModule: Mint not enough out"
        );

        _transferFrom(msg.sender, address(this), amountIn);

        IERC20(volt()).safeTransfer(to, amountVoltOut);

        emit Mint(to, amountIn, amountVoltOut);
    }

    /// @notice function to redeem FEI for an underlying asset
    /// We do not burn Fei; this allows the contract's balance of Fei to be used before the buffer is used
    /// In practice, this helps prevent artificial cycling of mint-burn cycles and prevents a griefing vector.
    function redeem(
        address to,
        uint256 amountFeiIn,
        uint256 minAmountOut
    )
        external
        virtual
        override
        nonReentrant
        whenNotPaused
        whileRedemptionsNotPaused
        returns (uint256 amountOut)
    {
        amountOut = _redeem(to, amountFeiIn, minAmountOut);
    }

    /// @notice function to buy FEI for an underlying asset
    /// We first transfer any contract-owned fei, then mint the remaining if necessary
    function mint(
        address to,
        uint256 amountIn,
        uint256 minAmountOut
    )
        external
        virtual
        override
        nonReentrant
        whenNotPaused
        whileMintingNotPaused
        returns (uint256 amountFeiOut)
    {
        amountFeiOut = _mint(to, amountIn, minAmountOut);
    }

    // ----------- Public View-Only API ----------

    /// @notice calculate the amount of FEI out for a given `amountIn` of underlying
    /// First get oracle price of token
    /// Then figure out how many dollars that amount in is worth by multiplying price * amount.
    /// ensure decimals are normalized if on underlying they are not 18
    function getMintAmountOut(uint256 amountIn)
        public
        view
        override
        returns (uint256 amountFeiOut)
    {
        amountFeiOut = _getMintAmountOut(amountIn);
    }

    /// @notice calculate the amount of underlying out for a given `amountFeiIn` of FEI
    /// First get oracle price of token
    /// Then figure out how many dollars that amount in is worth by multiplying price * amount.
    /// ensure decimals are normalized if on underlying they are not 18
    function getRedeemAmountOut(uint256 amountFeiIn)
        public
        view
        override
        returns (uint256 amountTokenOut)
    {
        amountTokenOut = _getRedeemAmountOut(amountFeiIn);
    }

    /// @notice the maximum mint amount out
    function getMaxMintAmountOut() external view override returns (uint256) {
        return volt().balanceOf(address(this));
    }

    /// @notice function from PCVDeposit that must be overriden
    function balance() public view virtual override returns (uint256) {
        return underlyingToken.balanceOf(address(this));
    }

    /// @notice returns address of token this contracts balance is reported in
    function balanceReportedIn() public view override returns (address) {
        return address(underlyingToken);
    }

    /// @notice override default behavior of not checking fei balance
    function resistantBalanceAndVolt()
        public
        view
        override
        returns (uint256, uint256)
    {
        return (balance(), voltBalance());
    }

    // ----------- Internal Methods -----------

    /// @notice helper function to get mint amount out based on current market prices
    /// @dev will revert if price is outside of bounds and bounded PSM is being used
    function _getMintAmountOut(uint256 amountIn)
        internal
        view
        virtual
        returns (uint256 amountFeiOut)
    {
        Decimal.D256 memory price = readOracle();
        _validatePriceRange(price);

        Decimal.D256 memory adjustedAmountIn = price.mul(amountIn);

        amountFeiOut = adjustedAmountIn.asUint256();
    }

    /// @notice helper function to get redeem amount out based on current market prices
    /// @dev will revert if price is outside of bounds and bounded PSM is being used
    function _getRedeemAmountOut(uint256 amountFeiIn)
        internal
        view
        virtual
        returns (uint256 amountTokenOut)
    {
        Decimal.D256 memory price = readOracle();
        _validatePriceRange(price);

        /// get amount of dollars being provided
        Decimal.D256 memory adjustedAmountIn = Decimal.from(amountFeiIn);

        /// now turn the dollars into the underlying token amounts
        /// dollars / price = how much token to pay out
        amountTokenOut = adjustedAmountIn.div(price).asUint256();
    }

    /// @notice transfer ERC20 token
    function _transfer(address to, uint256 amount) internal {
        SafeERC20.safeTransfer(underlyingToken, to, amount);
    }

    /// @notice transfer assets from user to this contract
    function _transferFrom(
        address from,
        address to,
        uint256 amount
    ) internal {
        SafeERC20.safeTransferFrom(underlyingToken, from, to, amount);
    }

    /// @notice no-op to maintain backwards compatability with IPCVDeposit
    function deposit() external override {}

    // ----------- Hooks -----------

    /// @notice overriden function in the bounded PSM
    function _validatePriceRange(Decimal.D256 memory price)
        internal
        view
        virtual
    {}
}
