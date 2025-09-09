#!/bin/bash
echo "🔍 Getting Smart Contract Deployment Information..."

# Get wallet address
WALLET_ADDRESS=$(sui client active-address)
echo "�� Wallet Address: $WALLET_ADDRESS"

# Get all objects for this wallet
echo "📦 Getting all objects..."
sui client objects $WALLET_ADDRESS --json > objects.json

# Find package ID from UpgradeCap objects
echo "🔍 Looking for Package ID..."
PACKAGE_ID=$(cat objects.json | jq -r '.[] | select(.objectType | contains("UpgradeCap")) | .objectId' | head -1)
echo "📦 Package ID: $PACKAGE_ID"

# Get package details
if [ ! -z "$PACKAGE_ID" ]; then
    echo "�� Package Details:"
    sui client object $PACKAGE_ID
fi

# Get private key
echo "🔑 Getting private key..."
sui client keytool export --key-id 0 --key-scheme ed25519

echo "✅ Information gathering complete!"