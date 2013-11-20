module Knife
  module Vserver
    class Interface

      attr_accessor :device
      attr_accessor :address
      attr_accessor :netmask
      attr_accessor :is_tinc_interface
      attr_accessor :device_id

      def initialize
        @is_tinc_interface = false
        @device_id = -1
      end

      def to_s
        "#{@address}:#{@device}"
      end
    end
  end
end
