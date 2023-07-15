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
/// @dev This example implementation confines payments to an allow list.
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

    // Tiered Bonus System
    struct Tier {
        uint256 bonusPercentage;
        uint256 minContribution;
        uint256 maxContribution;
    }

    Tier[] public bonusTiers;

    /// @notice Addresses allowed to make payments to the treasury.
    mapping(address => bool) public paymentFromAddressIsAllowed;

    /// @notice This function gets called when the project receives a payment.
    /// @dev Part of IJBFundingCycleDataSource.
    /// @dev This implementation just sets this contract up to receive a `didPay` call.
    /// @param _data The Juicebox standard project payment data.
    /// @return weight The weight that project tokens should get minted relative to.
    /// @return memo A memo to be forwarded to the event.
    /// @return delegateAllocations Amount to be sent to delegates instead of adding to local balance.
    function payParams(JBPayParamsData calldata _data)
        external
        view
        virtual
        override
        returns (
            uint256 weight,
            string memory memo,
            JBPayDelegateAllocation[] memory delegateAllocations
        )
    {
        // Determine the weight based on contribution
        weight = calculateWeight(_data.weight);
        memo = _data.memo;

        // Add `this` contract as a Pay Delegate so that it receives a `didPay` call. Don't send any funds to the delegate (keep all funds in the treasury).
        delegateAllocations = new JBPayDelegateAllocation[](1);
        delegateAllocations[0] = JBPayDelegateAllocation(this, 0);
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
        reclaimAmount = _data.reclaimAmount.value;
        memo = _data.memo;

        // Add `this` contract as a Redeem Delegate so that it receives a `didRedeem` call. Don't send any extra funds to the delegate.
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
            _interfaceId ==
                type(IJBFundingCycleDataSource).interfaceId ||
            _interfaceId == type(IJBPayDelegate).interfaceId ||
            _interfaceId == type(IJBRedemptionDelegate).interfaceId;
    }

    constructor(Tier[] memory _bonusTiers) {
        bonusTiers = _bonusTiers;
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
    /// @dev This example implementation reverts if the payer isn't on the allow list.
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

    /// @dev Calculates the weight based on the contribution amount.
    function calculateWeight(uint256 contributionAmount)
        private
        view
        returns (uint256)
    {
        for (uint256 i = 0; i < bonusTiers.length; i++) {
            if (
                contributionAmount >= bonusTiers[i].minContribution &&
                contributionAmount <= bonusTiers[i].maxContribution
            ) {
                return contributionAmount * bonusTiers[i].bonusPercentage / 100;
            }
        }

        // If the contribution doesn't fall within any tier, return the default weight.
        return contributionAmount;
    }

    /// @notice Sets the bonus tiers for the tiered bonus system.
    /// @param _bonusTiers The array of bonus tiers.
    function setBonusTiers(Tier[] memory _bonusTiers) external {
        bonusTiers = _bonusTiers;
    }
}
