require 'open3'

root = File.expand_path('..', __dir__)
removed = %w[
  Podfile Podfile.lock Pods
  GorillaTranslate/AMap-Bridging-Header.h
  GorillaTranslate/Models/AMapConfig.swift
  GorillaTranslate/Models/AmapNaviManager.swift
  GorillaTranslate/Models/LaneGuidanceManager.swift
  GorillaTranslate/Views/AmapNaviTestView.swift
  GorillaTranslate/Views/LaneNavigationTestView.swift
  GorillaTranslate/Views/FloatingLaneGuidanceView.swift
]
removed.each { |path| raise "Still present: #{path}" if File.exist?(File.join(root, path)) }

paths = Dir[File.join(root, 'GorillaTranslate/**/*.swift')] + [
  File.join(root, 'GorillaTranslation.xcodeproj/project.pbxproj'),
  File.join(root, 'GorillaTranslation.xcworkspace/contents.xcworkspacedata')
]
paths.each do |path|
  raise "AMap integration remains: #{path}" if File.read(path).match?(/import AMap|restapi\.amap\.com|AMapConfig|AmapNavi|LaneNavigationTestView|FloatingLaneGuidanceView|Pods\/Pods|\[CP\]/)
end
raise 'Missing export-compliance setting' unless File.read(File.join(root, 'GorillaTranslate/Info.plist')).match?(/ITSAppUsesNonExemptEncryption<\/key>\s*<false\/>/)

if ARGV[0]
  app = File.join(ARGV[0], 'Products/Applications/GorillaTranslate.app')
  raise 'AMap resources bundled' unless Dir[File.join(app, '**/*')].none? { |p| File.basename(p).match?(/AMap|Amap|Pods_Gorilla/) }
  linked, status = Open3.capture2e('xcrun', 'otool', '-L', File.join(app, 'GorillaTranslate'))
  raise linked unless status.success?
  raise 'AMap framework linked' if linked.lines.drop(1).any? { |line| line.match?(/AMap|Pods_Gorilla/) }
  strings, status = Open3.capture2e('strings', File.join(app, 'GorillaTranslate'))
  raise strings unless status.success?
  raise 'AMap crypto code retained' if strings.match?(/amapossl_|AMapFoundationAES|AMapServices|NMXXTEAEncrypt|restapi\.amap\.com/)
  info, status = Open3.capture2e('plutil', '-extract', 'ITSAppUsesNonExemptEncryption', 'raw', File.join(app, 'Info.plist'))
  raise 'Archive missing compliance setting' unless status.success? && info.strip == 'false'
end

puts 'No AMap source, CocoaPods integration or bundled SDK remains.'
