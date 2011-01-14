require 'time'
require 'rack/file'
require 'rack/utils'

module Rack
  if "java" == RUBY_PLATFORM then
    # use jcoffeescript implementation
    require 'java'
    require ::File.dirname(__FILE__) + '/../jcoffeescript-1.0.jar' 
    class CoffeeScriptCompiler
      def initialize(opts = {})
        options = []
        options << org.jcoffeescript.Option::BARE if opts[:nowrap] or opts[:bare]
        @compiler = org.jcoffeescript.JCoffeeScriptCompiler.new options
      end
      
      def compile(source)
        @compiler.compile(source)
      end
    end
  else
    # use shell out to coffee implementation
    require 'open3'
    class CoffeeScriptCompiler
      def initialize(opts = {})
        @command = ['coffee', '-p']
        @command.push('--bare') if opts[:nowrap] or opts[:bare]
        @command.push('-e')
        @command = @command.join(' ')
      end
      
      def compile(source)
        return Open3.popen3(@command) do |stdin, stdout, stderr|
          stdin.puts source
          stdin.close
          stdout.read
        end
      end
    end
  end
  
  class Coffee
    F = ::File
    
    attr_accessor :urls, :root
    DEFAULTS = {:static => true}
    
    def initialize(app, opts={})
      opts = DEFAULTS.merge(opts)
      @app = app
      @urls = *opts[:urls] || '/javascripts'
      @root = opts[:root] || Dir.pwd
      @server = opts[:static] ? Rack::File.new(root) : app
      @cache = opts[:cache]
      @ttl = opts[:ttl] || 86400
      @compiler = CoffeeScriptCompiler.new opts
    end
    
    def brew(coffee)
      script = ''
      F.open(coffee).each_line { |line| script << line }
      [@compiler.compile(script)]
    end
    
    def call(env)
      path = Utils.unescape(env["PATH_INFO"])
      return [403, {"Content-Type" => "text/plain"}, ["Forbidden\n"]] if path.include?('..')
      return @app.call(env) unless urls.any?{|url| path.index(url) == 0} and (path =~ /\.js$/)
      coffee = F.join(root, path.sub(/\.js$/,'.coffee'))
      if F.file?(coffee)

        modified_time = F.mtime(coffee)

        if env['HTTP_IF_MODIFIED_SINCE']
          cached_time = Time.parse(env['HTTP_IF_MODIFIED_SINCE'])
          if modified_time - cached_time < 1
            return [304, {}, 'Not modified']
          end
        end

        headers = {"Content-Type" => "application/javascript", "Last-Modified" => F.mtime(coffee).httpdate}
        if @cache
          headers['Cache-Control'] = "max-age=#{@ttl}"
          headers['Cache-Control'] << ', public' if @cache == :public
        end
        [200, headers, brew(coffee)]
      else
        @server.call(env)
      end
    end
  end
end
