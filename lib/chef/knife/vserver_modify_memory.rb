require 'chef/knife/vserver_base'

class Chef
  class Knife
    class VserverModifyMemory < VserverBase

      banner 'knife vserver modify memory SERVER (options)'

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

      option :container_ram,
        :short => "-R RAM",
        :long => "--container-ram",
        :description => "Amount of Ram (in MB) for the container",
        :proc => Proc.new { |ram| ram.strip },
        :default => nil

      option :container_swap,
        :short => "-S SWAP",
        :long => "--container-swap",
        :description => "Amount of Swap (in MB) for the container",
        :proc => Proc.new { |swap| swap.strip },
        :default => nil

      def run
        config[:manual] = true
        super
      end

      def process(node, session)
        if config[:container_name].to_s.empty?
          ui.error("No container name defined")
          exit 1
        end

        if config[:container_ram].nil? || config[:container_swap].nil?
          ui.error("Ram and/or Swap must be defined")
          exit 1
        end

        host = ::Knife::Vserver::Host.create(node, session)
        container = host.containers.select { |n| n.name == config[:container_name] }.first
        if container.nil?
          ui.error("Container #{config[:container_name]} doesn't exist on #{host.node[:fqdn]}")
          exit 1
        end

        container.ram = config[:container_ram].to_i * 1024 ** 2 unless config[:container_ram].nil?
        container.swap = config[:container_swap].to_i * 1024 ** 2 unless config[:container_swap].nil?

        host.apply_memory_limits(container)
        ui.info("done")
      end
    end
  end
end