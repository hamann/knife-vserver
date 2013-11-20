require 'chef/knife/vserver_base'

class Chef
  class Knife
    class VserverCreate < VserverBase

      banner 'knife vserver create SERVER (options)'

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
        :short => "-M NAME",
        :long => "--container-name",
        :description => "Name of the new container",
        :proc => Proc.new { |name| name.strip },
        :default => nil

      option :container_addresses,
        :short => "-I ADDRESSES",
        :long => "--container-addresses",
        :description => "ADDRESSES is a comma seperated list of ip addresses",
        :proc => Proc.new { |addresses| addresses.split(',') },
        :default => Array.new

      option :container_distribution,
        :short => "-D DISTRIBUTION",
        :long => "--container-distribution",
        :description => "The container distribution",
        :proc => Proc.new { |dist| dist.strip },
        :default => 'squeeze'

      option :container_hostname,
        :short => "-H HOSTNAME",
        :long => "--container-hostname",
        :description => "The hostname for the container",
        :proc => Proc.new { |name| name.strip },
        :default => nil

      option :container_memory,
        :short => "-R RAM",
        :long => "--container-ram",
        :description => "Amount of Ram (in MB) for the container",
        :proc => Proc.new { |ram| ram.strip },
        :default => 512

      option :container_swap,
        :short => "-S SWAP",
        :long => "--container-swap",
        :description => "Amount of Swap (in MB) for the container",
        :proc => Proc.new { |swap| swap.strip },
        :default => 512

      option :container_tinc,
        :short => "-T TINC",
        :long => "--container-tinc",
        :description => "Tinc configuration for the container, e.g. (-T \"test_vpn:172.10.10.1/16,172.10.10.16/16\")",
        :default => Hash.new

      def prepare_tinc(value)
        return if value.empty?

        result = Hash.new
        begin
          key, addresses = value.split(":")
          result[key] = { 'addresses' => addresses.split(",") }
        rescue
          ui.error("Could not parse argument for tinc configuration!")
        end
        result
      end

      def run
        config[:manual] = true
        super
      end

      def process(node, session)
        tinc = prepare_tinc(config[:container_tinc])

        h = ::Knife::Vserver::Host.create(node, session)
        container = ::Knife::Vserver::Container.new(config[:container_name], h)

        dev_id = 0
        config[:container_addresses].each do |addr|
          ip = IPAddress(addr.strip)
          iface = ::Knife::Vserver::Interface.new
          iface.address = ip.address
          iface.netmask = ip.netmask
          iface.device_id = dev_id
          dev_id = dev_id + 1

          container.interfaces << iface
        end

        if tinc.count > 0
          vpn = tinc.flatten[0]
          addresses = tinc.flatten[1]['addresses']
          addresses.each do |addr|
            ip = IPAddress(addr.strip)
            iface = ::Knife::Vserver::Interface.new
            iface.address = ip.address
            iface.netmask = ip.netmask
            iface.device = vpn
            iface.is_tinc_interface = true
            iface.device_id = dev_id
            dev_id = dev_id + 1

            container.interfaces << iface
          end
        end

        container.distribution = config[:container_distribution]
        container.hostname = config[:container_hostname]
        container.ram = config[:container_memory] * 1024 * 1024
        container.swap = config[:container_swap] * 1024 * 1024
        #container.is_running = true
        h.add_new_container(container)
      end
    end
  end
end
