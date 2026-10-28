require 'fileutils'
repo = File.expand_path('..', __dir__)
root = '/private/tmp/gorilla-meter-overview-checks'
FileUtils.mkdir_p(root)
File.write("#{root}/Language.swift", 'enum LanguageManager { static let languageCode = "zh-Hant" }')
abort 'Compile failed' unless system('swiftc', '-module-cache-path', '/private/tmp/gorilla-swift-test-cache',
  "#{root}/Language.swift", "#{repo}/GorillaTranslate/Models/MeterData.swift",
  "#{repo}/Tests/MeterDataChecks.swift", '-o', "#{root}/checks")
abort 'Checks failed' unless system("#{root}/checks")
