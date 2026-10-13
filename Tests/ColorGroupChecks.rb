require 'fileutils'
repo = File.expand_path('..', __dir__)
source = File.read("#{repo}/GorillaTranslate/Models/TimePhase.swift")
first = source.index('enum GorillaColorGroup:') or abort 'Missing color policy'
last = source.index('// MARK: - Time Phase Model', first) or abort 'Missing color policy boundary'
root = '/private/tmp/gorilla-color-group-checks'
FileUtils.mkdir_p(root)
File.write("#{root}/Policy.swift", "import Foundation\n" + source[first...last])
abort 'Compilation failed' unless system('swiftc', '-module-cache-path', '/private/tmp/gorilla-swift-test-cache',
  "#{root}/Policy.swift", "#{repo}/Tests/ColorGroupChecks.swift", '-o', "#{root}/checks")
abort 'Checks failed' unless system("#{root}/checks")
