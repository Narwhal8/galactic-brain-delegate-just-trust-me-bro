// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { IJBDirectory } from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBDirectory.sol";
import { IJBFundingCycleDataSource } from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBFundingCycleDataSource.sol";
import { IJBPayDelegate } from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBPayDelegate.sol";
import { IJBPaymentTerminal } from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBPaymentTerminal.sol";
import { IJBRedemptionDelegate } from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBRedemptionDelegate.sol";
import { JBPayParamsData } from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBPayParamsData.sol";
import { JBDidPayData } from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBDidPayData.sol";
import { JBDidRedeemData } from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBDidRedeemData.sol";
import { JBRedeemParamsData } from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBRedeemParamsData.sol";
import { JBPayDelegateAllocation } from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBPayDelegateAllocation.sol";
import { JBRedemptionDelegateAllocation } from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBRedemptionDelegateAllocation.sol";
import { DeployMyDelegateData } from "./structs/DeployMyDelegateData.sol";

/// @notice A contract that is a Data Source, a Pay Delegate, and a Redemption Delegate.
/// @dev This example implementation confines payments to an allow list and includes a custom bonus distribution.
contract MyDelegate is
    IJBFundingCycleDataSource,
    IJBPayDelegate,
    IJBRedemptionDelegate
{
    error INVALID_PAYMENT_EVENT(
        address caller,
        uint256 projectId,
        uint256 value
    );
    error INVALID_REDEMPTION_EVENT(
        address caller,
        uint256 projectId,
        uint256 value
    );
    error PAYER_NOT_ON_ALLOWLIST(address payer);

    /// @notice The Juicebox project ID this contract's functionality applies to.
    uint256 public projectId;

    /// @notice The directory of terminals and controllers for projects.
    IJBDirectory public directory;

    //Added function. PayoutBonuses declaration.
    uint256 private payoutbonus1;
    uint256 private payoutbonus2;
    uint256 private payoutbonus3;

    // Added function. BonusThreshold declarations.                     //
    uint256 private bonusThreshold1;
    uint256 private bonusThreshold2;
    uint256 private bonusThreshold3;

    // Added ability. Checks to make sure you didn't accidentally let someone mint more tokens than they can make on redeem               //

    uint256 public SafetyNumber;

    /// @notice Addresses allowed to make payments to the treasury.
    mapping(address => bool) public paymentFromAddressIsAllowed;

    /// @notice This function gets called when the project receives a payment.
    /// @dev Part of IJBFundingCycleDataSource.
    /// @dev This implementation just sets this contract up to receive a `didPay` call.
    /// @param _data The Juicebox standard project payment data.
    /// @return weight The weight that project tokens should get minted relative to.
    /// @return memo A memo to be forwarded to the event.
    /// @return delegateAllocations Amount to be sent to delegates instead of adding to the local balance.
    function payParams(JBPayParamsData calldata _data)
        external
        virtual
        override
        returns (
            uint256 weight,
            string memory memo,
            JBPayDelegateAllocation[] memory delegateAllocations
        )
    {
        // Calculate the payout bonus based on the weight
        uint256 payoutBonus = getPayoutBonus(_data.weight);

        // Calculate the final weight after applying the bonus
        weight = (_data.weight * payoutBonus) / 100;

        // Forward the default memo received from the payer
        memo = _data.memo;

        // Add `this` contract as a Pay Delegate so that it receives a `didPay` call
        delegateAllocations = new JBPayDelegateAllocation[](1);
        delegateAllocations[0] = JBPayDelegateAllocation(this, 0);

        // Save the weighting to the delegate for the purpose of a safety check later on redeem
        SafetyNumber = _data.weight;
    }

    /// @notice This function gets called when the project's token holders redeem.
    /// @dev Part of IJBFundingCycleDataSource.
    /// @param _data Standard Juicebox project redemption data.
    /// @return reclaimAmount Amount to be reclaimed from the treasury.
    /// @return memo A memo to be forwarded to the event.
    /// @return delegateAllocations Amount to be sent to delegates instead of being added to the beneficiary.
    function redeemParams(JBRedeemParamsData calldata _data)
        external
        view
        virtual
        override
        returns (
            uint256 reclaimAmount,
            string memory memo,
            JBRedemptionDelegateAllocation[] memory delegateAllocations
        )
    {
        // Forward the default reclaimAmount received from the protocol.
        reclaimAmount = _data.reclaimAmount.value;
        require(
            SafetyNumber >= reclaimAmount / payoutbonus3,
            "You are unable to redeem as you may effectively have over a 100% redeem rate"
        );

        // Forward the default memo received from the redeemer.
        memo = _data.memo;

        // Add `this` contract as a Redeem Delegate so that it receives a `didRedeem` call.
        delegateAllocations = new JBRedemptionDelegateAllocation[](1);
        delegateAllocations[0] = JBRedemptionDelegateAllocation(this, 0);
    }

    /// @notice Indicates if this contract adheres to the specified interface.
    /// @dev See {IERC165-supportsInterface}.
    /// @param _interfaceId The ID of the interface to check for adherence to.
    /// @return A flag indicating if the provided interface ID is supported.
    function supportsInterface(bytes4 _interfaceId)
        public
        view
        virtual
        override
        returns (bool)
    {
        return
            _interfaceId == type(IJBFundingCycleDataSource).interfaceId ||
            _interfaceId == type(IJBPayDelegate).interfaceId ||
            _interfaceId == type(IJBRedemptionDelegate).interfaceId;
    }

    constructor(
        uint256 _payoutbonus1,
        uint256 _payoutbonus2,
        uint256 _payoutbonus3,
        uint256 _bonusThreshold1,
        uint256 _bonusThreshold2,
        uint256 _bonusThreshold3
    ) {
        payoutbonus1 = _payoutbonus1;
        payoutbonus2 = _payoutbonus2;
        payoutbonus3 = _payoutbonus3;
        bonusThreshold1 = _bonusThreshold1;
        bonusThreshold2 = _bonusThreshold2;
        bonusThreshold3 = _bonusThreshold3;
    }

    /// @notice Initializes the clone contract with project details and a directory from which ecosystem payment terminals and controller can be found.
    /// @param _projectId The ID of the project this contract's functionality applies to.
    /// @param _directory The directory of terminals and controllers for projects.
    /// @param _deployMyDelegateData Data necessary to deploy the delegate.
    function initialize(
        uint256 _projectId,
        IJBDirectory _directory,
        DeployMyDelegateData memory _deployMyDelegateData
    ) external {
        // Stop re-initialization.
        if (projectId != 0) revert();

        // Store the basics.
        projectId = _projectId;
        directory = _directory;

        // Store the allow list.
        uint256 _numberOfAllowedAddresses = _deployMyDelegateData
            .allowList
            .length;
        for (uint256 _i; _i < _numberOfAllowedAddresses; ) {
            paymentFromAddressIsAllowed[
                _deployMyDelegateData.allowList[_i]
            ] = true;
            unchecked {
                ++_i;
            }
        }
    }

    /// @notice Received hook from the payment terminal after a payment.
    /// @dev Reverts if the calling contract is not one of the project's terminals.
    /// @param _data Standard Juicebox project payment data.
    function didPay(JBDidPayData calldata _data)
        external
        payable
        virtual
        override
    {
        // Make sure the caller is a terminal of the project, and that the call is being made on behalf of an interaction with the correct project.
        if (
            msg.value != 0 ||
            !directory.isTerminalOf(
                projectId,
                IJBPaymentTerminal(msg.sender)
            ) ||
            _data.projectId != projectId
        ) revert INVALID_PAYMENT_EVENT(msg.sender, _data.projectId, msg.value);

        // Make sure the address is on the allow list.
        if (!paymentFromAddressIsAllowed[_data.payer])
            revert PAYER_NOT_ON_ALLOWLIST(_data.payer);
    }

    /// @notice Received hook from the payment terminal after a redemption.
    /// @dev Reverts if the calling contract is not one of the project's terminals.
    /// @param _data Standard Juicebox project redemption data.
    function didRedeem(JBDidRedeemData calldata _data)
        external
        payable
        virtual
        override
    {
        // Make sure the caller is a terminal of the project, and that the call is being made on behalf of an interaction with the correct project.
        if (
            msg.value != 0 ||
            !directory.isTerminalOf(
                projectId,
                IJBPaymentTerminal(msg.sender)
            ) ||
            _data.projectId != projectId
        )
            revert INVALID_REDEMPTION_EVENT(
                msg.sender,
                _data.projectId,
                msg.value
            );
    }

    // Helper function to calculate the payout bonus based on the weight
    function getPayoutBonus(uint256 weight) private view returns (uint256) {
        if (weight >= bonusThreshold3) {
            return payoutbonus3;
        } else if (weight >= bonusThreshold2) {
            return payoutbonus2;
        } else if (weight >= bonusThreshold1) {
            return payoutbonus1;
        } else {
            return 100; // No bonus
        }
    }
}
