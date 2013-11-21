require 'chef/knife/vserver_base'

class Chef
  class Knife
    class VserverList < VserverBase

      banner 'knife vserver list QUERY (options)'

      deps do
        require 'net/ssh'
        require 'net/ssh/multi'
        require 'chef/knife/ssh'
        require 'chef/node'
        require 'knife-vserver'
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

      option :manual,
        :short => "-m",
        :long => "--manual-list",
        :boolean => true,
        :description => "QUERY is a space separated list of servers",
        :default => false

      def run
        super
      end

      def process(node, session)
        h = ::Knife::Vserver::Host.create(node, session)
        ui.info "\nKernel: #{h.kernel_version}"
        ui.info "util-vserver: #{h.util_vserver_version}"
        ui.info "cgroups enabled: #{h.cgroups_enabled}"
        ui.info "configuration path: #{h.config_path}\n\n"

        h.containers.sort { |n, m| n.ctx <=> m.ctx }.each do |c|
          ui.info "\tContext:\t#{c.ctx}"
          ui.info "\tName:\t\t#{c.name}"
          ui.info "\tHostname:\t#{c.hostname}"
          ui.info "\tIs Running:\t#{c.is_running}"
          ui.info "\tInterfaces:"
          c.interfaces.each {|i| ui.info("\t\t\t#{i.address}\t#{i.device_id}:#{i.device}")}
          ui.info "\tRam:\t\t#{c.ram_to_s}"
          ui.info "\tSwap:\t\t#{c.swap_to_s}"
          ui.info "\n\n"
        end
      end
    end
  end
end
