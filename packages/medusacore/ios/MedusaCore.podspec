engine_public = File.expand_path('../../../engine/medusacore/src/medusa/core/public', __dir__)

Pod::Spec.new do |s|
  s.name           = 'MedusaCore'
  s.version        = '0.0.0'
  s.summary        = 'Medusa on MedusaCore (our own Chromium layer) for React Native macOS'
  s.author         = ''
  s.homepage       = 'https://github.com/medusa'
  s.license        = 'Apache-2.0'
  s.platforms      = { :osx => '14.0' }
  s.source         = { git: '' }
  s.static_framework = true
  s.dependency 'ExpoModulesCore'
  s.source_files   = '*.{h,mm,swift}'
  s.public_header_files = 'MedusaCoreHost.h', 'MedusaCoreWebView.h', 'MedusaCoreTabStrip.h', 'MedusaCoreEngineBridge.h', 'MedusaCoreServices.h', 'ACSwipe.h', 'ACChromeWindow.h'
  s.resources      = 'page_script.js'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'HEADER_SEARCH_PATHS' => "\"#{engine_public}\"",
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++20',
  }
end
