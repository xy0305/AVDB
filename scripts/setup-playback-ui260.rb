require 'xcodeproj'
root = ENV.fetch('GITHUB_WORKSPACE', Dir.pwd)
dir = File.join(root, 'evidence260')
p = Xcodeproj::Project.new(File.join(dir, 'Playback260.xcodeproj'))
app = p.new_target(:application, 'Playback260', :ios, '17.0')
app.source_build_phase.add_file_reference(p.main_group.new_file(File.join(dir, 'Identity260.swift')))
files = ['AVDB/Services/PlaybackDiagnostic.swift', 'AVDB/Services/JavRankingCore.swift', 'AVDB/Services/MissAVCore.swift', 'AVDB/Services/OnlinePlaybackCore.swift', 'AVDB/Services/OnlineAdditionalProviders.swift', 'AVDB/Services/DetailOnlineAdapters.swift', 'AVDB/Views/Player/OnlinePlaybackPanel.swift', 'AVDB/Views/Detail/PlaybackResourceCards.swift', 'scripts/PlaybackUIHost260.swift']
files.each { |f| app.source_build_phase.add_file_reference(p.main_group.new_file(File.join(root, f))) }
app.build_configurations.each do |c|
  c.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'org.avdb.Playback260'
  c.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  c.build_settings['INFOPLIST_KEY_UILaunchScreen_Generation'] = 'YES'
  c.build_settings['INFOPLIST_KEY_UIApplicationSceneManifest_Generation'] = 'YES'
  c.build_settings['SWIFT_VERSION'] = '5.0'
  c.build_settings['TARGETED_DEVICE_FAMILY'] = '1,2'
  c.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
end
t = p.new_target(:ui_test_bundle, 'PlaybackResourceUITests260', :ios, '17.0')
t.add_dependency(app)
t.source_build_phase.add_file_reference(p.main_group.new_file(File.join(root, 'scripts/PlaybackResourceUITests260.swift')))
t.build_configurations.each do |c|
  c.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'org.avdb.PlaybackResourceUITests260'
  c.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  c.build_settings['TEST_TARGET_NAME'] = 'Playback260'
  c.build_settings['SWIFT_VERSION'] = '5.0'
  c.build_settings['TARGETED_DEVICE_FAMILY'] = '1,2'
  c.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
end
p.save
s = Xcodeproj::XCScheme.new
s.add_build_target(app); s.add_build_target(t); s.add_test_target(t); s.set_launch_target(app)
s.save_as(p.path, 'Playback260', true)
