//
//  SplashView.swift
//  EOS
//
//  Created on 1/7/26.
//

import SwiftUI

struct SplashView: View {
    @State private var logoOpacity = 0.0
    @State private var taglineOpacity = 0.0
    @State private var logoScale = 0.8
    @State private var taglineScale = 0.95
    @State private var logoOffset: CGFloat = 0
    @Binding var isShowingSplash: Bool
    
    var body: some View {
        ZStack {
            // White background
            Color.white
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 20) {
                // EOS Logo - Will migrate to top
                Image("eos logo final_original")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                    .opacity(logoOpacity)
                    .scaleEffect(logoScale)
                    .offset(y: logoOffset)
                
                // EOS Text with gradient
                Text("EOS")
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.black, Color(UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 1))],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .opacity(logoOpacity)
                    .scaleEffect(logoScale)
                    .offset(y: logoOffset)
                
                // Do or Donate tagline
                Text("Do or Donate")
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 0.8)), Color(UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 1))],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .opacity(taglineOpacity)
                    .scaleEffect(taglineScale)
            }
        }
        .onAppear {
            // Smoother fade in animations
            withAnimation(.easeInOut(duration: 0.8)) {
                logoOpacity = 1.0
                logoScale = 1.0
            }
            
            withAnimation(.easeInOut(duration: 0.8).delay(0.4)) {
                taglineOpacity = 1.0
                taglineScale = 1.0
            }
            
            // Start exit animations after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                // Fade out tagline smoothly
                withAnimation(.easeInOut(duration: 0.7)) {
                    taglineOpacity = 0.0
                    taglineScale = 0.95
                }
                
                // Move logo to top position matching home screen exactly
                withAnimation(.easeInOut(duration: 0.9).delay(0.3)) {
                    // Precisely calculated to prevent jumping
                    let screenHeight = UIScreen.main.bounds.height
                    // Adjusted for exact alignment - accounts for nav bar + status bar + padding
                    // Fine-tuned to eliminate jumping on transition
                    let hasNotch = screenHeight > 800 // iPhone X and newer
                    let finalTopPosition: CGFloat = hasNotch ? 118 : 112
                    logoOffset = -(screenHeight / 2 - finalTopPosition)
                    logoScale = 0.583 // Match home screen size exactly
                }
                
                // Smoother transition to main app - timed to complete just as text reaches position
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isShowingSplash = false
                    }
                }
            }
        }
    }
}

// Version with logo image
struct SplashViewWithLogo: View {
    @State private var logoOpacity = 0.0
    @State private var textOpacity = 0.0
    @State private var taglineOpacity = 0.0
    @State private var logoScale = 0.85
    @State private var textScale = 0.9
    @State private var taglineScale = 0.9
    @State private var logoOffset: CGFloat = 0
    @State private var textOffset: CGFloat = 0
    @Binding var isShowingSplash: Bool
    
    private let goldColor = Color(UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 1))
    
    var body: some View {
        ZStack {
            // White background
            Color.white
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 35) {
                Spacer()
                
                // Logo Image - Bigger
                Image("EOSLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 180, height: 180)
                    .opacity(logoOpacity)
                    .scaleEffect(logoScale)
                    .offset(y: logoOffset)
                
                // EOS Text with gradient matching home screen
                Text("EOS")
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.black, goldColor],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .opacity(textOpacity)
                    .scaleEffect(textScale)
                    .offset(y: textOffset)
                
                // Do or Donate tagline - Bigger
                Text("Do or Donate")
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [goldColor.opacity(0.8), goldColor],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .opacity(taglineOpacity)
                    .scaleEffect(taglineScale)
                
                Spacer()
                Spacer()
            }
        }
        .onAppear {
            // Smoother fade in animations with longer duration
            withAnimation(.easeInOut(duration: 0.8)) {
                logoOpacity = 1.0
                logoScale = 1.0
            }
            
            withAnimation(.easeInOut(duration: 0.8).delay(0.3)) {
                textOpacity = 1.0
                textScale = 1.0
            }
            
            withAnimation(.easeInOut(duration: 0.8).delay(0.5)) {
                taglineOpacity = 1.0
                taglineScale = 1.0
            }
            
            // Start exit animations after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                // Fade out tagline and logo smoothly
                withAnimation(.easeInOut(duration: 0.7)) {
                    taglineOpacity = 0.0
                    taglineScale = 0.95
                    logoOpacity = 0.0
                    logoScale = 0.95
                }
                
                // Move text to top position matching home screen exactly
                withAnimation(.easeInOut(duration: 0.9).delay(0.3)) {
                    // Precisely calculated to prevent jumping
                    let screenHeight = UIScreen.main.bounds.height
                    // Account for different device types (with/without notch)
                    let hasNotch = screenHeight > 800
                    let finalTopPosition: CGFloat = hasNotch ? 118 : 112
                    textOffset = -(screenHeight / 2 - finalTopPosition)
                    textScale = 0.583  // 42/72 = 0.583 to match exact home screen font size
                }
                
                // Smoother transition to main app - timed to complete just as text reaches position
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isShowingSplash = false
                    }
                }
            }
        }
    }
}

// Alternative version with just text (no image)
struct SplashViewTextOnly: View {
    @State private var logoOpacity = 0.0
    @State private var taglineOpacity = 0.0
    @State private var logoScale = 0.8
    @State private var taglineScale = 0.95
    @State private var logoOffset: CGFloat = 0
    @Binding var isShowingSplash: Bool
    
    private let goldColor = Color(UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 1))
    
    var body: some View {
        ZStack {
            // White background
            Color.white
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 30) {
                Spacer()
                
                // EOS Text Logo with gradient
                Text("EOS")
                    .font(.system(size: 80, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.black, goldColor],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .opacity(logoOpacity)
                    .scaleEffect(logoScale)
                    .offset(y: logoOffset)
                
                // Do or Donate tagline
                Text("Do or Donate")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [goldColor.opacity(0.8), goldColor],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .opacity(taglineOpacity)
                    .scaleEffect(taglineScale)
                
                Spacer()
                Spacer() // Extra spacer to center content slightly above center
            }
        }
        .onAppear {
            // Smoother fade in animations
            withAnimation(.easeInOut(duration: 0.8)) {
                logoOpacity = 1.0
                logoScale = 1.0
            }
            
            withAnimation(.easeInOut(duration: 0.8).delay(0.4)) {
                taglineOpacity = 1.0
                taglineScale = 1.0
            }
            
            // Start exit animations after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                // Fade out tagline smoothly
                withAnimation(.easeInOut(duration: 0.7)) {
                    taglineOpacity = 0.0
                    taglineScale = 0.95
                }
                
                // Move logo to top position matching ContentView exactly
                withAnimation(.easeInOut(duration: 0.9).delay(0.3)) {
                    // Precisely calculated to prevent jumping
                    let screenHeight = UIScreen.main.bounds.height
                    let hasNotch = screenHeight > 800
                    let finalTopPosition: CGFloat = hasNotch ? 118 : 112
                    logoOffset = -(screenHeight / 2 - finalTopPosition)
                    logoScale = 0.525 // Match size in navigation
                }
                
                // Smoother transition to main app - timed to complete just as text reaches position
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isShowingSplash = false
                    }
                }
            }
        }
    }
}

struct SplashView_Previews: PreviewProvider {
    static var previews: some View {
        SplashViewTextOnly(isShowingSplash: .constant(true))
    }
}
