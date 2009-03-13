# -*- encoding: utf-8 -*-

module_name = "pulp"

Gem::Specification.new do |s|
  s.version = "0.0.1"
  s.author = "Jason King"
  s.summary = %q{pulp - Passenger Helper - for simple setup of Ruby Apps using Passenger}

	s.files = %w{
    README.markdown
    lib/passenger/config.rb
    bin/pulp
  }

  s.executables = %w{
    pulp
  }

	#s.test_files       = Dir.glob('tests/*.rb')

  s.name = module_name
  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.date = Time.now.strftime("%Y-%m-%d")
  s.email = %q{jk@handle.it}
  s.has_rdoc = true
  s.homepage = "http://github.com/JasonKing/#{module_name}"
  s.rdoc_options = ["--inline-source", "--charset=UTF-8"]
  s.require_paths = ["lib"]
  s.rubygems_version = Gem::RubyGemsVersion
	s.platform         = Gem::Platform::RUBY

  if s.respond_to? :specification_version then
    current_version = Gem::Specification::CURRENT_SPECIFICATION_VERSION
    s.specification_version = 2

    if Gem::Version.new(Gem::RubyGemsVersion) >= Gem::Version.new('1.2.0') then
      s.add_runtime_dependency(%q<JasonKing-grep>, [">= 0.0.2"])
    else
      s.add_dependency(%q<JasonKing-grep>, [">= 0.0.2"])
    end
  else
    s.add_dependency(%q<JasonKing-grep>, [">= 0.0.2"])
  end
end

