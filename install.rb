config_file = File.join(File.dirname(__FILE__),'..','..','..','config','aws_sdb_proxy.yml')
unless File.exists?(config_file)
  config_template = <<_YAML
development:
  aws_access_key_id: 
  aws_secret_access_key: 
  salt: your_aws_sdb_proxy_secret_salt_here
  port: 8888

test:
  aws_access_key_id: 
  aws_secret_access_key: 
  salt: your_aws_sdb_proxy_secret_salt_here
  port: 8888

production:
  aws_access_key_id: 
  aws_secret_access_key: 
  salt: your_aws_sdb_proxy_secret_salt_here
  port: 8888
_YAML
  File.open(config_file, 'w') do |f|
    f.write config_template
  end
end
puts <<_MSG

AwsSdbProxy depends on the aws-sdb gem by Tim Dysinger; install it with

  gem install aws-sdb

now.

_MSG
