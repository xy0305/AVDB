require 'xcodeproj'
r = ENV.fetch('GITHUB_WORKSPACE', Dir.pwd)
d = File.join(r, 'evidence-homehq298')
Dir.mkdir(d) unless Dir.exist?(d)
p = Xcodeproj::Project.new(File.join(d, 'HomeHQ298.xcodeproj'))
a = p.new_target(:application, 'HomeHQ298', :ios, '17.0')
files = [
  'AVDB/Services/ImageLoader.swift',
  'AVDB/Services/DetailPosterPolicy.swift',
  'AVDB/Services/DetailPosterResolver.swift',
  'AVDB/Services/DMMCoverResolver.swift',
  'AVDB/Services/TenhowPoster.swift',
  'AVDB/Services/CatalogueMetadata.swift',
  'AVDB/Models/Movie.swift',
  'AVDB/Networking/APIClient.swift',
  'AVDB/Networking/JavDBSignature.swift',
  'scripts/HomeHQUIHost298.swift'
]
files.each { |f| a.source_build_phase.add_file_reference(p.main_group.new_file(File.join(r, f))) }
t = p.new_target(:unit_test_bundle, 'HomeHQ298Tests', :ios, '17.0')
t.add_dependency(a)
t.source_build_phase.add_file_reference(p.main_group.new_file(File.join(r, 'scripts/HomeHQTests298.swift')))
t.source_build_phase.add_file_reference(p.main_group.new_file(File.join(r, 'scripts/HomeHQViewTests298.swift')))
[a, t].each do |x|
  x.build_configurations.each do |c|
    c.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'org.avdb.' + x.name
    c.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
    c.build_settings['SWIFT_VERSION'] = '5.0'
    c.build_settings['TARGETED_DEVICE_FAMILY'] = '1'
    c.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
    c.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
  end
end
p.save
s = Xcodeproj::XCScheme.new
s.add_build_target(a)
s.add_test_target(t)
s.set_launch_target(a)
s.save_as(p.path, 'HomeHQ298', true)
