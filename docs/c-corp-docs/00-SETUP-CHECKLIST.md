# RunMatch, Inc. — Post-Incorporation Setup Checklist

**Status:** Certificate of Incorporation filed with Delaware via Northwest Registered Agent
**Next Step:** Get EIN from IRS

---

## Step 1: Get Your EIN from the IRS ⬜

**URL:** https://www.irs.gov/businesses/small-businesses-self-employed/apply-for-an-employer-identification-number-ein-online

**Hours:** Monday–Friday, 7am–10pm Eastern only. Does not work on weekends.

**What you'll enter:**

| Field | Value |
|---|---|
| Legal name | RunMatch, Inc. |
| Type of entity | Corporation |
| State of incorporation | Delaware |
| Date of incorporation | *(use the filing date from your Delaware confirmation)* |
| Reason for applying | Started a new business |
| Responsible party | Erich Mayne |
| Your SSN | *(required to verify you as responsible party)* |
| Business address | *(your personal address)* |
| Type of activity | Other → "Software / Technology" or "Fitness Services" |
| Expected employees | 0 |

**Cost:** Free

**Result:** You get your EIN immediately on screen. **Download and save the confirmation letter PDF.** You will need this for the bank account.

---

## Step 2: Open a Bank Account ⬜

**Recommended:** Mercury (mercury.com) — online, startup-friendly, free, no branch visit required.

**What you need to upload:**

1. Filed Certificate of Incorporation (from Delaware / Northwest)
2. EIN confirmation letter (from Step 1)
3. Signed Board Consent — sign and date `03-organizational-board-consent.md`, scan or photograph it

**Process:** Apply online at mercury.com. Approval is typically same-day or next business day. Once approved, you'll have a routing number and account number.

---

## Step 3: Sign Bylaws ⬜

1. Open `02-bylaws.md`
2. Fill in the date at the top and in the certificate at the bottom
3. Sign the certificate at the bottom
4. Save a signed copy (digital or print) in your corporate records

This is purely internal — just your record that the company's operating rules are in place.

---

## Step 4: Sign the Board Consent ⬜

1. Open `03-organizational-board-consent.md`
2. Fill in dates throughout (use your incorporation date or the same day you're signing)
3. Sign both sections (Incorporator Consent and Director Consent)
4. Save a signed copy in your corporate records

This formally: elects you as President/Secretary/Treasurer, sets fiscal year to Dec 31, authorizes your founder shares, confirms Northwest as registered agent, and authorizes banking + payment processor setup.

---

## Step 5: Buy Your Founder Shares ⬜

1. Transfer **$800.00** from your personal account into the RunMatch, Inc. bank account (from Step 2)
2. Open `04-founder-stock-purchase-agreement.md`
3. Fill in the date (this becomes your "Date of Grant" — your vesting clock starts here)
4. Sign both signature blocks (as President of RunMatch AND as the Purchaser)
5. If married, have your spouse sign the Spousal Consent section. If not married, ignore it.
6. Save a signed copy in your corporate records

**The $800 is real money.** You are buying 8,000,000 shares at $0.0001 each. This is a legitimate purchase, not a formality. The transfer from your personal account to the company account is the payment.

---

## Step 6: File 83(b) Election with the IRS ⬜ ⚠️ DEADLINE: 30 DAYS FROM STEP 5

**This is the most critical step. There are NO extensions. If you miss the 30-day window, it cannot be fixed.**

### Prepare the form

1. Open `05-83b-election.md`
2. Fill in:
   - Your address
   - Your Social Security Number
   - The transfer date (same date as your Stock Purchase Agreement from Step 5)
3. Print **3 copies**
4. Sign all 3 copies

### Mail to the IRS

5. Look up your IRS Service Center based on your state of residence:
   https://www.irs.gov/filing/where-to-file-paper-tax-returns-with-or-without-a-payment

6. Go to the post office and send **1 signed copy** to your IRS Service Center via:
   - **Certified mail** (get the receipt)
   - **Return receipt requested** (the green card — this is your proof of timely filing)

7. Cost: ~$7 for certified mail + return receipt

### Keep your records

8. Keep **1 signed copy** for yourself in a safe place
9. Put **1 signed copy** in the RunMatch corporate records (with the Stock Purchase Agreement)
10. **Keep the certified mail receipt and the green return receipt card forever.** This is your only proof of timely filing if the IRS ever asks.

### At tax time

11. Attach a copy of the 83(b) election to your 2026 federal income tax return
12. Check if your state requires a copy with your state return as well (consult your accountant)

---

## Step 7: Publish Legal Docs ⬜

These three docs need to be live on your website and linked in the app:

| Document | Suggested URL | Source |
|---|---|---|
| Terms of Service | `live-eos.com/terms` | `06-terms-of-service.md` |
| Privacy Policy | `live-eos.com/privacy` | `07-privacy-policy.md` |
| Acceptable Use Policy | `live-eos.com/acceptable-use` | `08-acceptable-use-policy.md` |

**Before publishing:**
- Fill in all dates (Effective Date and Last Updated)
- Decide if you're keeping `live-eos.com` / `connect@live-eos.com` or switching to a RunMatch domain
- Apple requires a Privacy Policy link for App Store — update your App Store listing if the URL changes

**Update references in the app:**
- `ContentView.swift` links to `https://live-eos.com/terms` — update if URL changes
- Competition rules disclaimer mentions "processed through Stripe" — update to Braintree/PayPal when you migrate

---

## Summary

| # | Step | Status | Deadline |
|---|---|---|---|
| 0 | File Certificate of Incorporation | ✅ Done | — |
| 1 | Get EIN from IRS | ⬜ | Now (next business day) |
| 2 | Open bank account (Mercury) | ⬜ | After Step 1 |
| 3 | Sign Bylaws | ⬜ | Same day as Step 2 |
| 4 | Sign Board Consent | ⬜ | Same day as Step 2 |
| 5 | Buy founder shares ($800 transfer + sign agreement) | ⬜ | After bank account is open |
| 6 | File 83(b) election | ⬜ | **30 days from Step 5 — NO EXCEPTIONS** |
| 7 | Publish Terms, Privacy Policy, AUP on website | ⬜ | Before next app update |

---

## Corporate Records Folder

When you're done, your `c-corp-docs` folder should contain signed copies of:

```
c-corp-docs/
├── 00-SETUP-CHECKLIST.md          ← this file
├── 01-certificate-of-incorporation.md   ← filed with Delaware (keep a copy)
├── 02-bylaws.md                   ← signed
├── 03-organizational-board-consent.md   ← signed
├── 04-founder-stock-purchase-agreement.md  ← signed
├── 05-83b-election.md             ← signed, mailed, receipt saved
├── 06-terms-of-service.md         ← published on website
├── 07-privacy-policy.md           ← published on website
├── 08-acceptable-use-policy.md    ← published on website
└── EIN-confirmation.pdf           ← downloaded from IRS
```

Keep scanned/photographed signed copies alongside the markdown files. If you ever raise money, a lawyer will ask for all of these during due diligence.
