require 'tmpdir'

repo = File.expand_path('..', __dir__)
source = File.read("#{repo}/GorillaTranslate/Views/GorillaPageView.swift")
first = source.index('enum GorillaPageLayout {') or abort 'Missing Gorilla layout policy'
last = source.index('enum GorillaBrand {', first) or abort 'Missing layout policy boundary'
abort 'Missing gold tab icon' unless source.include?('static let goldTabIcon: UIImage = {')
abort 'Gold tab icon must retain its own color' unless source.include?('withRenderingMode(.alwaysOriginal)')
abort 'Missing shared title gold' unless source.include?('static let darkKnightGold = UIColor(')
abort 'Missing gold highlight gradient' unless source.include?('context.drawLinearGradient(gradient,')
abort 'Gold body must be softened, not full-strength yellow' unless source.include?('let body = paleGold(whiteMix: 0.55, opacity: 0.75)')
content = File.read("#{repo}/GorillaTranslate/ContentView.swift")
abort 'Tab must use the original gold image' unless content.match?(/Image\(uiImage: GorillaBrand.goldTabIcon\)\s*\.renderingMode\(\.original\)/)
abort 'Title must use the same gold' unless content.include?('let goldColor = Color(uiColor: GorillaBrand.darkKnightGold)')
puts 'PASS: Gorilla tab shares title gold, with gradient highlights independent of glass preference'
Dir.mktmpdir('gorilla-page-checks-') do |root|
  fixture = "#{root}/GorillaPageLayout.swift"
  File.write(fixture, "import Foundation\n" + source[first...last])
  binary = "#{root}/checks"
  abort 'Compilation failed' unless system('xcrun', 'swiftc', fixture,
                                           "#{repo}/Tests/GorillaPageChecks.swift", '-o', binary,
                                           '-module-cache-path', "#{root}/ModuleCache")
  abort 'Checks failed' unless system(binary)
end
