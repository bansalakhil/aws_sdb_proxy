require 'aws_sdb'
require 'digest/sha2'

module AwsSdbProxy

  # Servlet for proxying requests form ActiveResource models to Amanzon's
  # SimpleBD web service.
  # Request URIs must follow this schema:
  #
  #  http://host:port/:simple-db-domain/:resource[/:id].xml
  #
  class SdbServlet < WEBrick::HTTPServlet::AbstractServlet
  
    attr_reader :logger
  
    # reload servlet on every request when debugging
    def self.get_instance config, *options # :nodoc:
      load __FILE__ if config[:Logger].debug?
      self.new config, *options
    end
  
    # handle GET requests (requesting collections and elements). This will
    # also support SimpleDB query syntax given in the following form:
    #  http://host:port/:simple-db-domain/:resource/query.xml?:simpledb_query
    # Use it from ActiveResource with:
    #  find(:all, :from => :query, :params => "<my SimpleDB query string>")
    def do_GET(req, res)
      domain, resource, id, format = parse_request_path(req.path_info)
      if domain && resource && id && format == 'xml' # element or query
        unless id == 'query'
          attributes = sdb_get_item(domain, "#{resource}_#{id}")
          raise WEBrick::HTTPStatus::NotFound unless attributes
          res.body = to_xml(resource, attributes)
        else
          logger.debug "Query string: #{req.query.inspect}"
          items = sdb_get_items(domain, resource, req.query.keys.first).collect {|item| sdb_get_item(domain, item) }
          res.body = to_xml_array(resource, items)
        end

      elsif domain && resource && format == 'xml'    # collection
        logger.debug "Additonal query params: #{req.query.inspect}"
        items = sdb_get_items(domain, resource, req.query).collect {|item| sdb_get_item(domain, item) }
        res.body = to_xml_array(resource, items)

      else                                           # unsupported format
        raise WEBrick::HTTPStatus::UnsupportedMediaType, "Only XML formatted requests are supported."
      end
      logger.debug "Fetched requested item(s), responding with:\n#{res.body}"
      res['Content-Type'] = "application/xml"
      raise WEBrick::HTTPStatus::OK
    end
  
    # handle POST requests (create new elements)
    def do_POST(req, res)
      domain, resource, id, format = parse_request_path(req.path_info)
      attributes = from_xml(resource, req.body)
      attributes['id'] = generate_id(req.body)
      attributes['created-at'] = attributes['updated-at'] = Time.now.iso8601

      logger.debug "Creating item with attributes: #{attributes.inspect}"
      sdb_put_item(domain, attributes, false)

      res.body = to_xml(resource, attributes)
      res['location'] = "/#{domain}/#{resource}/#{id}.#{format}"
      res['Content-Type'] = "application/xml"
      raise WEBrick::HTTPStatus::Created
    end
  
    # handle PUT requests (update existing elements)
    def do_PUT(req, res)
      domain, resource, id, format = parse_request_path(req.path_info)
      attributes = from_xml(resource, req.body)
      attributes['updated-at'] = Time.now.iso8601
      logger.debug "Updating item with attributes: #{attributes.inspect}"
      sdb_put_item(domain, attributes, true)
      raise WEBrick::HTTPStatus::OK
    end

    # handle DELETE requests (delete elements)
    def do_DELETE(req, res)
      domain, resource, id, format = parse_request_path(req.path_info)
      sdb_delete_item(domain, "#{resource}_#{id}")
      raise WEBrick::HTTPStatus::OK
    end
  
    protected

      # Split request URI into +domain+, +resource+, +id+ and +format+
      def parse_request_path(path_info)
        case path_info
        when /\A\/([^\/.?]+)\/([^\/.?]+)\Z/
          domain, resource, id, format = $1, $2, nil, nil
        when /\A\/([^\/.?]+)\/([^\/.?]+)\.(.+)\Z/
          domain, resource, id, format = $1, $2, nil, $3
        when /\A\/([^\/.?]+)\/([^\/.?]+)\/([^\/.?]+)\Z/
          domain, resource, id, format = $1, $2, $3, nil
        when /\A\/([^\/.?]+)\/([^\/.?]+)\/([^\/.?]+)\.(.+)\Z/
          domain, resource, id, format = $1, $2, $3, $4
        else
          raise WEBrick::HTTPStatus::BadRequest, "Invalid Request Format #{path_info}, please stick to :resource[/:id[.:format]]"
        end
        logger.debug "Processing Domain: #{domain}, Resource: #{resource}, id: #{id}, format: #{format}"
        # .dasherize added as suggested by Jason Fox on 2008-04-14 (waiting for field report)
        return domain, resource.dasherize, id, format
      end 
      
      # Convert XML formatted element into attribute list
      def from_xml(resource, request_body)
        attributes = {}
        REXML::XPath.each(REXML::Document.new(request_body), "/#{resource.singularize}/*") do |attr|
          attributes["#{attr.name}"] = "#{attr.text}"
        end
        attributes.update('_resource' => resource)
      end
      
      # Generate XML from attribute list
      def to_xml_attributes(xml_builder, resource, attributes)
        xml_builder.tag! resource.singularize do |xml|
          attributes.each do |name, value|
            next if name == '_resource'
            options = {}
            options.update(:type => :datetime) if %w(created-at updated-at).include?(name)
            options.update(:type => :integer) if name == 'id'
            xml.tag! name, value, options
          end
        end
      end
      
      # Generate XML for element
      def to_xml(resource, attributes)
        document = ''
        xml_builder = Builder::XmlMarkup.new(:target => document, :indent => 2)
        xml_builder.instruct!
        to_xml_attributes(xml_builder, resource, attributes)
        document
      end
      
      # Generate XML for collection
      def to_xml_array(resource, items)
        document = ''
        xml_builder = Builder::XmlMarkup.new(:target => document, :indent => 2)
        xml_builder.instruct!
        xml_builder.tag!(resource, :type => :array) do |xml|
          items.each do |attributes|
            next unless attributes
            to_xml_attributes(xml_builder, resource, attributes)
          end
        end
        document
      end
      
      # Query SimpleDB for all item names in a collection
      def sdb_get_items(domain, resource, params = {})
        raising_service_unavailable_on_exception do
          query = "['_resource' = '#{resource}']"
          unless params.is_a?(String)
            params.each do |key, value|
              query << " intersection ['#{key}' = '#{value}']"
            end
          else # SimpleDB query string given
            query << " intersection #{params}"
          end
          logger.debug "Effective query: #{query}"
          items = AwsSdbProxy::SDB_SERVICE.query(domain, query)
          items.flatten!.reject!(&:blank?)
          logger.debug "Items from SDB: #{items.inspect}"
          return items
        end
      end
      
      # Query SimpleDB for element
      def sdb_get_item(domain, item_name)
        raising_service_unavailable_on_exception do
          attributes = AwsSdbProxy::SDB_SERVICE.get_attributes(domain, item_name)
          logger.debug "Attributes from SDB: #{attributes.inspect}"
          return attributes['id'] ? attributes : nil
        end
      end

      # Update element in SimpleDB
      def sdb_put_item(domain, attributes, replace = false)
        raising_service_unavailable_on_exception do
          AwsSdbProxy::SDB_SERVICE.put_attributes(domain, "#{attributes['_resource']}_#{attributes['id']}", attributes, replace)
        end
      end

      # Delete element in SimpleDB
      def sdb_delete_item(domain, item_name)
        raising_service_unavailable_on_exception do
          AwsSdbProxy::SDB_SERVICE.delete_attributes(domain, item_name)
        end
      end

      # Generate unique primary key (+id+) using a SHA512 hash algorithm on 
      # the request request_body, combined with a timestamp and a configurable
      # salt.
      def generate_id(request_body)
        Digest::SHA512.hexdigest("#{request_body}#{Time.now}#{AwsSdbProxy::CONFIG['salt']}").to_i(base=16).to_s
      end
      
      # Encapsule SimpleDB requests in wrapper raising
      # HTTPStatus::ServiceUnavailable on errors.
      def raising_service_unavailable_on_exception
        yield if block_given?
      rescue
        logger.error $!
        raise WEBrick::HTTPStatus::ServiceUnavailable
      end
  end
end
