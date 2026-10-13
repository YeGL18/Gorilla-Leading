import XCTest
import SwiftUI
import Darwin
@testable import GorillaTranslate

@MainActor final class OrbRenderingTests: XCTestCase {
    private let fills: [Color] = [.yellow.opacity(0.315), .cyan.opacity(0.315), .blue.opacity(0.315)]

    private func reference(elapsed: Double, size: CGSize, mixing: Bool, multiplier: CGFloat, palette: [Color]? = nil) -> some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                Circle().fill((palette ?? self.fills)[index]).blur(radius: 100)
                    .frame(width: [450.0, 500.0, 420.0][index] * multiplier,
                           height: [450.0, 500.0, 420.0][index] * multiplier)
                    .offset(x: LegacyOrbField.offsets(at: elapsed, size: size)[index].x,
                            y: LegacyOrbField.offsets(at: elapsed, size: size)[index].y)
                    .blendMode(mixing ? .plusLighter : .normal)
            }
        }.compositingGroup().frame(width: size.width, height: size.height)
    }

    private func render<V: View>(_ view: V, size: CGSize, name: String) throws -> [UInt8] {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height).clipped())
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.uiImage)
        let data = try XCTUnwrap(image.pngData())
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let cgImage = try XCTUnwrap(image.cgImage)
        var bytes = [UInt8](repeating: 0, count: cgImage.width * cgImage.height * 4)
        let context = try XCTUnwrap(CGContext(data: &bytes, width: cgImage.width, height: cgImage.height,
            bitsPerComponent: 8, bytesPerRow: cgImage.width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(cgImage, in: CGRect(origin: .zero, size: size))
        return bytes
    }

    func testLegacyOrbVisualParity() throws {
        for (size, multiplier) in [(CGSize(width: 390, height: 844), CGFloat(1)),
                                   (CGSize(width: 844, height: 540), CGFloat(2))] {
            for mixing in [false, true] {
                for elapsed in [0.0, 7.5, 37.0] {
                    let original = try render(reference(elapsed: elapsed, size: size, mixing: mixing,
                        multiplier: multiplier).background(Color.gray), size: size, name: "original-\(size)-\(mixing)-\(elapsed)")
                    let optimized = try render(LegacyOrbField(elapsed: elapsed, fills: fills,
                        multiplier: multiplier, mixing: mixing).background(Color.gray),
                        size: size, name: "native-\(size)-\(mixing)-\(elapsed)")
                    let error = zip(original, optimized).reduce(0.0) { $0 + abs(Double($1.0) - Double($1.1)) } / Double(original.count)
                    print("Orb visual mean channel error: \(size), mixing=\(mixing), elapsed=\(elapsed): \(error)")
                    let center = (Int(size.height) / 2 * Int(size.width) + Int(size.width) / 2) * 4
                    print("Orb center original=\(Array(original[center..<center+4])), native=\(Array(optimized[center..<center+4]))")
                    XCTAssertEqual(original, optimized, "Native positions, blur tails, alpha and blend must match exactly")
                    XCTAssertGreaterThan(Set(optimized).count, 20, "Native orbs must not be blank")
                }
            }
        }
    }

    func testNativeDarkPaletteParity() throws {
        let size = CGSize(width: 390, height: 844)
        let palette = [Color(hex: "BEBC3F").opacity(0.48), Color(hex: "5CAEB7").opacity(0.48),
                       Color(hex: "0098FF").opacity(0.48)]
        for mixing in [false, true] {
            let baseline = try render(reference(elapsed: 37, size: size, mixing: mixing,
                multiplier: 1, palette: palette).background(Color.black),
                size: size, name: "native-dark-reference-\(mixing)")
            let restored = try render(LegacyOrbField(elapsed: 37, fills: palette,
                multiplier: 1, mixing: mixing).background(Color.black),
                size: size, name: "native-dark-restored-\(mixing)")
            XCTAssertEqual(baseline, restored, "Restoring native blur must not alter the palette or add noise")
        }
    }

    func testDisabledCanvasDitherLeavesNativePixelsUntouched() throws {
        let size = CGSize(width: 390, height: 844)
        let native = LegacyOrbField(elapsed: 7.5, fills: fills, multiplier: 1, mixing: true)
            .background(Color.black)
        let baseline = try render(native, size: size, name: "native-no-modifier")
        let disabled = try render(native.modifier(OptionalOrbDitherModifier(enabled: false)),
                                  size: size, name: "native-dither-disabled")
        XCTAssertEqual(baseline, disabled, "Selecting native must bypass the entire dither pipeline")
    }

    func testCanvasDitherOptionRendersAndIsStatic() throws {
        let size = CGSize(width: 390, height: 844)
        for mixing in [false, true] {
            let canvas = LegacyOrbCanvas(elapsed: 7.5, fills: fills, multiplier: 1, mixing: mixing)
                .background(Color.black)
                .modifier(OptionalOrbDitherModifier(enabled: true))
            let first = try render(canvas, size: size, name: "canvas-option-\(mixing)")
            let second = try render(canvas, size: size, name: "canvas-option-repeat-\(mixing)")
            XCTAssertEqual(first, second, "Dither must not flicker at a fixed animation time")
            XCTAssertGreaterThan(Set(first).count, 20, "Canvas symbols must be visible")
        }
    }

    func testStarsVisualParity() throws {
        let size = CGSize(width: 390, height: 844)
        for elapsed in [0.0, 9.0, 37.0] {
            let reference = ZStack {
                ForEach(0..<90, id: \.self) { index in
                    let star = OrbStarField.stars[index]
                    let opacity = star.opacity(at: elapsed, night: 1)
                    if opacity > 0.001 {
                        Circle().fill(.white).frame(width: star.radius * 2, height: star.radius * 2)
                            .blur(radius: star.radius > 1.6 ? 0.6 : 0.2)
                            .position(x: star.x * size.width, y: star.y * size.height).opacity(opacity)
                    }
                }
            }.frame(width: size.width, height: size.height).background(Color.black)
            let original = try render(reference, size: size, name: "stars-original-\(elapsed)")
            let optimized = try render(OrbStarField(elapsed: elapsed, night: 1).background(Color.black),
                size: size, name: "stars-canvas-\(elapsed)")
            var error = 0.0
            var energy = 0.0
            for index in original.indices where index % 4 != 3 {
                error += abs(Double(original[index]) - Double(optimized[index]))
                energy += Double(original[index])
            }
            print("Star visual relative pixel error: \(error / max(energy, 1))")
            XCTAssertGreaterThan(energy, 1000)
            XCTAssertLessThan(error / max(energy, 1), 0.05)
        }
    }

    func testStarSeedsAndBreathingRemainUnchanged() {
        XCTAssertEqual(OrbStarField.stars.count, 90)
        func fraction(_ n: Double) -> Double { n - floor(n) }
        for (index, star) in OrbStarField.stars.enumerated() {
            let seed = Double(index) * 0.6180339887498949
            let y = fraction(sin(seed * 311.7) * 43758.5453123) * 0.6667
            let fade = y <= 1.0 / 3 ? 1 : max(0, 1 - (y - 1.0 / 3) / (1.0 / 3))
            XCTAssertEqual(star.y, y, accuracy: 1e-12)
            XCTAssertEqual(star.fade, fade, accuracy: 1e-12)
            for elapsed in [0.0, 1.5, 60.0, 1943.0] {
                let phase = fraction(elapsed * star.frequency + seed)
                let original = min(1, (0.45 + 0.55 * (0.5 - 0.5 * cos(phase * 2 * .pi)))
                    * (0.82 + 0.18 * sin(elapsed * 5 + seed * 30))) * fade
                XCTAssertEqual(star.opacity(at: elapsed, night: 1), original, accuracy: 1e-12)
                XCTAssertEqual(star.opacity(at: elapsed, night: 0), 0)
            }
        }
    }

    func testLiveRenderingCPUComparison() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previousWindow = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        defer {
            window.isHidden = true
            previousWindow?.makeKeyAndVisible()
        }
        let size = CGSize(width: 390, height: 844)
        var results: [Bool: [Double]] = [:]
        for optimized in [false, true, true, false] {
            let clock = AnimationClock()
            let content = ClockDrivenContent(clock: clock) { elapsed in
                if optimized {
                    LegacyOrbField(elapsed: elapsed, fills: self.fills, multiplier: 1, mixing: true)
                } else {
                    self.reference(elapsed: elapsed, size: size, mixing: true, multiplier: 1)
                }
            }.frame(width: size.width, height: size.height).background(Color.gray)
            window.rootViewController = UIHostingController(rootView: content)
            window.makeKeyAndVisible()
            clock.start()
            try await Task.sleep(for: .seconds(2))
            var start = rusage()
            getrusage(RUSAGE_SELF, &start)
            let began = CACurrentMediaTime()
            try await Task.sleep(for: .seconds(5))
            var end = rusage()
            getrusage(RUSAGE_SELF, &end)
            func seconds(_ usage: rusage) -> Double {
                Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
                    + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
            }
            let cpu = (seconds(end) - seconds(start)) / (CACurrentMediaTime() - began) * 100
            results[optimized, default: []].append(cpu)
            clock.stop()
            print("Live orb renderer simulator CPU: optimized=\(optimized), cpu=\(cpu)%")
        }
        XCTAssertEqual(results.count, 2)
        for optimized in [false, true] {
            let values = try XCTUnwrap(results[optimized])
            print("Live orb renderer simulator mean CPU: optimized=\(optimized), cpu=\(values.reduce(0, +) / Double(values.count))%, runs=\(values)")
        }
        // Hardware thermal/GPU behavior still needs a real-device comparison.
    }
}
