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
      attr_accessor :distribution

      def initialize(name, host)
        @name = name
        @is_running = false
        @ctx = 0
        @node_name = ''
        @interfaces = Array.new
        @config_path = "#{host.config_path}/#{name}"
        @host = host
        @distribution = ''
      end

      def ram_to_s
        "#{(@ram.to_f / 1024 ** 2).to_i} MB"
      end

      def swap_to_s
        "#{((@swap.to_f - ram.to_f) / 1024 ** 2).to_i} MB"
      end

      def self.prepare_tinc_from_config(config)
        return if config.empty?

        result = Hash.new
        begin
          key, addresses = config.split(":")
          result[key] = { 'addresses' => addresses.split(",") }
        rescue
          ui.error("Could not parse argument for tinc configuration!")
        end
        result
      end

      def self.create_new(config, h)
        container = Container.new(config[:container_name], h)
        dev_id = 0
        config[:container_addresses].each do |addr|
          iface = Interface.new(addr)
          iface.device_id = dev_id
          dev_id = dev_id + 1

          container.interfaces << iface
        end

        tinc = self.prepare_tinc_from_config(config[:container_tinc])
        if tinc && tinc.count > 0
          vpn = tinc.flatten[0]
          addresses = tinc.flatten[1]['addresses']
          addresses.each do |addr|
            iface = Interface.new(addr)
            iface.device = vpn
            iface.is_tinc_interface = true
            iface.device_id = dev_id
            dev_id = dev_id + 1

            container.interfaces << iface
          end
        end

        container.distribution = config[:container_distribution]
        container.hostname = config[:container_hostname]
        container.ram = config[:container_ram].to_i * 1024 ** 2
        container.swap = config[:container_swap].to_i * 1024 ** 2

        container
      end
    end
  end
end
