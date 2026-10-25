require_relative "lib/movoa/version"

Gem::Specification.new do |s|
  s.name        = "movoa"
  s.version     = Movoa::VERSION
  s.summary     = "Official SDK for Movoa (movoa.ai), the AI video generator with sound."
  s.description = "Unlimited AI video generator with sound: on paid plans the tenth take of a shot costs what the first did, and your first clip is free to make right now. A zero-dependency Ruby client for Movoa (movoa.ai): text to video and photo to video with sound, on MiniMax H3, Seedance 2.5, Seedance 2.0 and Veo 3.1 Fast, with one API key."
  s.authors     = ["Movoa (https://movoa.ai)"]
  s.homepage    = "https://movoa.ai/?utm_source=rubygems&utm_medium=package"
  s.license     = "MIT"
  s.files       = Dir["lib/**/*.rb"] + ["README.md", "LICENSE"]
  s.required_ruby_version = ">= 2.6"
  s.metadata    = {
    "homepage_uri"      => "https://movoa.ai/?utm_source=rubygems&utm_medium=package",
    "source_code_uri"   => "https://github.com/hanshs474/movoa-rb",
    "documentation_uri" => "https://movoa.ai/video/text-to-video",
    "bug_tracker_uri"   => "https://github.com/hanshs474/movoa-rb/issues",
    "rubygems_mfa_required" => "false"
  }
end
