require 'xcodeproj'
require 'fileutils'
r = ENV.fetch('GITHUB_WORKSPACE', Dir.pwd)
d = File.join(r, 'evidence-live288', 'coldload-sim')
FileUtils.mkdir_p(d)
p = Xcodeproj::Project.new(File.join(d, 'Cold288.xcodeproj'))
a = p.new_target(:application, 'Cold288', :ios, '17.0')
['AVDB/Services/LiveSubtitleCore.swift', 'AVDB/Services/LiveTranslationPrep.swift', 'AVDB/Services/LiveAppleTranslation.swift', 'AVDB/Services/LiveSpeechEngines.swift',
 'scripts/live288/ColdLoadCore288.swift', 'scripts/live288/ColdLoadApp288.swift'].each { |f| a.source_build_phase.add_file_reference(p.main_group.new_file(File.join(r, f))) }
models = p.main_group.new_file(File.join(r, 'AVDB/Resources/LiveModels'))
models.last_known_file_type = 'folder'
a.resources_build_phase.add_file_reference(models)
a.resources_build_phase.add_file_reference(p.main_group.new_file(File.join(d, 'sample288.wav')))
pkg = p.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
pkg.repositoryURL = 'https://github.com/argmaxinc/argmax-oss-swift.git'
pkg.requirement = { 'kind' => 'exactVersion', 'version' => '1.1.1' }
p.root_object.package_references << pkg
dep = p.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
dep.package = pkg
dep.product_name = 'WhisperKit'
a.package_product_dependencies << dep
bf = p.new(Xcodeproj::Project::Object::PBXBuildFile)
bf.product_ref = dep
a.frameworks_build_phase.files << bf
a.build_configurations.each do |c|
  c.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'org.avdb.Cold288'
  c.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  c.build_settings['SWIFT_VERSION'] = '5.0'
  c.build_settings['TARGETED_DEVICE_FAMILY'] = '1'
  c.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
  c.build_settings['INFOPLIST_KEY_UILaunchScreen_Generation'] = 'YES'
  c.build_settings['INFOPLIST_KEY_UIApplicationSceneManifest_Generation'] = 'YES'
end
p.save
s = Xcodeproj::XCScheme.new; s.add_build_target(a); s.set_launch_target(a); s.save_as(p.path, 'Cold288', true)
