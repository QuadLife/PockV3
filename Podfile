# Uncomment the next line to define a global platform for your project
  platform :osx, '10.13'

target 'PockV3' do
  # Comment the next line if you're not using Swift and don't want to use dynamic frameworks
  use_frameworks!

  # PockKit
  pod 'PockKit', :path => 'PockKit'
  
  # Pods for Pock
  #pod 'Fabric'
  #pod 'Crashlytics'
  pod 'Magnet'
  pod 'Defaults'
  pod 'Preferences'
  pod 'LoginServiceKit', :git => 'https://github.com/Clipy/LoginServiceKit.git'
  
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      if config.build_settings['MACOSX_DEPLOYMENT_TARGET'].to_f < 10.13
        config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '10.13'
      end
    end
  end
end
