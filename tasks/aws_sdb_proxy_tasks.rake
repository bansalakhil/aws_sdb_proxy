require 'aws_sdb'

namespace :aws_sdb do

  desc "Start AWS SimpleDB Proxy Server"
  task(:start_proxy => :environment) do
    require "aws_sdb_proxy/server"
    puts "Starting Server in background..."
    AwsSdbProxy::Server.start
  end

  desc "Stop AWS SimpleDB Proxy Server"
  task(:stop_proxy => :environment) do
    require "aws_sdb_proxy/server"
    puts "Stopping Server..."
    pid = File.open(File.join(RAILS_ROOT,'tmp','pids','aws_sdb_proxy.pid'), 'r').read.to_i
    Process.kill('INT', pid)
  end

  desc "Start AWS SimpleDB Proxy Server in foreground (do not daemonize)"
  task(:start_proxy_in_foreground => :environment) do
    require "aws_sdb_proxy/server"
    AwsSdbProxy::Server.start(:foreground => true)
  end

  desc "List all existing AWS SimpleDB Domains"
  task(:list_domains => :environment) do
    require File.join(File.dirname(__FILE__),'..','lib','aws_sdb_proxy','server')
    puts "* #{AwsSdbProxy::SDB_SERVICE.list_domains.first.join("\n* ")}"
  end

  desc "Create AWS SimpleDB Domain"
  task(:create_domain => :environment) do
    require "aws_sdb_proxy/server"
    domain = ENV['DOMAIN']
    unless domain.blank?
      puts "Creating Domain #{domain}..."
      AwsSdbProxy::SDB_SERVICE.create_domain(domain)
    else
      STDERR.puts "Please provide required parameter DOMAIN for this task:"
      STDERR.puts "  rake aws_sdb:create_domain DOMAIN=domain_to_be_created"
    end
  end

  desc "Delete AWS SimpleDB Domain"
  task(:delete_domain => :environment) do
    require "aws_sdb_proxy/server"
    domain = ENV['DOMAIN']
    unless domain.blank?
      puts "Deleting Domain #{domain}..."
      AwsSdbProxy::SDB_SERVICE.delete_domain(domain)
    else
      STDERR.puts "Please provide required parameter DOMAIN for this task:"
      STDERR.puts "  rake aws_sdb:create_domain DOMAIN=domain_to_be_deleted"
    end
  end
end