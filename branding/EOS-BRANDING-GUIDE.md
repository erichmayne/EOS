# EOS Branding Guide

## Branding Assets (in /branding directory)

### Logo Files
- `eos-logo-backup.png` - Main logo with angel/sun imagery (454KB)
- `eos-logo-backup.svg` - Vector logo (1.8KB)  
- `eos-app-icon-backup.png` - iOS app icon (143KB)
- `eos-app-icon-original-backup.png` - Original iOS app icon (91KB)

### EOS Gradient Text Files  
- `eos-gradient-text.svg` - EOS text with gradient (white background)
- `eos-gradient-text-transparent.svg` - EOS text with gradient (transparent)
- `eos-gradient-text.html` - Interactive HTML with multiple sizes
  - Open in browser to view/screenshot the gradient text
  - Contains Large (200px), Medium (100px), and Small (42px) versions

## Text Styling (from iOS App)

### Main EOS Title
- **Font:** System, Size 42, Bold, Rounded design
- **Gradient:** Linear gradient from Black to Gold
  - Start: `#000000` (Black)
  - End: `#D9A600` (Gold - RGB: 0.85, 0.65, 0)
  - Direction: Leading to Trailing (left to right)

### Swift Code for Gradient Text:
```swift
Text("EOS")
    .font(.system(size: 42, weight: .bold, design: .rounded))
    .foregroundStyle(
        LinearGradient(
            colors: [
                Color.black, 
                Color(UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 1))
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    )
```

## Brand Colors

### Primary Colors
- **Black:** `#000000`
- **Gold:** `#D9A600` or `rgb(217, 166, 0)` or `UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 1)`
- **Light Gold:** `#F2BF1A` or `UIColor(red: 0.95, green: 0.75, blue: 0.1, alpha: 1)`

### Button Gradient
```swift
LinearGradient(
    colors: [
        Color(UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 1)),
        Color(UIColor(red: 0.95, green: 0.75, blue: 0.1, alpha: 1))
    ],
    startPoint: .leading,
    endPoint: .trailing
)
```

### Shadow Color
- Gold shadow with 30% opacity: `Color(UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 0.3))`

## Usage Contexts
- **App Name:** EOS (formerly "morning-would")
- **Product Name in Xcode:** EOS
- **Bundle ID:** com.emayne.morning-would
- **Marketing Name:** Eos

## Typography
- Primary font family: System font with rounded design variant
- Weights used: Bold (for titles), Medium (for buttons), Regular (for body text)

## Files Location Reference
- Server logos: `/var/www/invite/` (on server at 159.26.94.94)
- iOS app icons: `/morning-would/Assets.xcassets/AppIcon.appiconset/`
- Backup location on server: `~/eos-branding-backup/`
- Local backups: `/Users/emayne/morning-would/`
