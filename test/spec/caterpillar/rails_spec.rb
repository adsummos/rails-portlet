# encoding: utf-8
#--
# Copyright (c) 2010 Mikael Lammentausta
# This source code is available under the MIT license.
# See the file LICENSE.txt for details.
#++

require File.join(File.dirname(__FILE__),'..','spec_helper')
require 'tmpdir'
require 'tempfile'
#require 'open4'
#include Open4
require 'net/http'

describe @caterpillar do

  @@pids = []
  
  def check_rails_gem(version)
    installed_rails_gems = %x[#{@ruby} `which gem` list rails]
    if installed_rails_gems[/#{version}/] == nil
      STDOUT.puts 'Installing missing rubygems...'
      system("sudo #{@ruby} `which gem` install rails -v=#{version} --no-ri --no-rdoc")
    end
    # check again...
    installed_rails_gems = %x[#{@ruby} `which gem` list rails]
    installed_rails_gems[/#{version}/].should == version #, "Ruby #{@ruby} does not come with Rails #{version}"
  end

  def create_rails(version)
    check_rails_gem(version)
    Dir.chdir(@tmpdir)
    rails_dir = "rails#{version}"
    
    FileUtils.rm_rf rails_dir if File.exist?(rails_dir)
    File.exist?(rails_dir).should == false

    system("#{@ruby} `which rails` _#{version}_ #{rails_dir} >/dev/null").should == true
    File.exist?(rails_dir).should == true

    env = File.join(Dir.pwd, rails_dir, 'config', 'environment.rb')
    File.exist?(env).should == true
    _version = File.read(env)[/RAILS_GEM_VERSION.*$/][/([\d.]+)/,1]
    _version.should == version
    return File.join(Dir.pwd, rails_dir)
  end
  
  def package_caterpillar
    Dir.chdir File.join(@pwd,'..','caterpillar')
    version = File.read('lib/caterpillar.rb')[/VERSION.*/][/([\d.]+)/,1]
    system("#{@ruby} `which gem` build caterpillar.gemspec").should == true
    _gem = "caterpillar-#{version}.gem"
    File.exists?(_gem).should == true
    return _gem
  end

  def install_caterpillar
    gem = package_caterpillar
    system("sudo #{@ruby} `which gem` install #{gem} --no-ri --no-rdoc").should == true  
  end
  
  def pluginize_caterpillar(rails_version)
    STDOUT.puts 'Using ' + @ruby
    #install_caterpillar # XXX
    rails_home = create_rails(rails_version)
    Dir.chdir rails_home
    system("#{@ruby} `which caterpillar` pluginize >/dev/null").should == true
    return rails_home
  end

  def test_rails(rails_home)
    # runs the server in a new subprocess, waits for it to launch
    # and terminates the process, reads from outout that it was
    # opened correctly
    Dir.chdir(rails_home)

    # funny way to read startup messages from Rails > 2.1.2 ...
    #f = Tempfile.new('')
    f_out = File.new '/Users/mikael/work/rails-portlet-github/test/stdout'
    f_err = File.new '/Users/mikael/work/rails-portlet-github/test/stderr'
    `echo -e '\n\$stdout = File.new "#{f_out.path}", "a"' >> config/environment.rb`
    `echo -e '\n\$stderr = File.new "#{f_err.path}", "a"' >> config/environment.rb`

    # enable caterpillar
    routes = File.open('config/routes.rb','r+')
    _routes = routes.readline
    _routes << "  map.caterpillar\n"
    _routes << routes.read
    routes.seek(0)
    routes.write(_routes)
    routes.close

    IO.popen("#{@ruby} script/server -p 3010 > #{f_out.path} 2>#{f_err.path} ") do |pipe|
      pid = pipe.pid
      @@pids << pid
      puts 'Rails PID: %s' % pid
      sleep 5
      begin
        # no errors in startup log
        output = f_out.read
        #puts '--- output ---'
        #puts output
        #puts '--------------'

        errors = f_err.read
        #puts '--- errors ---'
        #puts errors
        #puts '--------------'
        #if errors
        #  errors.each_with_index {|line,i| puts line if i<3}
        #end
        errors[/.*(error|errno).*/i].should == nil

        # check that test bench loads
        h = Net::HTTP.new('127.0.0.1', 3010)
        resp, data = h.get('/caterpillar/test_bench', nil)
        if resp != Net::HTTPSuccess
          # show errors from the log file
          log = File.open('log/development.log')
          err = ''
          3.times { err << log.readline() }
          err.should == nil
          resp.error! # fails before this line
        end
        data[/Rails-portlet testbench/].should_not == nil

      # make sure the server is shut down
      ensure
        Process.kill("TERM",pid+1) # XXX pid+1 works on OS X
        sleep 1
        #@@pids.delete pid

      end
    end
  end

  before(:all) do
  end

  after(:all) do
  end

  before(:each) do
    @pwd = Dir.pwd
    @tmpdir = Dir.tmpdir + '/rails-portlet'
    Dir.mkdir(@tmpdir) unless File.exists?(@tmpdir)
  end

  after(:each) do
    #FileUtils.rm_rf @tmpdir
    Dir.chdir @pwd
=begin
    @@pids.each do |pid|
      puts 'killing (for sure) %s' % pid
      begin
        Process.kill("TERM",pid)
      rescue
        nil
      end
    end
=end
  end
  

  ### try different Ruby interpreter / Rails combinations ...

  # quick debug
  #rails_home = '/Users/mikael/work/rails-portlet-github/example'

  it "pluginize caterpillar to Rails 2.1.2 with Ruby 1.8" do
    @ruby = '/usr/bin/ruby'
    rails_home = pluginize_caterpillar('2.1.2')
    test_rails(rails_home)
  end

  it "pluginize caterpillar to Rails 2.2.3 with Ruby 1.8" do
    @ruby = '/usr/bin/ruby'
    rails_home = pluginize_caterpillar('2.2.3')
    test_rails(rails_home)
  end

  it "pluginize caterpillar to Rails 2.3.8 with Ruby 1.8" do
    @ruby = '/usr/bin/ruby'
    rails_home = pluginize_caterpillar('2.3.8')
    test_rails(rails_home)
  end

=begin # Do not use Ruby1.9 with Raise older than 2.3
  it "pluginize caterpillar to Rails 2.1.2 with Ruby 1.9" do
    @ruby = `which ruby1.9`.strip
    rails_home = pluginize_caterpillar('2.1.2')
    test_rails(rails_home)
  end

  it "pluginize caterpillar to Rails 2.2.3 with Ruby 1.9" do
    @ruby = `which ruby1.9`.strip
    rails_home = pluginize_caterpillar('2.2.3')
    test_rails(rails_home)
  end
=end
  it "pluginize caterpillar to Rails 2.3.8 with Ruby 1.9" do
    @ruby = `which ruby1.9`.strip
    rails_home = pluginize_caterpillar('2.3.8')
    test_rails(rails_home)
  end

end
