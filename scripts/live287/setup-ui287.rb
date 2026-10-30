require 'xcodeproj'
r = ENV.fetch('GITHUB_WORKSPACE', Dir.pwd)
d = File.join(r, 'evidence-live287', 'ui')
FileUtils.mkdir_p(d)
p = Xcodeproj::Project.new(File.join(d, 'Live287.xcodeproj'))
a = p.new_target(:application, 'Live287', :ios, '17.0')
['AVDB/Services/LiveSubtitleCore.swift', 'AVDB/Services/LiveAppleTranslation.swift', 'AVDB/Views/Player/LiveSubtitleViews.swift',
 'scripts/live287/LiveUIHost287.swift'].each { |f| a.source_build_phase.add_file_reference(p.main_group.new_file(File.join(r, f))) }
t = p.new_target(:ui_test_bundle, 'Live287UITests', :ios, '17.0'); t.add_dependency(a)
t.source_build_phase.add_file_reference(p.main_group.new_file(File.join(r, 'scripts/live287/LiveUITests287.swift')))
[a, t].each do |x|
  x.build_configurations.each do |c|
    c.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'org.avdb.' + x.name
    c.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
    c.build_settings['SWIFT_VERSION'] = '5.0'
    c.build_settings['TARGETED_DEVICE_FAMILY'] = '1'
    c.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
    if x == a
      c.build_settings['INFOPLIST_KEY_UILaunchScreen_Generation'] = 'YES'
      c.build_settings['INFOPLIST_KEY_UIApplicationSceneManifest_Generation'] = 'YES'
      c.build_settings['INFOPLIST_KEY_UISupportedInterfaceOrientations'] = 'UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight'
    else
      c.build_settings['TEST_TARGET_NAME'] = 'Live287'
    end
  end
end
p.save
s = Xcodeproj::XCScheme.new; s.add_build_target(a); s.add_build_target(t); s.add_test_target(t); s.set_launch_target(a); s.save_as(p.path, 'Live287', true)
