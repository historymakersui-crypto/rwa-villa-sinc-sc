# Villa RWA Smart Contract

This directory contains the Move smart contract for the Villa Real World Asset (RWA) management system on the Sui blockchain.

## Prerequisites

Before building and deploying the smart contract, ensure you have the following installed:

1. **Sui CLI** - Install the latest version from [Sui Documentation](https://docs.sui.io/build/install)
2. **Rust** - Required for Move development
3. **Linux Terminal** - For running CLI commands

## Installation

### 1. Install Sui CLI

```bash
# Install Sui CLI
curl -fLJO https://github.com/MystenLabs/sui/releases/download/testnet-v1.0.0/sui-testnet-v1.0.0-ubuntu-x86_64.tgz
tar -xzf sui-testnet-v1.0.0-ubuntu-x86_64.tgz
sudo mv sui /usr/local/bin/

# Verify installation
sui --version
```

### 2. Install Rust (if not already installed)

```bash
# Install Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source ~/.cargo/env

# Verify installation
rustc --version
```

## Configuration

### 1. Initialize Sui Project

```bash
# Navigate to the smart contract directory
cd smartcontract-move-sui

# Initialize a new Sui project
sui move new villa-rwa

# Copy the source files to the new project
cp sources/* villa-rwa/sources/
cp Move.toml villa-rwa/
```

### 2. Configure Environment

```bash
# Set up your Sui environment
sui client new-address ed25519

# Fund your address with testnet SUI
sui client faucet

# Check your address and balance
sui client addresses
sui client balance
```

## Building the Smart Contract

### 1. Build the Package

```bash
# Navigate to the project directory
cd villa-rwa

# Build the smart contract
sui move build
```

### 2. Verify Build

```bash
# Check for any compilation errors
sui move build --verbose

# If successful, you should see:
# "Build Successful"
```

## Deploying the Smart Contract

### 1. Deploy to Testnet

```bash
# Deploy the smart contract to Sui testnet
sui client publish --gas-budget 100000000

# Note the package ID and object IDs from the output
# Example output:
# Package ID: 0x1234567890abcdef...
# Object ID: 0xabcdef1234567890...
```

### 2. Deploy to Mainnet (Production)

```bash
# Switch to mainnet
sui client switch --env mainnet

# Deploy to mainnet
sui client publish --gas-budget 100000000
```

## Post-Deployment Configuration

### 1. Update Environment Variables

After successful deployment, update your backend environment variables:

```bash
# Update .env file in backend-villa-sinc
SUI_PACKAGE_ID=0x1234567890abcdef...  # Package ID from deployment
SUI_ADMIN_CAP_ID=0xabcdef1234567890...  # Admin Capability Object ID
SUI_APP_CAP_ID=0x9876543210fedcba...  # App Capability Object ID
```

### 2. Verify Deployment

```bash
# Check the deployed package
sui client object <PACKAGE_ID>

# Check admin capability
sui client object <ADMIN_CAP_ID>

# Check app capability
sui client object <APP_CAP_ID>
```

## Smart Contract Functions

### Available Functions

1. **`create_villa_project`** - Create a new villa project
2. **`create_villa_metadata`** - Create villa metadata
3. **`mint_villa_shares`** - Mint villa shares
4. **`transfer_villa_shares`** - Transfer villa shares
5. **`burn_villa_shares`** - Burn villa shares

### Function Parameters

- **Project Creation**: Requires admin capability
- **Villa Metadata**: Requires project ID and villa details
- **Share Minting**: Requires villa ID and share count
- **Share Transfer**: Requires share object ID and recipient address
- **Share Burning**: Requires share object ID

## Testing the Smart Contract

### 1. Run Tests

```bash
# Run Move tests
sui move test

# Run specific test
sui move test --filter test_create_villa_project
```

### 2. Test Functions

```bash
# Test project creation
sui client call --package <PACKAGE_ID> --module villa_dnft --function create_villa_project --args <ADMIN_CAP_ID> "Test Project" "Test Description" --gas-budget 10000000

# Test villa metadata creation
sui client call --package <PACKAGE_ID> --module villa_dnft --function create_villa_metadata --args <PROJECT_ID> "Villa 1" "Villa Description" "image_url" "Location" 100 1000000 --gas-budget 10000000
```

## Troubleshooting

### Common Issues

1. **Build Errors**
   ```bash
   # Check Move.toml configuration
   cat Move.toml
   
   # Verify source files
   ls -la sources/
   ```

2. **Deployment Errors**
   ```bash
   # Check gas balance
   sui client balance
   
   # Increase gas budget
   sui client publish --gas-budget 200000000
   ```

3. **Permission Errors**
   ```bash
   # Verify admin capability
   sui client object <ADMIN_CAP_ID>
   
   # Check object ownership
   sui client object <OBJECT_ID>
   ```

### Getting Help

- **Sui Documentation**: [https://docs.sui.io/](https://docs.sui.io/)
- **Move Language**: [https://move-language.github.io/move/](https://move-language.github.io/move/)
- **Sui Discord**: [https://discord.gg/sui](https://discord.gg/sui)

## Security Considerations

1. **Private Keys**: Never commit private keys to version control
2. **Gas Budget**: Set appropriate gas budgets for transactions
3. **Capabilities**: Secure admin and app capabilities
4. **Testing**: Thoroughly test on testnet before mainnet deployment

## License

This smart contract is part of the Villa RWA management system. Please refer to the main project license for usage terms.

## Support

For technical support or questions about this smart contract, please refer to the main project documentation or contact the development team.
