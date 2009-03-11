require 'fileutils'
require 'etc'
require 'find'
require 'grep'

module Passenger
  class Config
    attr_reader :domain

    @@marker_string = "#----- #{File.basename($0, '.rb')} marker line -- DO NOT DELETE -----#"

    @@httpd_cmd = 'httpd'

    @@user_re  = /^\s*User\s+(\S+)/i
    @@group_re = /^\s*Group\s+(\S+)/i

    def initialize(p)
      @app = p[:app]
      @domain = (p[:domain] || '.dev').sub(/^\.*/,'.')
      @hosts = p[:hosts] || '/etc/hosts'
      @ip = p[:ip] || '127.0.0.1'

      @check_for_user = lambda {|l|
        if m = l.match(@@user_re)
          puts "Got user #{m[1]}"
          @user = m[1]
        end
      }
      @check_for_group = lambda {|l|
        if m = l.match(@@user_re)
          puts "Got group #{m[1]}"
          @group = m[1]
        end
      }
    end

    def host
      @host ||= @app + @domain
    end

    def conf
      @conf ||= from_server('SERVER_CONFIG_FILE')
    end

    def dir
      @dir ||= File.dirname(self.conf)
    end

    def server_root
      @server_root ||= File.open(conf).grep(/^\s*ServerRoot\s+['"]?([^'"\s]+)['"]?/i).first[:match][1] || from_server('HTTPD_ROOT')
    end

    def dir_handle
      @dir_handle ||= Dir.open(dir)
    end

    def user
      @user ||= get_user
    end

    def group
      @group ||= get_group
    end

    def get_user
      File.open(conf).each do |line|
        return @user if @check_for_user.call(line)
      end
    end

    def check_perms(_dir)
      system("sudo -u #{user} ls #{_dir} 1>/dev/null 2>&1") or raise %Q{Your Apache user "#{user}" can't read your document root "#{_dir}"}
    end

    def get_group
      File.open(conf).each do |line|
        return @group if @check_for_group.call(line)
      end
    end

    def retrieve_passenger_conf
      File.open(conf) do |f|
        f.each do |line|
          @check_for_user.call(line)
          @check_for_group.call(line)
          if line.chomp == @@marker_string
            until line.match(/^\s*[^#]/)
              line = f.gets
              unless m = line.match(/^\s*Include\s+(\S+)/)
                raise "Non-include following marker: #{@@marker_string} in #{conf}"
              end
              return m[1]
            end
          end
        end
      end
      return nil
    end

    def passenger_conf
      return @passenger_conf if @passenger_conf || @passenger_conf = retrieve_passenger_conf

      # Strings that we're looking for:
      #
      #   NameVirtualHost *:80
      #   LoadModule passenger_module /opt/local/lib/ruby/gems/1.8/gems/passenger-2.0.6/ext/apache2/mod_passenger.so
      #   PassengerRoot /opt/local/lib/ruby/gems/1.8/gems/passenger-2.0.6
      #   PassengerRuby /opt/local/bin/ruby
      #
      @_conf_strings = {
        :vhost => /^\s*NameVirtualHost\s+(\S+)/i,
        :load => %r{^\s*LoadModule\s+passenger_module\s+((/\S+)/lib/ruby/gems/\S+/passenger-[\d.]+)/ext/apache2/mod_passenger.so}i,
        :root => %r{^\s*PassengerRoot\s+(['"]?)(/\S+/lib/ruby/gems/\S+/passenger-[\d.]+)\1}i,
        :ruby =>  %r{^\s*PassengerRuby\s+(['"]?)(/\S+)/bin/ruby\1}i,
        :renv =>  %r{^\s*RailsEnv\s+(['"]?)(\S+)\1}i
      }

      @conf_files = {}

      # change into the server root so that any relative paths in the conf files work
      Dir.chdir(server_root) do |p|

        # start at the conf and drill down through all includes looking for our
        # strings and recording where they are - we're just going to barf if we
        # find the strings in more than one location - let the user sort that
        # out
        drill_down(conf)
      end

      check_conf
      ensure_conf

      # the logic for where we're going to add our vhosts is a little complex
      #
      #  1. We use the RailsEnv file as long as it comes after the
      #     NameVirtualHost entry
      #  2. Otherwise we're going to create our own file, include it from the
      #     main conf, and use that

      if @conf_files[:renv][:order] > @conf_files[:vhost][:order]
        if @conf_files[:renv][:file] != conf
          return @passenger_conf = @conf_files[:renv][:file]
        end
      end

      @passenger_conf = make_new_file
    end

    def ensure_dir(d)
      _umask = File.umask(022)
      _dir = File.join(dir, d)
      begin
        Dir.mkdir(_dir)
      rescue Errno::EEXIST
        # we don't care if it exists
      end
      File.umask(_umask)
      _dir
    end

    def make_new_file
      _dir = ensure_dir('extra')

      # we're going to make sure that we get a filename that doesn't exist
      %w{passenger.conf mod_rails.conf httpd-passenger.conf httpd-mod_rails.conf j20qmcjidhe93knd.conf}.each do |fn|
        _f = File.join(_dir,fn)
        if !File.exist?(_f)
          FileUtils.touch _f
          File.open(conf, 'a') do |f|
            f.puts @@marker_string
            f.puts "Include #{_f}"
          end
          return _f
        end
      end
      raise "Couldn't find a unique filename in #{_dir}."
    end

    def ensure_conf
      unless @conf_files[:root]
        add_to_conf( "PassengerRoot #{@conf_files[:load][:match][1]}", :load, :root )
      end

      unless @conf_files[:ruby]
        add_to_conf( "PassengerRuby #{@conf_files[:load][:match][2]}/bin/ruby", :root, :ruby )
      end

      unless @conf_files[:renv]
        add_to_conf( "RailsEnv #{ENV['RAILS_ENV'] || 'development'}", :ruby, :renv )
      end

      unless @conf_files[:vhost]
        add_to_conf( "NameVirtualHost *:80", :renv, :vhost )
      end
      check_conf
    end

    def add_to_conf( str, from, to)
      p = @conf_files[from]
      File.open( p[:file], 'r+' ) do |f|
        f.flock File::LOCK_EX
        buffer = []
        f.each do |l|
          buffer << l
          if $. == p[:lineno]
            buffer << str.chomp + "\n"
          end
        end
        f.truncate 0
        f.seek 0
        f << buffer
      end
    end

    def check_conf
      unless @conf_checked

        # we can add everything except the LoadModule line
        unless @conf_files[:load]
          raise "LoadModule line missing, maybe you forgot to run: passenger-install-apache2-module"
        end

        _load_order = @conf_files[:load][:order]
        [ :root, :ruby, :renv ].each do |s|
          next unless @conf_files[s]
          if _load_order > @conf_files[s][:order]
            raise "Passenger module loaded too late: #{@conf_files[:load][:file]},#{@conf_files[:load][:lineno]} needs to happen before #{@conf_files[s][:file]},#{@conf_files[s][:lineno]}"
          end
        end

        _load_passenger_location = @conf_files[:load][:match][1]
        if @conf_files[:root]
          unless _load_passenger_location == _root_passenger_location = @conf_files[:root][:match][2]
            raise "Passenger module location #{_load_passenger_location} and PassengerRoot setting #{_root_passenger_location} should be the same."
          end
        end

        _load_passenger_prefix = @conf_files[:load][:match][2]
        if @conf_files[:ruby]
          unless _load_passenger_prefix == _ruby_passenger_prefix = @conf_files[:ruby][:match][2]
            raise "Passenger module prefix #{_load_passenger_prefix} and PassengerRuby prefix #{_ruby_passenger_prefix} should be the same."
          end
        end
      end

      @conf_checked = true
    end

    def drill_down(_c)
      @_order ||= 0
      _c = File.expand_path(_c)
      File.open(_c).each_line do |line|
        @_conf_strings.each do |k,v|
          if m = line.match(v)
            _exists = @conf_files[k]
            raise "#{k} was already found in #{_exists[:file]},#{_exists[:lineno]} for #{_c},#{$.}" if _exists
            @conf_files[k] = { :file => _c, :lineno => $., :match => m, :order => @_order += 1 }
          end
        end

        if m = line.match(/^\s*Include\s+(['"]?)(\S+)\1/i)
          # apache includes are commonly file globs
          Dir.glob(m[2]).each do |f|
            drill_down(f)
          end
        end
      end
    end


    def recursive_tracking(_c)
      _c.each do |c|
        _filename = c[:file]
        _new = dir_handle.grep(/^\s*Include.*#{Regexp.escape(_filename)}/i)
        unless _new.size > 0
          # do some other things
        end

        if _new.find{|c| c[:file] == conf}
          return true
        end

        ret = recursive_tracking(_new)
        if ret
          @includes << c
        else
          @includes.pop
        end
        return ret
      end
      return false
    end

    private
    def from_server(s)
      @httpd_string ||= `#{@@httpd_cmd} -V`
      @httpd_string.match(/#{s}="([^"]+)"/i)[1]
    end
  end
end
