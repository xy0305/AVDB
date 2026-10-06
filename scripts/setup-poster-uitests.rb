require 'xcodeproj'
p = Xcodeproj::Project.open('AVDB.xcodeproj')
app = p.targets.find { |t| t.name == 'AVDB' }
t = p.new_target(:ui_test_bundle, 'PosterNavigationUITests', :ios, '17.0')
t.add_dependency(app)
f = p.main_group.new_group('UITests').new_file('UITests/PosterNavigationTests.swift')
t.source_build_phase.add_file_reference(f)
t.build_configurations.each do |c|
  c.build_settings['PRODUCT_NAME'] = 'PosterNavigationUITests'
  c.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.avdb.PosterNavigationUITests'
  c.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  c.build_settings['TEST_TARGET_NAME'] = 'AVDB'
  c.build_settings['SWIFT_VERSION'] = '5.0'
  c.build_settings['TARGETED_DEVICE_FAMILY'] = '1,2'
  c.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
end
p.save
s = Xcodeproj::XCScheme.new
s.add_build_target(app)
s.add_build_target(t)
s.add_test_target(t)
s.set_launch_target(app)
s.save_as(p.path, 'PosterNavigation', true)
