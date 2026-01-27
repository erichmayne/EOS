# Apple Pay Setup Instructions for EOS

## ✅ What's Already Done:
1. **Code Updates**: Added Apple Pay configuration to the Stripe PaymentSheet
2. **Entitlements File**: Created with merchant ID
3. **Info.plist**: Added URL scheme for Stripe redirects
4. **UI Improvements**: Fixed payout amount selectors ($10, $50, $100, Custom)

## 🎯 What You Need to Do in Xcode:

### Step 1: Add Entitlements File to Project
1. In Xcode, select the project navigator (folder icon)
2. Right-click on the "morning-would" folder
3. Select "Add Files to 'Eos'"
4. Select the `Entitlements.entitlements` file we created
5. Make sure "Copy items if needed" is unchecked (it's already in the folder)
6. Click "Add"

### Step 2: Configure Project Settings
1. Select your project in the navigator (blue icon at top)
2. Select the "EOS" target
3. Go to the "Signing & Capabilities" tab
4. Click the "+" button to add a capability
5. Search for and add "Apple Pay"
6. Check the box for "Apple Pay Payment Processing"

### Step 3: Set Entitlements File
1. Still in the "EOS" target
2. Go to the "Build Settings" tab
3. Search for "entitlements"
4. Set "Code Signing Entitlements" to: `morning-would/Entitlements.entitlements`

## 💳 Apple Pay Features Now Available:

### For Users:
- **Auto-populated Cards**: If users have cards in Apple Wallet, they'll appear automatically
- **Touch/Face ID**: Quick authentication for payments
- **Saved Cards**: Previously used cards are remembered (if customer ID is consistent)
- **Apple Cash**: Users can use their Apple Cash balance directly

### What Apple Pay Enables:
1. **Faster Checkout**: One-touch payment with Face/Touch ID
2. **Saved Payment Methods**: Cards are automatically saved to the customer
3. **Security**: Uses device authentication and tokenization
4. **Apple Cash Support**: Direct use of Apple Cash balance

## 🔧 Testing Apple Pay:

### On Simulator:
- Apple Pay will show but won't process real payments
- Use Stripe test cards for testing

### On Physical Device:
1. Must have a valid Apple Developer account
2. Device must have cards added to Wallet
3. Use Stripe test mode first, then switch to live

## 📱 How It Works in the App:

1. User taps "Deposit"
2. Stripe Payment Sheet opens with:
   - Apple Pay button (if available)
   - Saved cards (if any)
   - Add new card option
3. For Apple Pay: One touch → Face/Touch ID → Done!
4. Cards are automatically saved for future deposits

## 🎨 UI Improvements Made:

### Payout Amount Selector:
- Changed from cramped $5/$10/$25/$50 to spacious $10/$50/$100
- Custom button is now full-width with an icon
- Better visual hierarchy with gold highlighting
- Responsive button sizing
- Default custom value: $25

The deposit system now supports the full Apple Pay experience, including Apple Cash!