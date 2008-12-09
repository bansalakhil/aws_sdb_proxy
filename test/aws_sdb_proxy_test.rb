require 'test/unit'
require 'fileutils'
require 'rubygems'
require 'activeresource'

# Class for access tests to SDB (single word model name)
class Post < ActiveResource::Base
  self.site = "http://localhost:#{ENV['AWS_SDB_PROXY_PORT'] || 8888}"
  self.prefix = "/#{ENV['AWS_SDB_TESTDOMAIN']}/"
end

# Class for access tests to SDB (multi word model name)
class AnotherPost < ActiveResource::Base
  self.site = "http://localhost:#{ENV['AWS_SDB_PROXY_PORT'] || 8888}"
  self.prefix = "/#{ENV['AWS_SDB_TESTDOMAIN']}/"
end

class AwsSdbProxyTest < Test::Unit::TestCase

  def setup
    flunk "You need to set the environment variable AWS_SDB_TESTDOMAIN to an existing empty SDB domain for testing" unless ENV['AWS_SDB_TESTDOMAIN']

    # generate demo Rails project
    `rails aws_sdb_demo --force --database=sqlite3`
    assert_equal 0, $?

    # install aws_sdb_proxy plugin
    FileUtils.mkdir_p './aws_sdb_demo/vendor/plugins/aws_sdb_proxy'
    FileUtils.cp_r %w(init.rb install.rb uninstall.rb ./lib ./tasks), './aws_sdb_demo/vendor/plugins/aws_sdb_proxy'
    `cd aws_sdb_demo/vendor/plugins/aws_sdb_proxy; ruby ../../../script/runner ./install.rb`
    assert_equal 0, $?
    
    # Start proxy
    `cd aws_sdb_demo; rake aws_sdb:start_proxy`
    assert_equal 0, $?

    # make sure domain has no Posts in it and proxy is ready
    retries = 0
    begin
      Post.find(:all).each {|p| p.destroy}
      AnotherPost.find(:all).each {|p| p.destroy}
    rescue Errno::ECONNREFUSED
      retries += 1
      raise if retries >= 10
      sleep 1.0
      retry
    end
  end
  
  # test complete lifecyle of a SDB object
  def test_aws_sdb_proxy
    [Post, AnotherPost].each do |klass|
      # CREATE
      p1 = klass.create(:title => 'Testpost number one')
      assert_kind_of(klass, p1)

      p2 = klass.create(:title => 'Testpost number two')
      assert_kind_of(klass, p2)

      # UPDATE
      p1.body = 'Content is king'
      assert p1.save, "Save to SDB failed"
    
      # QUERY
      p = klass.find(:first, :params => { :title => 'Testpost number one' })
      assert_equal('Content is king', p.body)
    
      posts = klass.find(:all, :from => :query, :params => "['title' starts-with 'Testpost']")
      assert_equal(2, posts.size)
    
      # DELETE
      assert_nothing_raised do
        posts.each {|p| p.destroy}
      end

      posts = klass.find(:all)
      assert_equal(0, posts.size)
    end
  end

  def teardown
    # Stop proxy
    `cd aws_sdb_demo; rake aws_sdb:stop_proxy`
    FileUtils.rm_r './aws_sdb_demo'
  end

end
