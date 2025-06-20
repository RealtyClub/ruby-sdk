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
    
    def handle_request(request, method)
      # This method is expected by MCP::Server but not used in our implementation
      # The actual handling is done in the handle method
      raise NotImplementedError, "handle_request is not implemented in this JsonRpcHandler"
    end
    
    def call(method_name, params = {})
      if @handlers.key?(method_name.to_s)
        @handlers[method_name.to_s].call(params)
      else
        raise "Method not found: #{method_name}"
      end
    end
    
    def tools_list_handler(&block)
      @capabilities.support_tools
      @handlers[Methods::TOOLS_LIST] = block
    end
    
    def tools_call_handler(&block)
      @capabilities.support_tools
      @handlers[Methods::TOOLS_CALL] = block
    end
    
    private
    
    def parse_request(json_string)
      JSON.parse(json_string)
    rescue JSON::ParserError
      nil
    end
    
    def build_success_response(id, result)
      {
        jsonrpc: "2.0",
        id: id,
        result: result
      }
    end
    
    def build_error_response(id, code, message, data = nil)
      error = {
        code: code,
        message: message
      }
      error[:data] = data if data
      
      {
        jsonrpc: "2.0",
        id: id,
        error: error
      }
    end
    
    def build_parse_error
      build_error_response(nil, -32600, "Invalid Request", "Request must be an array or a hash")
    end
  end
  
  # Class methods for backward compatibility
  class << self
    def handle(request, &block)
      if request.is_a?(String)
        parsed_request = parse_request(request)
        return build_parse_error if parsed_request.nil?
      else
        parsed_request = request
      end
      
      # Convert string keys to symbols for internal processing
      parsed_request = symbolize_keys(parsed_request)
      
      method_name = parsed_request[:method]
      params = parsed_request[:params] || {}
      id = parsed_request[:id]
      is_notification = id.nil?
      
      begin
        handler = block.call(method_name)
        if handler.nil?
          # For notifications (id is nil), return nil instead of error response
          return nil if is_notification
          return build_error_response(id, -32601, "Method not found", method_name)
        elsif handler.respond_to?(:call)
          result = handler.call(params)
          # For notifications (id is nil), return nil instead of success response
          return nil if is_notification
          return build_success_response(id, result)
        else
          return nil if is_notification
          return build_error_response(id, -32601, "Method not found", method_name)
        end
      rescue StandardError => e
        return nil if is_notification
        return build_error_response(id, -32603, "Internal error", e.message)
      end
    end
    
    def handle_json(request_json, &block)
      parsed_request = parse_request(request_json)
      return build_parse_error.to_json if parsed_request.nil?
      
      # Convert string keys to symbols for internal processing
      parsed_request = symbolize_keys(parsed_request)
      
      method_name = parsed_request[:method]
      params = parsed_request[:params] || {}
      id = parsed_request[:id]
      is_notification = id.nil?
      
      begin
        handler = block.call(method_name)
        if handler.nil?
          # For notifications (id is nil), return nil instead of error response
          return nil if is_notification
          return build_error_response(id, -32601, "Method not found", method_name).to_json
        elsif handler.respond_to?(:call)
          result = handler.call(params)
          # For notifications (id is nil), return nil instead of success response  
          return nil if is_notification
          return build_success_response(id, result).to_json
        else
          return nil if is_notification
          return build_error_response(id, -32601, "Method not found", method_name).to_json
        end
      rescue StandardError => e
        return nil if is_notification
        return build_error_response(id, -32603, "Internal error", e.message).to_json
      end
    end
    
    private
    
    def parse_request(json_string)
      JSON.parse(json_string)
    rescue JSON::ParserError
      nil
    end
    
    def symbolize_keys(hash)
      case hash
      when Hash
        hash.transform_keys(&:to_sym).transform_values { |v| symbolize_keys(v) }
      when Array
        hash.map { |v| symbolize_keys(v) }
      else
        hash
      end
    end
    
    def build_success_response(id, result)
      {
        jsonrpc: "2.0",
        id: id,
        result: result
      }
    end
    
    def build_error_response(id, code, message, data = nil)
      error = {
        code: code,
        message: message
      }
      error[:data] = data if data
      
      {
        jsonrpc: "2.0",
        id: id,
        error: error
      }
    end
    
    def build_parse_error
      build_error_response(nil, -32600, "Invalid Request", "Request must be an array or a hash")
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