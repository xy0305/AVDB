require 'xcodeproj'
r = ENV.fetch('GITHUB_WORKSPACE', Dir.pwd)
d = File.join(r, 'evidence-tab283')
p = Xcodeproj::Project.new(File.join(d, 'Tab283.xcodeproj'))
a = p.new_target(:application, 'Tab283', :ios, '17.0')
['AVDB/Views/AVDBNativeTabBar.swift', 'AVDB/Views/TabBarChrome.swift', 'scripts/TabUIHost283.swift'].each { |f| a.source_build_phase.add_file_reference(p.main_group.new_file(File.join(r, f))) }
t = p.new_target(:ui_test_bundle, 'TabUITests283', :ios, '17.0'); t.add_dependency(a)
t.source_build_phase.add_file_reference(p.main_group.new_file(File.join(r, 'scripts/TabUITests283.swift')))
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
    else
      c.build_settings['TEST_TARGET_NAME'] = 'Tab283'
    end
  end
end
p.save
s = Xcodeproj::XCScheme.new; s.add_build_target(a); s.add_build_target(t); s.add_test_target(t); s.set_launch_target(a); s.save_as(p.path, 'Tab283', true)
