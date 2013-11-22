require 'ipaddress'

module Knife
  module Vserver
    class Interface

      attr_accessor :device
      attr_accessor :address
      attr_accessor :netmask
      attr_accessor :is_tinc_interface
      attr_accessor :device_id
      attr_accessor :prefix
      attr_accessor :broadcast

      def initialize(address)
        ip = IPAddress(address.to_s.strip)
        @address = ip.address
        @netmask = ip.netmask
        @prefix = ip.prefix
        @broadcast = ip.broadcast.to_s
        @is_tinc_interface = false
        @device_id = -1
      end

      def to_s
        "#{@address}:#{@device}"
      end

      def clone
        i = Interface.new("#{@address}/#{@netmask}")
        i.device_id = @device_id
        i.is_tinc_interface = @tinc_interface
        i.device = @device
        i
      end

      def self.reorder_device_ids(interfaces)
        result = Array.new
        interfaces.each { |i| result << i.clone }
        for i in 0..result.count - 1
          result[i].device_id = i
        end
        result
      end
    end
  end
end
