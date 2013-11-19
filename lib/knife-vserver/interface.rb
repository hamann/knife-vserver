module Knife
  module Vserver
    class Interface

      attr_accessor :device
      attr_accessor :address
      attr_accessor :netmask

      def to_s
        "#{@address}:#{@device}"
      end
    end
  end
end
