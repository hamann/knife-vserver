require 'chef/knife/vserver_base'

class Chef
  class Knife
    class VserverRemoveAddress < VserverBase

      banner 'knife vserver remove address SERVER (options)'

      deps do
        require 'net/ssh'
        require 'net/ssh/multi'
        require 'chef/knife/ssh'
        require 'chef/node'
        require 'knife-vserver'
        require 'ipaddress'
      end

      option :attribute,
        :short => "-a ATTR",
        :long => "--attribute ATTR",
        :description => "The attribute to use for opening the connection - default depends on the context",
        :proc => Proc.new { |key| Chef::Config[:knife][:ssh_attribute] = key.strip }

      option :ssh_user,
        :short => "-x USERNAME",
        :long => "--ssh-user USERNAME",
        :description => "The ssh username"

      option :ssh_password,
        :short => "-P PASSWORD",
        :long => "--ssh-password PASSWORD",
        :description => "The ssh password"

      option :ssh_port,
        :short => "-p PORT",
        :long => "--ssh-port PORT",
        :description => "The ssh port",
        :proc => Proc.new { |key| Chef::Config[:knife][:ssh_port] = key.strip }

      option :ssh_gateway,
        :short => "-G GATEWAY",
        :long => "--ssh-gateway GATEWAY",
        :description => "The ssh gateway",
        :proc => Proc.new { |key| Chef::Config[:knife][:ssh_gateway] = key.strip }

      option :forward_agent,
        :short => "-A",
        :long => "--forward-agent",
        :description => "Enable SSH agent forwarding",
        :boolean => true

      option :identity_file,
        :short => "-i IDENTITY_FILE",
        :long => "--identity-file IDENTITY_FILE",
        :description => "The SSH identity file used for authentication"

      option :host_key_verify,
        :long => "--[no-]host-key-verify",
        :description => "Verify host key, enabled by default.",
        :boolean => true,
        :default => true

      option :sudo_required,
        :short => "-z",
        :long => "--sudo-required",
        :description => "Use sudo",
        :boolean => true,
        :default => false

      option :container_name,
        :short => "-C NAME",
        :long => "--container-name",
        :description => "Name of the new container",
        :proc => Proc.new { |name| name.strip },
        :default => nil

      option :container_addresses,
        :short => "-I ADDRESSES",
        :long => "--container-addresses",
        :description => "Comma seperated list of IP Addresses to remove (e.g. \"192.168.10.2/24, 10.20.20.16/26\")",
        :proc => Proc.new { |addresses| addresses.split(',')},
        :default => Array.new

      def run
        config[:manual] = true
        super
      end

      def process(node, session)
        if config[:container_name].to_s.empty?
          ui.error("No container name defined")
          exit 1
        end

        if config[:container_addresses].nil? || config[:container_addresses].count == 0
          ui.error("No address defined")
          exit 1
        end

        host = ::Knife::Vserver::Host.create(node, session)
        container = host.containers.select { |n| n.name == config[:container_name] }.first
        if container.nil?
          ui.error("Container #{config[:container_name]} doesn't exist on #{host.node[:fqdn]}")
          exit 1
        end

        interfaces = Array.new
        config[:container_addresses].each do |addr| 
          iface = ::Knife::Vserver::Interface.new(addr.strip)
          interfaces << iface
        end

        interfaces.each do |iface|
          iface_to_delete = nil
          container.interfaces.each do |c_iface|
            if c_iface.address == iface.address &&
              c_iface.netmask == iface.netmask
              iface_to_delete = c_iface
              break
            end
          end
          unless iface_to_delete
            ui.error("#{iface.address}/#{iface.prefix} doesn't exist!")
            exit 1
          end
          
          iface.device = iface_to_delete.device
          iface.device_id = iface_to_delete.device_id
        end

        host.remove_interfaces(container, interfaces) 
        ui.info("done")
      end
    end
  end
end
