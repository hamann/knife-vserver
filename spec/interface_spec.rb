require_relative 'spec_helper'
include Knife::Vserver

describe 'Interface' do
  describe '.self_reorder_device_ids' do
    it 'should reorder the device ids' do
      interfaces = Array.new
      s1 = Interface.new('192.168.0.1/24')
      s1.device = 'a'
      s1.device_id = 0
      interfaces << s1

      s2 = Interface.new('192.168.0.2/24')
      s2.device = 'b'
      s2.device_id = 1
      interfaces << s2

      s3 = Interface.new('192.168.0.3/24')
      s3.device = 'c'
      s3.device_id = 2
      interfaces << s3

      s5 = Interface.new('192.168.0.3/24')
      s5.device = 'e'
      s5.device_id = 4
      interfaces << s5

      new_interfaces = Interface.reorder_device_ids(interfaces)
      expect(new_interfaces.select { |i| i.device == 'a' }.first.device_id).to eq(0)
      expect(new_interfaces.select { |i| i.device == 'b' }.first.device_id).to eq(1)
      expect(new_interfaces.select { |i| i.device == 'c' }.first.device_id).to eq(2)
      expect(new_interfaces.select { |i| i.device == 'e' }.first.device_id).to eq(3)
    end
  end
end
