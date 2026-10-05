require 'fileutils'

repo = File.expand_path('..', __dir__)
source = File.read("#{repo}/GorillaTranslate/Models/SFXPlayer.swift")
first = source.index('enum SFXPreferences {') or abort 'Missing sound preferences'
last = source.index('@MainActor', first) or abort 'Missing player boundary'
directory = '/private/tmp/gorilla-sfx-preference-tests'
FileUtils.mkdir_p(directory)
File.write("#{directory}/Preferences.swift", "import Foundation\n" + source[first...last])
abort 'Compilation failed' unless system('swiftc', '-module-cache-path', '/private/tmp/gorilla-swift-test-cache',
  "#{directory}/Preferences.swift", "#{repo}/Tests/SFXPreferenceChecks.swift", '-o', "#{directory}/checks")
abort 'Tests failed' unless system("#{directory}/checks", ARGV[0] || "#{repo}/GorillaTranslate/Resources/Audio/SFX")
