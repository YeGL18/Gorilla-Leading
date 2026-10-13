import SwiftUI
import UIKit

enum GorillaPageLayout {
    static func showsTab(isPhone: Bool, windowSize: CGSize) -> Bool {
        isPhone && min(windowSize.width, windowSize.height) >= 560
            && windowSize.width > windowSize.height
    }
}

enum GorillaBrand {
    static let darkKnightGold = UIColor(red: 1, green: 196.0 / 255.0, blue: 109.0 / 255.0, alpha: 1)

    static let tabIcon: UIImage = {
        let size = CGSize(width: 28, height: 28)
        return UIGraphicsImageRenderer(size: size).image { _ in
            guard let image = UIImage(named: "GorillaWatermark") else { return }
            let scale = min(size.width / image.size.width, size.height / image.size.height)
            let width = image.size.width * scale
            let height = image.size.height * scale
            image.draw(in: CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2,
                                  width: width, height: height))
        }.withRenderingMode(.alwaysTemplate)
    }()

    static let goldTabIcon: UIImage = {
        let size = tabIcon.size
        return UIGraphicsImageRenderer(size: size).image { renderer in
            let context = renderer.cgContext
            let rect = CGRect(origin: .zero, size: size)
            tabIcon.draw(in: rect)
            context.setBlendMode(.sourceIn)
            // Soften both the body and highlights, not just the gradient's edges.
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            darkKnightGold.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            func paleGold(whiteMix: CGFloat, opacity: CGFloat) -> UIColor {
                UIColor(red: red + (1 - red) * whiteMix,
                        green: green + (1 - green) * whiteMix,
                        blue: blue + (1 - blue) * whiteMix, alpha: opacity)
            }
            let body = paleGold(whiteMix: 0.55, opacity: 0.75)
            let highlight = paleGold(whiteMix: 0.80, opacity: 0.85)
            let colors = [highlight.cgColor, body.cgColor, highlight.cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                            colors: colors, locations: [0, 0.55, 1]) else { return }
            context.drawLinearGradient(gradient, start: .zero,
                                       end: CGPoint(x: size.width, y: size.height), options: [])
        }.withRenderingMode(.alwaysOriginal)
    }()
}

struct GorillaPageView: View {
    var body: some View {
        Color(uiColor: .systemGroupedBackground)
            .ignoresSafeArea()
            .navigationTitle("Gorilla")
    }
}
