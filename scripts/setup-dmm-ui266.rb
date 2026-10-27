require 'xcodeproj'
r = ENV.fetch('GITHUB_WORKSPACE', Dir.pwd)
d = File.join(r, 'evidence-dmm266')
p = Xcodeproj::Project.new(File.join(d, 'DMM266.xcodeproj'))
a = p.new_target(:application, 'DMM266', :ios, '17.0')
['AVDB/Services/DMMRankingCore.swift', 'AVDB/Services/DMMTransport.swift', 'AVDB/Services/DMMRankingGraphQL.swift', 'AVDB/Services/DMMRankingHydrator.swift', 'AVDB/Services/DMMRankingStore.swift', 'AVDB/Views/Rankings/DMMRankingView.swift', 'scripts/DMMUIHost266.swift'].each { |f| a.source_build_phase.add_file_reference(p.main_group.new_file(File.join(r,f))) }
a.source_build_phase.add_file_reference(p.main_group.new_file(File.join(d,'MovieResolver.swift')))
t = p.new_target(:ui_test_bundle, 'DMMUITests266', :ios, '17.0'); t.add_dependency(a)
t.source_build_phase.add_file_reference(p.main_group.new_file(File.join(r,'scripts/DMMUITests266.swift')))
[a,t].each do |x|
 x.build_configurations.each do |c|
  c.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'org.avdb.' + x.name
  c.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  c.build_settings['SWIFT_VERSION'] = '5.0'
  c.build_settings['TARGETED_DEVICE_FAMILY'] = '1,2'
  c.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
  if x == a
   c.build_settings['INFOPLIST_KEY_UILaunchScreen_Generation'] = 'YES'
   c.build_settings['INFOPLIST_KEY_UIApplicationSceneManifest_Generation'] = 'YES'
  else
   c.build_settings['TEST_TARGET_NAME'] = 'DMM266'
  end
 end
end
p.save
s=Xcodeproj::XCScheme.new;s.add_build_target(a);s.add_build_target(t);s.add_test_target(t);s.set_launch_target(a);s.save_as(p.path,'DMM266',true)
