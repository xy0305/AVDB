# Run from repository root on macOS (gem install xcodeproj if needed).
# Idempotent and based on CURRENT project, not a replacement PBX from build236/237.
require 'xcodeproj'
project = Xcodeproj::Project.open('AVDB.xcodeproj')
target = project.targets.find { |t| t.name == 'AVDB' }
raise 'AVDB target missing' unless target
root = project.main_group.children.find { |g| g.respond_to?(:path) && g.path == 'AVDB' } || project.main_group['AVDB']
raise 'AVDB group missing' unless root
[['Services', 'JavVerseSource.swift', target.source_build_phase],
 ['Services', 'JavVersePolicy.swift', target.source_build_phase],
 ['Services', 'JavVerseLiveClient.swift', target.source_build_phase],
 ['Views', 'JavVerseView.swift', target.source_build_phase],
 ['Resources', 'JavVerseSnapshot.json', target.resources_build_phase]].each do |group_name, name, phase|
 group = root.children.find { |g| g.respond_to?(:path) && g.path == group_name }
 group ||= root.new_group(group_name, group_name)
 ref = group.files.find { |f| f.path == name } || group.new_file(name)
 phase.add_file_reference(ref) unless phase.files_references.include?(ref)
end
if ARGV.include?('--tests')
  unit = project.targets.find { |t| t.name == 'JavVerseUnitTests' }
  unit ||= project.new_target(:unit_test_bundle, 'JavVerseUnitTests', :ios, '17.0')
  raise 'JavVerseUnitTests must be a hosted unit-test bundle' unless unit.product_type == 'com.apple.product-type.bundle.unit-test'
  unit.add_dependency(target) unless unit.dependencies.any? { |d| d.target == target }
  ['JavVerseIdentityTests.swift', 'JavVerseBehaviorTests.swift'].each do |name|
    path = "UITests/#{name}"
    ref = project.main_group.files.find { |f| f.path == path } || project.main_group.new_file(path)
    unit.source_build_phase.add_file_reference(ref) unless unit.source_build_phase.files_references.include?(ref)
  end
  unit.build_configurations.each do |config|
    config.build_settings.merge!({
      'PRODUCT_NAME' => '$(TARGET_NAME)', 'PRODUCT_BUNDLE_IDENTIFIER' => 'com.avdb.JavVerseUnitTests',
      'GENERATE_INFOPLIST_FILE' => 'YES', 'SWIFT_VERSION' => '5.0', 'TARGETED_DEVICE_FAMILY' => '1,2',
      'CODE_SIGNING_ALLOWED' => 'NO', 'TEST_HOST' => '$(BUILT_PRODUCTS_DIR)/AVDB.app/AVDB',
      'BUNDLE_LOADER' => '$(TEST_HOST)', 'OTHER_LDFLAGS' => '-Wl,-no_warn_duplicate_libraries'
    })
  end
  # Importing the hosted app also imports MediaPipe. Inherit search paths only,
  # never the app's static -force_load flags (duplicate registry risk).
  podfile = File.read('Podfile')
  unless podfile.include?("target 'JavVerseUnitTests' do")
    needle = "  pod 'MediaPipeTasksVision', '0.10.14'"
    raise 'Unrecognized Podfile: add nested JavVerseUnitTests inherit! :search_paths manually' unless podfile.include?(needle)
    podfile = podfile.sub(needle, needle + "\n  target 'JavVerseUnitTests' do\n    inherit! :search_paths\n  end")
    File.write('Podfile', podfile)
  end
  scheme = Xcodeproj::XCScheme.new
  scheme.add_build_target(target)
  scheme.add_build_target(unit)
  scheme.add_test_target(unit)
  if ARGV.include?('--ui-tests')
    ui = project.targets.find { |t| t.name == 'JavVerseUITests' }
    ui ||= project.new_target(:ui_test_bundle, 'JavVerseUITests', :ios, '17.0')
    raise 'JavVerseUITests must be a UI-test bundle' unless ui.product_type == 'com.apple.product-type.bundle.ui-testing'
    ui.add_dependency(target) unless ui.dependencies.any? { |d| d.target == target }
    path = 'UITests/JavVerseNavigationTests.swift'
    ref = project.main_group.files.find { |f| f.path == path } || project.main_group.new_file(path)
    ui.source_build_phase.add_file_reference(ref) unless ui.source_build_phase.files_references.include?(ref)
    ui.build_configurations.each do |config|
      config.build_settings.merge!({
        'PRODUCT_NAME' => '$(TARGET_NAME)', 'PRODUCT_BUNDLE_IDENTIFIER' => 'com.avdb.JavVerseUITests',
        'GENERATE_INFOPLIST_FILE' => 'YES', 'SWIFT_VERSION' => '5.0', 'TARGETED_DEVICE_FAMILY' => '1,2',
        'CODE_SIGNING_ALLOWED' => 'NO', 'TEST_TARGET_NAME' => 'AVDB'
      })
    end
    scheme.add_build_target(ui)
    scheme.add_test_target(ui)
  end
  scheme.set_launch_target(target)
  scheme.save_as(project.path, 'JavVerseAcceptance', true)
end
project.save
puts 'Registered JavVerse sources/snapshot; tests are opt-in. No version/workflow/entry edits.'
