# Adds the ExpenseWidget extension (WidgetKit) to the generated Flutter
# Xcode project and gives the app and the widget a shared App Group.
require 'xcodeproj'

team = ENV.fetch('APPLE_TEAM_ID')
version = ENV.fetch('APP_VERSION')
build = ENV.fetch('BUILD_NUMBER')

proj = Xcodeproj::Project.open('Runner.xcodeproj')
app = proj.targets.find { |t| t.name == 'Runner' }

ext = proj.new_target(:app_extension, 'ExpenseWidget', :ios, '16.0', nil, :swift)
group = proj.main_group.new_group('ExpenseWidget', 'ExpenseWidget')
swift = group.new_file('ExpenseWidget.swift')
group.new_file('Info.plist')
group.new_file('ExpenseWidget.entitlements')
ext.add_file_references([swift])
%w[WidgetKit SwiftUI].each { |f| ext.add_system_framework(f) }

ext.build_configurations.each do |c|
  s = c.build_settings
  s['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.rashad.moneytracker.ExpenseWidget'
  s['PRODUCT_NAME'] = 'ExpenseWidget'
  s['INFOPLIST_FILE'] = 'ExpenseWidget/Info.plist'
  s['GENERATE_INFOPLIST_FILE'] = 'NO'
  s['CODE_SIGN_ENTITLEMENTS'] = 'ExpenseWidget/ExpenseWidget.entitlements'
  s['DEVELOPMENT_TEAM'] = team
  s['CODE_SIGN_STYLE'] = 'Automatic'
  s['SWIFT_VERSION'] = '5.0'
  s['IPHONEOS_DEPLOYMENT_TARGET'] = '16.0'
  s['TARGETED_DEVICE_FAMILY'] = '1,2'
  s['SKIP_INSTALL'] = 'YES'
  s['APPLICATION_EXTENSION_API_ONLY'] = 'YES'
  s['MARKETING_VERSION'] = version
  s['CURRENT_PROJECT_VERSION'] = build
  s['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks']
  s['SWIFT_EMIT_LOC_STRINGS'] = 'YES'
end

app.add_dependency(ext)
embed = app.new_copy_files_build_phase('Embed Foundation Extensions')
embed.symbol_dst_subfolder_spec = :plug_ins
bf = embed.add_file_reference(ext.product_reference, true)
bf.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
# Embed before Flutter's "Thin Binary" script, or Xcode reports a cycle.
thin = app.build_phases.index { |p| p.respond_to?(:name) && p.name.to_s.include?('Thin Binary') }
if thin
  app.build_phases.delete(embed)
  app.build_phases.insert(thin, embed)
end

runner_group = proj.main_group['Runner']
runner_group.new_file('Runner.entitlements') if runner_group
app.build_configurations.each do |c|
  c.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Runner/Runner.entitlements'
end

proj.save
puts "Added ExpenseWidget extension (#{version} / #{build})"
