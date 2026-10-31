require 'xcodeproj'
require 'fileutils'
require 'json'
r = ENV.fetch('GITHUB_WORKSPACE', Dir.pwd)
d = File.join(r, 'evidence-live289', 'coldload-sim')
FileUtils.mkdir_p(d)
p = Xcodeproj::Project.new(File.join(d, 'Cold289.xcodeproj'))
a = p.new_target(:application, 'Cold289', :ios, '17.0')
['AVDB/Services/LiveSubtitleCore.swift', 'AVDB/Services/LiveTranslationPrep.swift', 'AVDB/Services/LiveAppleTranslation.swift', 'AVDB/Services/LiveSpeechEngines.swift',
 'AVDB/Services/LiveSenseVoice.swift', 'AVDB/Services/LiveSystemRecognizers.swift',
 'scripts/live289/ColdLoadCore289.swift', 'scripts/live289/ColdLoadApp289.swift'].each { |f| a.source_build_phase.add_file_reference(p.main_group.new_file(File.join(r, f))) }
models = p.main_group.new_file(File.join(r, 'AVDB/Resources/LiveModels'))
models.last_known_file_type = 'folder'
a.resources_build_phase.add_file_reference(models)
Dir.glob(File.join(d, 'samples', '*')).sort.each { |f| a.resources_build_phase.add_file_reference(p.main_group.new_file(f)) }
fw = p.main_group.new_file(File.join(r, 'Vendor/SherpaOnnxC.xcframework'))
a.frameworks_build_phase.add_file_reference(fw)
embed = a.new_copy_files_build_phase('Embed Frameworks')
embed.symbol_dst_subfolder_spec = :frameworks
bf = embed.add_file_reference(fw)
bf.settings = { 'ATTRIBUTES' => ['CodeSignOnCopy', 'RemoveHeadersOnCopy'] }
pkg = p.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
pkg.repositoryURL = 'https://github.com/argmaxinc/argmax-oss-swift.git'
pkg.requirement = { 'kind' => 'exactVersion', 'version' => '1.1.1' }
p.root_object.package_references << pkg
dep = p.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
dep.package = pkg
dep.product_name = 'WhisperKit'
a.package_product_dependencies << dep
pbf = p.new(Xcodeproj::Project::Object::PBXBuildFile)
pbf.product_ref = dep
a.frameworks_build_phase.files << pbf
a.build_configurations.each do |c|
  c.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'org.avdb.Cold289'
  c.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  c.build_settings['SWIFT_VERSION'] = '5.0'
  c.build_settings['TARGETED_DEVICE_FAMILY'] = '1'
  c.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
  c.build_settings['INFOPLIST_KEY_UILaunchScreen_Generation'] = 'YES'
  c.build_settings['INFOPLIST_KEY_UIApplicationSceneManifest_Generation'] = 'YES'
  c.build_settings['INFOPLIST_KEY_NSSpeechRecognitionUsageDescription'] = 'bench'
  c.build_settings['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks']
end
p.save
s = Xcodeproj::XCScheme.new; s.add_build_target(a); s.set_launch_target(a); s.save_as(p.path, 'Cold289', true)
