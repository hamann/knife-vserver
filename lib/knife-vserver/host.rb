module Knife
  module Vserver
    class Host
      
      attr_accessor :containers
      attr_accessor :node
      attr_accessor :config_path
      attr_accessor :cgroups_enabled
      attr_accessor :session

      def initialize(node)
        @config_path = '/etc/vservers'
        @node = node
        @cgroups_enabled = false
        @containers = Array.new
        @session = nil
      end

      def container_exist?(name)
        false #@containers.select { |n| n.name == name }.count > 0
      end

      def add_new_container(container)
        validate_new_container(container)
        load_dummy_module
        create_container(container)
      end

      def create_container(container)
        container.ctx = next_context_id
        dummy_ifs = unused_dummy_interfaces

        cmd_addresses = Array.new
        container.interfaces.each do |iface|
          next if iface.is_tinc_interface

          iface.device = dummy_ifs.slice!(0)
          cmd_addresses << "--interface #{iface.device}:#{iface.address}/#{iface.netmask}"
        end

        create_cmd_args = "--hostname #{container.hostname} --context #{container.ctx} " +
          "#{cmd_addresses.join(" ")} -- -d #{container.distribution}"

        template_path = "#{@config_path}/templates/#{container.distribution}-base.tar.gz"
        if ShellCommand.exec("test -e #{template_path}",
                             session,
                             { :dont_raise_error => true }).succeeded?
          create_cmd = "sudo vserver #{container.name} build -m template " +
            "#{create_cmd_args} -t #{template_path}"
        else
          create_cmd = "sudo vserver #{container.name} build -m debootstrap #{create_cmd_args}"
        end

        puts "Executing #{create_cmd}"
        #ShellCommand.exec(create_cmd, session)

        add_flags(container)
        apply_memory_limits(container)
        mark_for_start_at_boot(container)
        add_tinc_interfaces(container)

        @containers << container

        #puts "Starting container #{container.name}"
        #ShellCommand.exec("sudo vserver #{container.name} start", session)
        #container.is_running = true
      end

      def add_tinc_interfaces(container)
        tinc_ifaces = container.interfaces.select { |n| n.is_tinc_interface }
        return if tinc_ifaces.count == 0
        tinc_ifaces.each do |iface|
          path = "#{container.config_path}/interfaces/#{iface.device_id}"
          cmd = "
          mkdir #{path};
          echo #{iface.address} > #{path}/ip;
          echo #{iface.device} > #{path}/dev;
          echo #{iface.netmask} > #{path}/mask;
          "
          ShellCommand.exec("sudo sh -c \"#{cmd}\"", session)

          ip = IPAddress("#{iface.address}/#{iface.netmask}")
          path = "/etc/tinc/#{iface.device}/up.d/vserver-up"
          cmd = "echo ip addr add #{iface.address}/#{ip.prefix} dev #{iface.device} > #{path}"
          ShellCommand.exec("sudo sh -c \"#{cmd}\"", session)

          path = "/etc/tinc/#{iface.device}/down.d/vserver-down"
          cmd = "echo ip addr del #{iface.address}/#{ip.prefix} dev #{iface.device} > #{path}"
          ShellCommand.exec("sudo sh -c \"#{cmd}\"", session)
        end
      end

      def mark_for_start_at_boot(container)
        path = "#{container.config_path}/apps/init/mark"
        ShellCommand.exec("echo default | sudo tee #{path}", session)
      end

      def add_flags(container)
        path = "#{container.config_path}/flags"
        cmd = "echo \"VIRT_MEM\nVIRT_UPTIME\nVIRT_LOAD\nVIRT_CPU\" | sudo tee #{path}"
        ShellCommand.exec(cmd, session)
      end

      def apply_memory_limits(container)
        apply_memory_limits_cgroup(container)
        apply_memory_limits_rlimits(container)
      end

      def apply_memory_limits_cgroup(container)
        ram = container.ram
        swap = container.ram + container.swap
        cgroup_path = "#{container.config_path}/cgroup"
        cmd = "
        mkdir -p #{cgroup_path};
        echo #{ram} > #{cgroup_path}/memory.limit_in_bytes;
        echo #{swap} > #{cgroup_path}/memory.memsw.limit_in_bytes;
        "
        ShellCommand.exec("sudo sh -c \"#{cmd}\"", session)

        if container.is_running && @cgroups_enabled
          puts "Applying cgroup memory limits to running instance"
          cgroup_path = "/dev/cgroup/#{container.name}"
          cmd = "
          echo #{ram} > #{cgroup_path}/memory.limit_in_bytes;
          echo #{swap} > #{cgroup_path}/memory.memsw.limit_in_bytes;
          "
          ShellCommand.exec("sudo sh -c \"#{cmd}\"", session)
        end
      end

      def apply_memory_limits_rlimits(container)
        rlimit_path = "#{container.config_path}/rlimits"
        ram = container.ram / 4
        swap = container.ram + container.swap / 4
        cmd = "
        mkdir -p #{rlimit_path};
        echo #{ram} > #{rlimit_path}/rss.soft;
        echo #{swap} > #{rlimit_path}/rss.hard;
        "
        ShellCommand.exec("sudo sh -c \"#{cmd}\"", session)

        if container.is_running && !@cgroups_enabled
          puts "Applying rlimits memory limits to running instance"
          cmd = "
          vlimit -c #{container.ctx} -S --rss #{ram};
          vlimit -c #{container.ctx} --rss #{swap};
          "
          ShellCommand.exec("sudo sh -c \"#{cmd}\"", session)
        end
      end

      def next_context_id
        ids = Array(40000..40050)
        @containers.each do |c|
          ids.delete_if { |id| c.ctx.to_s == id.to_s }
        end
        ids.first
      end

      def unused_dummy_interfaces
        result = Array.new
        used = used_dummy_interfaces
        0.upto(39) do |idx|
          name = "dummy#{idx}"
          result << name unless used.include?(name)
        end
        result
      end

      def used_dummy_interfaces
        result = Array.new
        @containers.each do |c|
          c.interfaces.each do |iface|
            result << iface.device if iface.device =~ /dummy/
          end
        end
        result
      end

      def load_dummy_module
        ShellCommand.exec("sudo modprobe dummy numdummies=40", @session)
      end

      def validate_new_container(container)
        raise "Container #{container.name} already exists!" if container_exist?(container.name)
        raise "Container #{container.name} needs at least one ip address!" if container.interfaces.count == 0
        raise "Distribution #{container.distribution} isn't supported!" if container.distribution.match(/(squeeze|wheezy)/).nil?
        raise "Container #{container.name} has no hostname!" if container.hostname.nil?
        container.interfaces.each do |iface|
          raise "Device id for #{iface.address} is invalid!" if iface.device_id < 0
        end

        container.interfaces.select { |iface| iface.is_tinc_interface }.each do |iface|
          unless ShellCommand.exec("sudo test -e /etc/tinc/#{iface.device}", @session,
                               { :dont_raise_error => true }).succeeded?
            raise "This host isn't configured for vpn #{iface.device}!"
          end
        end
      end

      def self.create(node, session)
        host = Host.new(node)
        host.session = session
        return host unless ShellCommand.exec("sudo test -e #{host.config_path}", session, 
                                             { :dont_raise_error => true }).succeeded?

        host.cgroups_enabled = ShellCommand.exec("mount |grep vserver|grep cgroup", session,
                                                 { :dont_raise_error => true }).succeeded?

        entries = ShellCommand.exec("sudo ls -ls /etc/vservers | tail -n+2 |awk '{print $10}'", session).stdout.gsub(/\r/,"").strip.split("\n")
        entries.each do |n|

          c = Knife::Vserver::Container.new(n, host)
          next unless ShellCommand.exec("sudo test -d #{c.config_path} && sudo test -e #{c.config_path}/context", session,
                                        { :dont_raise_error => true }).succeeded?

          c.ctx = ShellCommand.exec("sudo cat #{c.config_path}/context", session).stdout.strip
          c.node_name = ShellCommand.exec("sudo cat #{c.config_path}/uts/nodename", session).stdout.strip
          c.is_running = ShellCommand.exec("sudo vserver-info #{c.name} RUNNING", 
                                           session, { :dont_raise_error => true }).succeeded?

          c.hostname = ShellCommand.exec("sudo vserver #{c.name} exec hostname -f", session).stdout.strip if c.is_running

          interface_path = "#{c.config_path}/interfaces"
          ShellCommand.exec("sudo ls -ls #{interface_path} | egrep \"^. d\" | awk '{print $10}'", session).stdout.gsub(/\r/,"").strip.split("\n").each do |if_n|
            iface = Interface.new
            iface.device_id = if_n
            iface.device = ShellCommand.exec("sudo cat #{interface_path}/#{if_n}/dev", session).stdout.strip
            iface.address = ShellCommand.exec("sudo cat #{interface_path}/#{if_n}/ip", session).stdout.strip
            if ShellCommand.exec("test -e #{interface_path}/#{if_n}/mask", session,
                                 { :dont_raise_error => true }).succeeded?
              iface.netmask = ShellCommand.exec("sudo cat #{interface_path}/#{if_n}/mask", session).stdout.strip
            end
            c.interfaces << iface
          end

          if host.cgroups_enabled &&
            ShellCommand.exec("sudo test -d #{c.config_path}/cgroup", session,
                              { :dont_raise_error => true }).succeeded?

            c.ram = ShellCommand.exec("sudo cat #{c.config_path}/cgroup/memory.limit_in_bytes", session).stdout.strip
            c.swap = ShellCommand.exec("sudo cat #{c.config_path}/cgroup/memory.memsw.limit_in_bytes", session).stdout.strip
          elsif ShellCommand.exec("sudo test -d #{c.config_path}/rlimits", session,
                                    { :dont_raise_error => true }).succeeded?

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
