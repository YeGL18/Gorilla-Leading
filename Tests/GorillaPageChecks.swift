import Foundation

@main
struct GorillaPageChecks {
    static func main() {
        let cases: [(String, Bool, CGSize, Bool)] = [
            ("inner landscape", true, CGSize(width: 951, height: 669), true),
            ("inner portrait", true, CGSize(width: 669, height: 951), false),
            ("outer portrait", true, CGSize(width: 466, height: 678), false),
            ("outer landscape", true, CGSize(width: 678, height: 466), false),
            ("phone portrait", true, CGSize(width: 402, height: 874), false),
            ("phone landscape", true, CGSize(width: 874, height: 402), false),
            ("large phone landscape", true, CGSize(width: 956, height: 440), false),
            ("tablet landscape", false, CGSize(width: 1194, height: 834), false),
            ("tablet portrait", false, CGSize(width: 834, height: 1194), false),
            ("Duo split window", true, CGSize(width: 475, height: 669), false),
            ("square window", true, CGSize(width: 669, height: 669), false),
            ("first layout", true, CGSize(width: 0, height: 0), false)
        ]
        for (name, isPhone, size, expected) in cases {
            precondition(GorillaPageLayout.showsTab(isPhone: isPhone, windowSize: size) == expected,
                         "Incorrect Gorilla tab visibility: \(name)")
        }
        print("PASS: \(cases.count) Gorilla tab layout checks")
    }
}
