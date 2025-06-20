# lib/json_rpc_handler.rb
# Replacement for json_rpc_handler gem to support Ruby 2.7.3

require 'json'

module JsonRpcHandler
  class Server
    def initialize
      @handlers = {}
    end
    
    def on(method_name, &block)
      @handlers[method_name.to_s] = block
    end
    
    def handle(request_json)
      request = parse_request(request_json)
      return build_parse_error if request.nil?
      
      method_name = request["method"]
      params = request["params"] || {}
      id = request["id"]
      
      if @handlers.key?(method_name)
        begin
          result = @handlers[method_name].call(params)
          build_success_response(id, result)
        rescue StandardError => e
          build_error_response(id, -32603, "Internal error", e.message)
        end
      else
        build_error_response(id, -32601, "Method not found")
      end
    end
    
    def call(method_name, params = {})
      if @handlers.key?(method_name.to_s)
        @handlers[method_name.to_s].call(params)
      else
        raise "Method not found: #{method_name}"
      end
    end
    
    private
    
    def parse_request(json_string)
      JSON.parse(json_string)
    rescue JSON::ParserError
      nil
    end
    
    def build_success_response(id, result)
      {
        "jsonrpc" => "2.0",
        "id" => id,
        "result" => result
      }
    end
    
    def build_error_response(id, code, message, data = nil)
      error = {
        "code" => code,
        "message" => message
      }
      error["data"] = data if data
      
      {
        "jsonrpc" => "2.0",
        "id" => id,
        "error" => error
      }
    end
    
    def build_parse_error
      build_error_response(nil, -32700, "Parse error")
    end
  end
  
  # Class methods for backward compatibility
  class << self
    def handle(request_json, &block)
      server = Server.new
      server.instance_eval(&block) if block_given?
      server.handle(request_json)
    end
  end
end

# Notification helper (if needed by MCP)
module JsonRpcHandler
  class Notification
    def initialize(method, params = {})
      @method = method
      @params = params
    end
    
    def to_json
      JSON.generate({
        "jsonrpc" => "2.0",
        "method" => @method,
        "params" => @params
      })
    end
  end
end