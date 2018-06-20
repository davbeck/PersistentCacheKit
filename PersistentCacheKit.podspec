Pod::Spec.new do |s|
  s.name             = 'PersistentCacheKit'
  s.version          = '0.3.1'
  s.summary          = 'A Swift library for caching items to the filesystem (using SQLite by default).'

  s.homepage         = 'https://github.com/davbeck/PersistentCacheKit'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'David Beck' => 'code@davidbeck.co' }
  s.source           = { :git => 'https://github.com/davbeck/PersistentCacheKit.git', :tag => s.version.to_s }
  s.social_media_url = 'https://twitter.com/davbeck'

  s.ios.deployment_target = '10.0'
  s.osx.deployment_target = '10.10'
  s.static_framework = true

  s.source_files = 'Sources/PersistentCacheKit/**/*'
end
