platform :ios, '16.0'

target 'GorillaTranslate' do
  use_frameworks!

  # 高德導航 SDK（已內含 3D 地圖 SDK，NO-IDFA 版本）
  pod 'AMapNavi-NO-IDFA', '~> 11.2.100'
  pod 'AMapLocation-NO-IDFA', '~> 2.10'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      # AMap SDK 本身排除 arm64 模擬器（冇 arm64 sim slice）
      if target.name.start_with?('AMap')
        config.build_settings['EXCLUDED_ARCHS[sdk=iphonesimulator*]'] = 'arm64'
        # Xcode 27 最低支援 15.0
        config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
      else
        # 其他 pod 唔排除（支援 iPhone Duo 等 arm64-only 模擬器）
        config.build_settings.delete('EXCLUDED_ARCHS[sdk=iphonesimulator*]')
      end
    end
  end

  # 主 app xcconfig: 模擬器 build 完全唔連接 AMap（冇 arm64 sim binary）
  # 同埋移除 EXCLUDED_ARCHS（支援 arm64-only 模擬器如 iPhone Duo）
  %w[debug release].each do |config_name|
    xcconfig_path = "Pods/Target Support Files/Pods-GorillaTranslate/Pods-GorillaTranslate.#{config_name}.xcconfig"
    next unless File.exist?(xcconfig_path)
    content = File.read(xcconfig_path)

    # 移除 EXCLUDED_ARCHS（唔排除 arm64 模擬器）
    content = content.gsub(/^EXCLUDED_ARCHS\[sdk=iphonesimulator\*\]\s*=.*\n?/, '')

    amap_flag_pattern = /-weak_framework\s+"?AMap\w+"?|-framework\s+"?AMap\w+"?/

    # OTHER_LDFLAGS: 移除 AMap flags，改用 conditional 真機加入
    if content =~ /^(OTHER_LDFLAGS\s*=\s*)(.+)$/
      full_flags = $2.strip
      non_amap = full_flags.gsub(amap_flag_pattern, '').gsub(/\s{2,}/, ' ').strip
      amap_only = full_flags.scan(amap_flag_pattern).map(&:strip).join(' ')
      # 基底用無 AMap 版（模擬器用），真機再加 AMap
      content = content.sub(
        /^(OTHER_LDFLAGS\s*=\s*.+)$/,
        "OTHER_LDFLAGS = #{non_amap}\nOTHER_LDFLAGS[sdk=iphoneos*] = #{amap_only}"
      )
    end

    # Framework search paths: 同理
    if content =~ /^(FRAMEWORK_SEARCH_PATHS\s*=\s*)(.+)$/
      full_paths = $2.strip
      non_amap = full_paths.gsub(/\s*"\$\{PODS_ROOT\}\/AMap[^"]*"/, '').gsub(/\s{2,}/, ' ').strip
      amap_paths = full_paths.scan(/\s*"\$\{PODS_ROOT\}\/AMap[^"]*"/).join.strip
      content = content.sub(
        /^(FRAMEWORK_SEARCH_PATHS\s*=\s*.+)$/,
        "FRAMEWORK_SEARCH_PATHS = #{non_amap}\nFRAMEWORK_SEARCH_PATHS[sdk=iphoneos*] = #{amap_paths}"
      )
    end

    File.write(xcconfig_path, content)
  end
end
