#
# Be sure to run `pod lib lint SMSyncServer.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'SMSyncServer'
  s.version          = '0.0.3'
  s.summary          = 'iOS Client Framework for SMSyncServer'

# This description is used to generate tags and improve search results.
#   * Think: What does it do? Why did you write it? What is the focus?
#   * Try to keep it short, snappy and to the point.
#   * Write the description between the DESC delimiters below.
#   * Finally, don't worry about the indent, CocoaPods strips it!

#  s.description      = <<-DESC
# TODO: Add long description of the pod here.
#                       DESC

  s.homepage         = 'https://github.com/crspybits/SMSyncServer.iOSFramework.git'
  # s.screenshots     = 'www.example.com/screenshots_1', 'www.example.com/screenshots_2'
  s.license          = { :type => 'GPL3', :file => 'LICENSE' }
  s.author           = { 'Christopher Prince' => 'chris@SpasticMuffin.biz' }
  s.source           = { :git => 'https://github.com/crspybits/SMSyncServer.iOSFramework.git', :tag => s.version.to_s }
  # s.social_media_url = 'https://twitter.com/<TWITTER_USERNAME>'

  s.pod_target_xcconfig = {
     # I haven't been able to get a DEBUG flag set in a Cocoapod, without these
	'GCC_PREPROCESSOR_DEFINITIONS[config=Debug]' => 'DEBUG=1',
	'OTHER_SWIFT_FLAGS[config=Debug]' => '-DDEBUG'
  }
  
  s.ios.deployment_target = '8.0'

  s.source_files = 'SMSyncServer/Classes/**/*'
  
  s.resources = "SMSyncServer/Assets/*.xcdatamodel"

  # s.resource_bundles = {
  #   'SMSyncServer' => ['SMSyncServer/Assets/*.png']
  # }

  # s.public_header_files = 'Pod/Classes/**/*.h'
  # s.frameworks = 'UIKit', 'MapKit'
  
  s.dependency 'SMCoreLib'
end
