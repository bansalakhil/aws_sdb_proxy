require 'webrick'
require 'yaml'
require File.join(File.dirname(__FILE__),'sdb_servlet')

# AwsSdbProxy::Server::
#    WEBrick based HTTP server including the SdbServlet.
#    
# AwsSdbProxy::SdbServlet::
#    Servlet for proxying requests form ActiveResource models to Amanzon's
#    SimpleDB web service.
module AwsSdbProxy

  CONFIG = YAML.load_file(File.join(RAILS_ROOT,'config','aws_sdb_proxy.yml'))[RAILS_ENV] rescue {}
  # configuration via environment overrides config file
  CONFIG.merge!({
    'aws_access_key_id'     => (ENV['AWS_ACCESS_KEY_ID'] || CONFIG['aws_access_key_id']),
    'aws_secret_access_key' => (ENV['AWS_SECRET_KEY'] || CONFIG['aws_secret_access_key']),
    'port'                  => (ENV['AWS_SDB_PROXY_PORT'] || CONFIG['port']),
    'salt'                  => (ENV['AWS_SDB_PROXY_SALT'] || CONFIG['salt'])
  })

  if !CONFIG || [ CONFIG['aws_access_key_id'], CONFIG['aws_secret_access_key'] ].any?(&:blank?)
    STDERR.puts "Please set your AWS credentials in aws_sdb_proxy.yml or via environment first!"
    exit 1
  end

   SDB_SERVICE = AwsSdb::Service.new(:logger => Logger.new(nil), :access_key_id => CONFIG['aws_access_key_id'], :secret_access_key => CONFIG['aws_secret_access_key'])

  # This is only needed for aws-sdb 0.1.1, but will do no harm when
  # used with 0.1.2 (and probably beyond).
  # Monkeypatching AwsSdb::Service to use newer API version for Query operations
  # blessing us with the intersection feature we need so desperately :-)
  class << SDB_SERVICE
    protected

    def call_with_enhanced_query(method, params)
      def params.merge!(h, &block)
        h.update('Version' => '2007-11-07') if h['Version'] == '2007-02-09' && self['Action'] == 'Query'
        update(h, &block)
      end
      call_without_enhanced_query(method, params)
    end

    alias_method_chain :call, :enhanced_query
  end

  # WEBrick based HTTP server including the SdbServlet for proxying requests
  # form ActiveResource models to Amanzon's SimpleBD web service.
  class Server
    
    # Start the server either in foreground or as a background daemon.
    def self.start(options = {})
      unless options[:foreground]
        WEBrick::Daemon.start { run }
      else
        run(:debug => true)
      end
    end
    
    protected
      # Configure the actual server and run it
      def self.run(options = {})
        log_file = File.join(RAILS_ROOT,'log','aws_sdb_proxy_server.log')
        server_options = { :Port => (CONFIG['port'] || 8888) }
        server_options[:Logger] = Logger.new(log_file) unless options[:debug]
        s = WEBrick::HTTPServer.new(server_options)
        s.logger.level = WEBrick::Log::DEBUG if options[:debug]
        s.mount('/', AwsSdbProxy::SdbServlet)
        trap('INT'){ s.shutdown }
        pid_file = File.join(RAILS_ROOT,'tmp','pids','aws_sdb_proxy.pid')
        File.open(pid_file,'w') do |f|
          f.write(Process.pid)
        end
        s.start
        FileUtils.rm(pid_file)
      end
  end
end
