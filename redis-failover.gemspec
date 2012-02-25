spec = Gem::Specification.new do |s|
  s.name = 'redis-failover'
  s.version = '0.1'
  s.summary = 'Redis failover for master-slave configurations'
  s.author = 'Jonathan Baudanza'
  s.email = 'jon@jonb.org'
  s.homepage = 'http://www.github.com/redis-failover/'
  s.add_dependency 'em-hiredis'
  s.files =  ['redis-failover.gemspec', 'Rakefile', 'README.md', 
  			  'failover.rb', 'LICENSE.txt']
  s.files += Dir['spec/*']

  s.description = <<END
  	Redis failover for master-slave configurations
END
end