Pod::Spec.new do |s|
  s.name = "CBBFunctionChannel"
  s.version = "2.0.5"
  s.summary = "FunctionChannel for iOS"
  s.homepage = "https://github.com/cross-border-bridge/function-channel-ios"
  s.author = 'DWANGO Co., Ltd.'
  s.license = { :type => 'MIT', :file => 'LICENSE' }
  s.platform = :ios, "8.0"
  s.source = { :git => "https://github.com/cross-border-bridge/function-channel-ios.git", :tag => "#{s.version}" }
  s.source_files = "CBBFunctionChannel/**/*.{h,m}"
  s.dependency "CBBDataChannel", "~> 2.0.4"
  s.preserve_path = "CBBFunctionChannel.modulemap"
  s.module_map = "CBBFunctionChannel.modulemap"
end
