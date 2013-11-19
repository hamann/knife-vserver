module Knife
  module Vserver
    class Host
      
      attr_accessor :containers
      attr_accessor :node
      attr_accessor :config_path
      attr_accessor :cgroups_enabled

      def initialize(node)
        @config_path = '/etc/vservers'
        @node = node
        @cgroups_enabled = false
        @containers = Array.new
      end

      def self.create(node, session)
        host = Host.new(node)
        return host unless ShellCommand.exec("sudo test -e #{host.config_path}", session).succeeded?

        host.cgroups_enabled = ShellCommand.exec("mount |grep vserver|grep cgroup", session).succeeded?

        entries = ShellCommand.exec("sudo ls -ls /etc/vservers | tail -n+2 |awk '{print $10}'", session).stdout.gsub(/\r/,"").strip.split("\n")
        entries.each do |n|

          c = Knife::Vserver::Container.new(n, host)
          next unless ShellCommand.exec("sudo test -d #{c.config_path} && sudo test -e #{c.config_path}/context", session).succeeded?

          c.ctx = ShellCommand.exec("sudo cat #{c.config_path}/context", session).stdout.strip
          c.node_name = ShellCommand.exec("sudo cat #{c.config_path}/uts/nodename", session).stdout.strip
          c.is_running = ShellCommand.exec("sudo vserver-info #{c.name} RUNNING", session).succeeded?

          c.hostname = ShellCommand.exec("sudo vserver #{c.name} exec hostname -f", session).stdout.strip if c.is_running

          interface_path = "#{c.config_path}/interfaces"
          ShellCommand.exec("sudo ls -ls #{interface_path} | tail -n+2 |awk '{print $10}'", session).stdout.gsub(/\r/,"").strip.split("\n").each do |if_n|
            iface = Interface.new
            iface.device = ShellCommand.exec("sudo cat #{interface_path}/#{if_n}/dev", session).stdout.strip
            iface.address = ShellCommand.exec("sudo cat #{interface_path}/#{if_n}/ip", session).stdout.strip
            iface.netmask = ShellCommand.exec("sudo cat #{interface_path}/#{if_n}/mask", session).stdout.strip
            c.interfaces << iface
          end

          if host.cgroups_enabled
            c.ram = ShellCommand.exec("sudo cat #{c.config_path}/cgroup/memory.limit_in_bytes", session).stdout.strip
            c.swap = ShellCommand.exec("sudo cat #{c.config_path}/cgroup/memory.memsw.limit_in_bytes", session).stdout.strip
          else
            c.ram = ShellCommand.exec("sudo cat #{c.config_path}/rlimits/rss.soft", session).stdout.strip.to_i * 4 * 1024
            c.swap = ShellCommand.exec("sudo cat #{c.config_path}/rlimits/rss.hard", session).stdout.strip.to_i * 4 * 1024
          end

          host.containers << c 
        end
        host
      end
    end
  end
end
