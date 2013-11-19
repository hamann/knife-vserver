module Knife
  module Vserver
    class Container

      attr_accessor :name
      attr_accessor :is_running
      attr_accessor :ctx
      attr_accessor :node_name
      attr_accessor :interfaces
      attr_accessor :config_path
      attr_accessor :host
      attr_accessor :hostname
      attr_accessor :ram
      attr_accessor :swap

      def initialize(name, host)
        @name = name
        @is_running = false
        @ctx = 0
        @node_name = ''
        @interfaces = Array.new
        @config_path = "#{host.config_path}/#{name}"
        @host = host
      end

      def ram_to_s
        "#{(ram.to_f / 1024 ** 2).to_i} MB"
      end

      def swap_to_s
        "#{((swap.to_f - ram.to_f) / 1024 ** 2).to_i} MB"
      end
    end
  end
end
