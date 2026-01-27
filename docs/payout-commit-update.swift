// Updated ProfileView - Add these changes to ContentView.swift

// 1. Add these @AppStorage variables to ProfileView (around line 957):
/*
    @AppStorage("missedGoalPayout") private var missedGoalPayout: Double = 0.0
    @AppStorage("payoutCommitted") private var payoutCommitted: Bool = false
    @AppStorage("committedPayoutAmount") private var committedPayoutAmount: Double = 0.0
*/

// 2. Add these @State variables (around line 959):
/*
    @State private var showPayoutSelector: Bool = false
*/

// 3. Replace the entire "Missed Goal Payout Amount" Section (lines 1295-1389) with:

                // Missed Goal Payout Amount - Separate prominent section
                Section {
                    // Show minimized bar if payout is committed
                    if payoutCommitted {
                        Button(action: {
                            showPayoutSelector.toggle()
                        }) {
                            HStack {
                                Image(systemName: "dollarsign.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(Color(UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 1)))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("$\(committedPayoutAmount, specifier: "%.2f") committed for payout")
                                        .font(.system(.body, design: .rounded, weight: .semibold))
                                        .foregroundStyle(Color.black)
                                    Text("Tap to change commitment")
                                        .font(.system(.caption, design: .rounded))
                                        .foregroundStyle(Color.black.opacity(0.6))
                                }
                                Spacer()
                                Image(systemName: showPayoutSelector ? "chevron.up" : "chevron.down")
                                    .font(.caption)
                                    .foregroundStyle(Color.black.opacity(0.4))
                            }
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // Show full selector if not committed or if expanded
                    if !payoutCommitted || showPayoutSelector {
                        VStack(spacing: 16) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Payout Amount")
                                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                                    Text("Amount sent per missed goal")
                                        .font(.system(.caption, design: .rounded))
                                        .foregroundStyle(Color.black.opacity(0.6))
                                }
                                Spacer()
                                HStack(spacing: 4) {
                                    Text("$")
                                        .font(.system(.title2, design: .rounded, weight: .bold))
                                        .foregroundStyle(Color(UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 1)))
                                    TextField("0.00", value: $missedGoalPayout, format: .number)
                                        .font(.system(.title2, design: .rounded, weight: .bold))
                                        .foregroundStyle(Color(UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 1)))
                                        .keyboardType(.decimalPad)
                                        .frame(width: 80)
                                        .multilineTextAlignment(.trailing)
                                        .focused($isPayoutAmountFocused)
                                        .toolbar {
                                            ToolbarItemGroup(placement: .keyboard) {
                                                Spacer()
                                                Button("Done") {
                                                    isPayoutAmountFocused = false
                                                }
                                                .font(.system(.body, design: .rounded, weight: .medium))
                                                .foregroundStyle(Color(UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 1)))
                                            }
                                        }
                                }
                            }
                            
                            // Quick select amounts
                            VStack(spacing: 12) {
                                HStack(spacing: 10) {
                                    ForEach([10.0, 50.0, 100.0], id: \.self) { amount in
                                        Button(action: { 
                                            missedGoalPayout = amount
                                            isPayoutAmountFocused = false // Dismiss keyboard
                                        }) {
                                            Text("$\(Int(amount))")
                                                .font(.system(.body, design: .rounded, weight: .semibold))
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 12)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 12)
                                                        .fill(missedGoalPayout == amount ? 
                                                            Color(UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 1)) : 
                                                            Color.gray.opacity(0.25))
                                                )
                                                .foregroundStyle(Color.black)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                
                                Button(action: { 
                                    // Focus on the text field and clear if it's a preset amount
                                    if missedGoalPayout == 10 || missedGoalPayout == 50 || missedGoalPayout == 100 {
                                        missedGoalPayout = 0 // Clear for new custom input
                                    }
                                    isPayoutAmountFocused = true // Show keyboard
                                }) {
                                    HStack {
                                        Image(systemName: "pencil.circle.fill")
                                            .font(.body)
                                        Text("Custom Amount")
                                            .font(.system(.body, design: .rounded, weight: .medium))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(missedGoalPayout != 10 && missedGoalPayout != 50 && missedGoalPayout != 100 && missedGoalPayout != 0 ? 
                                                Color(UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 1)) : 
                                                Color.gray.opacity(0.25))
                                    )
                                    .foregroundStyle(Color.black)
                                }
                                .buttonStyle(.plain)
                                
                                // Commit Button
                                Button(action: {
                                    commitPayout()
                                }) {
                                    HStack {
                                        Image(systemName: payoutCommitted && committedPayoutAmount == missedGoalPayout ? "checkmark.circle.fill" : "lock.fill")
                                            .font(.body)
                                        Text(payoutCommitted ? "Update Commitment" : "Commit Payout")
                                            .font(.system(.body, design: .rounded, weight: .bold))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color(UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 1)))
                                    )
                                    .foregroundStyle(Color.white)
                                }
                                .buttonStyle(.plain)
                                .disabled(missedGoalPayout <= 0)
                                .opacity(missedGoalPayout <= 0 ? 0.6 : 1.0)
                            }
                        }
                    }
                    .listRowBackground(Color.white)
                } header: {
                    Text("Missed Goal Payout")
                        .foregroundStyle(Color.white.opacity(0.95))
                } footer: {
                    Text(payoutCommitted ? 
                        "You have committed $\(committedPayoutAmount, specifier: "%.2f") per missed goal. This amount will be charged when you miss your daily objective." :
                        "This amount will be deducted from your balance and sent to your selected destination each time you miss your daily goal.")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.8))
                }

// 4. Add this function to ProfileView (before the closing bracket):

    private func commitPayout() {
        committedPayoutAmount = missedGoalPayout
        payoutCommitted = true
        showPayoutSelector = false
        isPayoutAmountFocused = false
        
        // Save to database
        saveProfile()
    }

// 5. Update the saveProfile() function to include committed payout amount:
// In the body dictionary (around line 1652), add:
/*
            "committedPayoutAmount": Int((committedPayoutAmount * 100).rounded()),
            "payoutCommitted": payoutCommitted,
*/