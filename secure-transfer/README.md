# Conditional Payment Smart Contract

## About
This smart contract implements a flexible conditional payment system on the Stacks blockchain. It allows users to create, manage, and execute payments that are released only when specific conditions are met. The contract supports multiple payment types (STX and tokens), batch operations, escrow functionality, and customizable verification conditions.

## Features

### Core Functionality
- **Conditional Payments**: Create payments that only execute when predefined conditions are met
- **Multi-Token Support**: Handle both STX and SIP-010 token payments
- **Escrow System**: Optional trusted third-party verification
- **Batch Processing**: Create multiple payments in a single transaction
- **Expiration Mechanism**: Automatic payment expiration after a specified block height
- **Transaction History**: Track user payment history
- **Confirmation System**: Optional multi-party confirmation requirement

### Security Features
- **Role-Based Access Control**: Administrative functions restricted to contract owner
- **Condition Verification**: External contract-based condition verification
- **Payment Status Tracking**: Prevent double-claiming of payments
- **Escrow Agent Registry**: Verified escrow agents only

## Contract Structure

### Data Storage
```clarity
payment-records: Stores all payment transaction details
user-transaction-counter: Tracks number of transactions per user
payment-confirmation-status: Records confirmation status for transactions
user-transaction-history: Maintains user transaction history
registered-escrow-agents: Lists approved escrow agents
```

### Error Codes
- `ERR-UNAUTHORIZED-ACCESS (u1)`: Caller lacks required permissions
- `ERR-PAYMENT-RECORD-NOT-FOUND (u2)`: Referenced payment doesn't exist
- `ERR-PAYMENT-ALREADY-CLAIMED (u3)`: Payment has already been claimed
- `ERR-PAYMENT-CONDITIONS-NOT-MET (u4)`: Conditions for payment release not satisfied
- `ERR-PAYMENT-EXPIRED (u5)`: Payment has expired
- `ERR-INVALID-PAYMENT-AMOUNT (u6)`: Invalid payment amount specified
- `ERR-INVALID-TOKEN-CONTRACT (u7)`: Invalid token contract address
- `ERR-INVALID-ESCROW-AGENT (u8)`: Unregistered escrow agent
- `ERR-BATCH-OPERATION-FAILED (u9)`: Batch payment operation failed
- `ERR-INSUFFICIENT-TOKEN-BALANCE (u10)`: Insufficient token balance

## Usage Guide

### Creating a Payment

```clarity
(create-conditional-payment 
    recipient-address 
    payment-amount 
    token-contract-address ;; optional
    condition-contract-address 
    condition-function-name
    expiration-block-height
    escrow-agent-address ;; optional
    requires-confirmation
    payment-metadata ;; optional
)
```

#### Parameters:
- `recipient-address`: Principal to receive the payment
- `payment-amount`: Amount to be transferred
- `token-contract-address`: Optional SIP-010 token contract address (none for STX)
- `condition-contract-address`: Contract containing verification logic
- `condition-function-name`: Function name for condition verification
- `expiration-block-height`: Block height at which payment expires
- `escrow-agent-address`: Optional escrow agent principal
- `requires-confirmation`: Boolean for confirmation requirement
- `payment-metadata`: Optional transaction metadata

### Claiming a Payment

```clarity
(claim-conditional-payment transaction-id)
```

Requirements:
1. Caller must be the designated beneficiary
2. Payment must not be expired
3. Payment must not be already claimed
4. All conditions must be met
5. Required confirmations must be provided

### Confirming a Transaction

```clarity
(confirm-transaction transaction-id)
```

Can be called by:
- Payment initiator
- Designated escrow agent (if any)

### Batch Operations

```clarity
(create-multiple-payments 
    recipient-addresses
    payment-amounts 
    condition-contract-address 
    condition-function-name
)
```

Creates multiple payments in a single transaction (max 20 payments).

### Query Functions

#### Get Transaction Details
```clarity
(get-transaction-details transaction-id)
```

#### Get User Transactions
```clarity
(get-user-transactions user-address)
```

#### Check Confirmation Status
```clarity
(get-transaction-confirmation-status transaction-id confirming-party)
```

#### Verify Escrow Agent
```clarity
(verify-escrow-agent-status agent-address)
```

## Administrative Functions

### Transfer Contract Ownership
```clarity
(transfer-contract-ownership new-administrator-address)
```

### Register Escrow Agent
```clarity
(register-new-escrow-agent agent-address)
```

## Security Considerations

1. **Condition Verification**
   - Always implement robust verification logic in external contracts
   - Consider timeouts for condition checking
   - Validate all inputs thoroughly

2. **Token Handling**
   - Verify token contract compliance with SIP-010
   - Ensure sufficient balance before creating payments
   - Handle token decimal places correctly

3. **Access Control**
   - Maintain strict control over escrow agent registration
   - Regularly audit administrative actions
   - Implement proper principal validation

4. **Expiration Management**
   - Set appropriate expiration timeframes
   - Consider block time variations
   - Include cleanup mechanisms for expired payments

## Best Practices

1. **Payment Creation**
   - Set reasonable expiration times
   - Use escrow for high-value transactions
   - Include relevant metadata for tracking

2. **Condition Design**
   - Keep condition logic simple and deterministic
   - Include failure recovery mechanisms
   - Document condition requirements clearly

3. **Batch Operations**
   - Limit batch sizes appropriately
   - Verify all recipients before submission
   - Include proper error handling

4. **Transaction Management**
   - Monitor transaction histories regularly
   - Implement proper logging mechanisms
   - Maintain clear audit trails