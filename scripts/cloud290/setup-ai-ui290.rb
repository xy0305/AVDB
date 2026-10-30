require 'xcodeproj'
r = ENV.fetch('GITHUB_WORKSPACE', Dir.pwd)
d = File.join(r, 'evidence-ai290ui')
p = Xcodeproj::Project.new(File.join(d, 'AI290.xcodeproj'))
a = p.new_target(:application, 'AI290', :ios, '17.0')
['AVDB/Services/AICoverPolicy.swift', 'AVDB/Services/AICoverSREngine.swift', 'AVDB/Services/AICoverCloud.swift', 'AVDB/Services/AICoverEnhancer.swift',
 'AVDB/Views/Detail/AICoverViews.swift', 'scripts/cloud290/AICoverUIHost290.swift', 'AVDB/Resources/CoverSR.mlpackage'].each do |f|
  ref = p.main_group.new_file(File.join(r, f))
  ref.last_known_file_type = 'folder.mlpackage' if f.end_with?('.mlpackage')
  a.source_build_phase.add_file_reference(ref)
end
['scripts/fixtures286/ipx706_front_378x538.jpg'].each { |f| a.resources_build_phase.add_file_reference(p.main_group.new_file(File.join(r, f))) }
t = p.new_target(:ui_test_bundle, 'AI290UITests', :ios, '17.0'); t.add_dependency(a)
t.source_build_phase.add_file_reference(p.main_group.new_file(File.join(r, 'scripts/cloud290/AICoverUITests290.swift')))
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
      c.build_settings['SWIFT_OPTIMIZATION_LEVEL'] = '-O'
      c.build_settings['INFOPLIST_FILE'] = File.join(r, 'scripts/cloud290/HostInfo290.plist')
    else
      c.build_settings['TEST_TARGET_NAME'] = 'AI290'
    end
  end
end
p.save
s = Xcodeproj::XCScheme.new; s.add_build_target(a); s.add_build_target(t); s.add_test_target(t); s.set_launch_target(a); s.save_as(p.path, 'AI290', true)
