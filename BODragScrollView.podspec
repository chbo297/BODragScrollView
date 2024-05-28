Pod::Spec.new do |s|
  s.name         = "BODragScrollView"
  s.version      = "1.0.9"
  s.summary      = "ScrollView nested support"

  s.description  = "ScrollView nested in dragable card view interaction"

  s.homepage     = "https://github.com/chbo297/BODragScrollView"
  s.license      = { :type => "MIT", :file => "LICENSE" }
  s.author             = { "bo" => "chbo297@gmail.com" }

  s.platform     = :ios, "9.0"
  s.source       = {
                     :git => "https://github.com/chbo297/BODragScrollView.git",
                     :tag => s.version
  }

  s.source_files  = "BODragScrollView", "BODragScrollView/*.{h}", "BODragScrollView/*.{m}"
  s.framework = 'UIKit'
  s.license = 'MIT'
end
