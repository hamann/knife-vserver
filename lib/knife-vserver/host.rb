module Knife
  module Vserver
    class Host
      
      attr_accessor :containers
      attr_accessor :node
      attr_accessor :config_path
      attr_accessor :cgroups_enabled
      attr_accessor :session
      attr_accessor :kernel_version
      attr_accessor :util_vserver_version

      def initialize(node)
        @config_path = '/etc/vservers'
        @node = node
        @cgroups_enabled = false
        @containers = Array.new
        @session = nil
        @kernel_version = 'unknown'
        @util_verserver_version = 'unknown'
      end

      def container_exists?(name)
        @containers.select { |n| n.name == name }.count > 0
      end

      def exec_ssh(cmd, raise_error = true)
        ShellCommand.exec("sudo " + cmd, @session, { :dont_raise_error => !raise_error })
      end

      def start_container(container)
        return if container.is_running
        exec_ssh("vserver #{container.name} start")
      end

      def stop_container(container)
        return unless container.is_running
        exec_ssh("vserver #{container.name} stop")
      end

      def delete_container!(container)
        exec_ssh("vserver #{container.name} stop") if container.is_running

        cmd = "echo y | sudo vserver #{container.name} delete"
        exec_ssh(cmd)
      end

      def create_new_container!(container)
        validate_new_container(container)
        load_dummy_module

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
        if exec_ssh("test -e #{template_path}", false).succeeded?
          create_cmd = "vserver #{container.name} build -m template " +
            "#{create_cmd_args} -t #{template_path}"
        else
          create_cmd = "vserver #{container.name} build -m debootstrap #{create_cmd_args}"
        end

        puts "Creating container, please wait..."
        exec_ssh(create_cmd)

        add_flags(container)
        apply_memory_limits(container)
        mark_for_start_at_boot(container)
        add_tinc_interfaces(container)

        @containers << container

        puts "Starting up..." 
        exec_ssh("vserver #{container.name} start")
        container.is_running = true

        add_apt_sources(container)
        fix_hostname(container)
        pass = create_root_password(container)
        start_ssh_server(container)
        puts "ready! Now login as root with password '#{pass}'"
      end

      def add_new_interfaces(container, interfaces)
        dummy_ifs = unused_dummy_interfaces
        interfaces.each do |iface|
          next if iface.is_tinc_interface

          iface.device = dummy_ifs.slice!(0)
          device_ids = Array.new
          container.interfaces.each { |cif| device_ids << cif.device_id }
          iface.device_id = device_ids.sort.last + 1
          container.interfaces << iface
          create_interface_files(container, iface)

          if container.is_running
            exec_ssh("ifconfig #{iface.device} up")
            exec_ssh("ip addr add #{iface.address}/#{iface.prefix} dev #{iface.device}")
            exec_ssh("ifconfig #{iface.device} broadcast #{iface.broadcast}")
            exec_ssh("naddress --add --nid #{container.ctx} --ip #{iface.address}/#{iface.prefix}")
          end
        end
      end

      def create_interface_files(container, interface)
        path = "#{container.config_path}/interfaces/#{interface.device_id}"
        cmd = "mkdir #{path}; echo #{interface.address} > #{path}/ip; echo #{interface.device} > #{path}/dev;
        echo #{interface.netmask} > #{path}/mask;"
        exec_ssh("sh -c \"#{cmd}\"")
      end

      def remove_interfaces(container, interfaces)
        return if interfaces.count == 0

        if container.is_running
          interfaces.each do |iface|
            exec_ssh("naddress --remove --nid #{container.ctx} --ip #{iface.address}/#{iface.prefix}")
            exec_ssh("ip addr del #{iface.address}/#{iface.prefix} dev #{iface.device}")
            exec_ssh("ifconfig #{iface.device} down")
          end
        end

        remove_interface_files(container)

        interfaces.each do |iface|
          iface_to_delete = nil
          container.interfaces.each do |c_iface|
            if c_iface.address == iface.address &&
              c_iface.netmask == iface.netmask
              iface_to_delete = c_iface
              break
            end
          end
          container.interfaces.delete_if { |n| n == iface_to_delete } if iface_to_delete
        end

        container.interfaces = Interface.reorder_device_ids(container.interfaces)
        container.interfaces.each { |iface| create_interface_files(container, iface) }
      end

      def remove_interface_files(container)
        paths = Array.new
        container.interfaces.each do |iface|
          paths << "#{container.config_path}/interfaces/#{iface.device_id}"
        end
        exec_ssh("rm -rf #{paths.join(" ")}")
      end

      def add_tinc_interfaces(container)
        tinc_ifaces = container.interfaces.select { |n| n.is_tinc_interface }
        return if tinc_ifaces.count == 0
        tinc_ifaces.each do |iface|
          create_interface_files(container, iface)
          path = "/etc/tinc/#{iface.device}/up.d/vserver-up"
          cmd = "echo ip addr add #{iface.address}/#{iface.prefix} dev #{iface.device} >> #{path}"
          exec_ssh("sh -c \"#{cmd}\"")

          path = "/etc/tinc/#{iface.device}/down.d/vserver-down"
          cmd = "echo ip addr del #{iface.address}/#{iface.prefix} dev #{iface.device} >> #{path}"
          exec_ssh("sh -c \"#{cmd}\"")
        end
      end

      def mark_for_start_at_boot(container)
        path = "#{container.config_path}/apps/init/mark"
        exec_ssh("echo default | sudo tee #{path}")
      end

      def create_root_password(container)
        pass = [*('A'..'Z')].sample(12).join.downcase
        exec_ssh("vserver #{container.name} exec /bin/sh -c 'echo \"root:#{pass}\" | chpasswd '")
        pass
      end

      def fix_hostname(container)
        hostname = container.hostname
        short = hostname.split(".").first
        exec_ssh("vserver #{container.name} exec /bin/sh -c 'echo \"127.0.0.1 #{hostname} #{short}\" >> /etc/hosts'")
        exec_ssh("vserver #{container.name} exec /bin/sh -c 'echo #{short} > /etc/hostname'")
      end

      def add_apt_sources(container)
        dist = container.distribution
        lines = "deb http://ftp2.de.debian.org/debian #{dist} main\ndeb http://security.debian.org/ #{dist}/updates main"
        exec_ssh("vserver #{container.name} exec /bin/sh -c 'echo \"#{lines}\" > /etc/apt/sources.list'")
      end

      def start_ssh_server(container)
        cmd = "/etc/init.d/ssh stop; rm /etc/ssh/ssh_host_*; dpkg-reconfigure openssh-server; /etc/init.d/ssh start"
        exec_ssh("vserver #{container.name} exec /bin/sh -c '#{cmd}'")
      end

      def add_flags(container)
        path = "#{container.config_path}/flags"
        cmd = "echo \"VIRT_MEM\nVIRT_UPTIME\nVIRT_LOAD\nVIRT_CPU\" | sudo tee #{path}"
        exec_ssh(cmd)
      end

      def apply_memory_limits(container)
        apply_memory_limits_cgroup(container)
        apply_memory_limits_rlimits(container)
      end

      def apply_memory_limits_cgroup(container)
        ram = container.ram
        swap = container.ram + container.swap
        cgroup_path = "#{container.config_path}/cgroup"
        cmd = "mkdir -p #{cgroup_path}; echo #{ram} > #{cgroup_path}/memory.limit_in_bytes;
        echo #{swap} > #{cgroup_path}/memory.memsw.limit_in_bytes;"
        cmd = "sh -c \"#{cmd}\""
        exec_ssh(cmd)

        if container.is_running && @cgroups_enabled
          Chef::Log.debug("Applying cgroup memory limits to running instance")
          cgroup_path = "/dev/cgroup/#{container.name}"
          cmd = "echo #{ram} > #{cgroup_path}/memory.limit_in_bytes; echo #{swap} > #{cgroup_path}/memory.memsw.limit_in_bytes;"
          exec_ssh("sh -c \"#{cmd}\"")
        end
      end

      def apply_memory_limits_rlimits(container)
        rlimit_path = "#{container.config_path}/rlimits"
        ram = (container.ram.to_f / 1024 / 4).to_i
        swap = ((container.ram + container.swap).to_f / 1024 / 4).to_i
        cmd = "mkdir -p #{rlimit_path}; echo #{ram} > #{rlimit_path}/rss.soft; echo #{swap} > #{rlimit_path}/rss.hard;"
        exec_ssh("sh -c \"#{cmd}\"")

        if container.is_running && !@cgroups_enabled
          Chef::Log.debug("Applying rlimits memory limits to running instance")
          cmd = "vlimit -c #{container.ctx} -S --rss #{ram}; vlimit -c #{container.ctx} --rss #{swap};"
          exec_ssh("sh -c \"#{cmd}\"")
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
        exec_ssh("modprobe dummy numdummies=40")
      end

      def validate_new_container(container)
        validate_container(container)

        raise "Container #{container.name} already exists!" if container_exists?(container.name)
        raise "Container #{container.name} needs at least one ip address!" if container.interfaces.count == 0
        raise "Distribution #{container.distribution} isn't supported!" if container.distribution.match(/(squeeze|wheezy)/).nil?
        raise "Container #{container.name} has no hostname!" if container.hostname.nil?
        
      end

      def validate_container(container)
        raise "No container name specified!" if container.name.to_s.empty?
        container.interfaces.each do |iface|
          raise "Device id for #{iface.address} is invalid!" if iface.device_id < 0
        end

        container.interfaces.select { |iface| iface.is_tinc_interface }.each do |iface|
          unless exec_ssh("test -e /etc/tinc/#{iface.device}", false).succeeded?
            raise "This host isn't configured for vpn #{iface.device}!"
          end
        end
      end

      def self.exec_ssh(cmd, session, raise_error = true)
        ShellCommand.exec("sudo " + cmd, session, { :dont_raise_error => !raise_error })
      end

      def self.create(node, session)
        host = Host.new(node)
        host.session = session
        return host unless self.exec_ssh("test -e #{host.config_path}", session, false).succeeded?

        host.kernel_version = self.exec_ssh("vserver-info - SYSINFO | grep -i kernel", session).
          stdout.strip.split(":")[1].strip
        host.util_vserver_version = self.exec_ssh("vserver-info - SYSINFO |grep -i util-vserver", session).
          stdout.strip.match(/util-vserver: (.+);.+/)[1]
        host.config_path = self.exec_ssh("vserver-info - SYSINFO |grep -i cfg-Directory", session).stdout.split(":")[1].strip
        host.cgroups_enabled = self.exec_ssh("mount |grep vserver|grep cgroup", session, false).succeeded?

        entries = self.exec_ssh("ls -ls #{host.config_path} | tail -n+2 |awk '{print $10}'", session).
          stdout.gsub(/\r/,"").strip.split("\n")
        entries.each do |n|

          c = Container.new(n, host)
          next unless self.exec_ssh("test -d #{c.config_path} && sudo test -e #{c.config_path}/context", session, false).succeeded?

          c.ctx = self.exec_ssh("cat #{c.config_path}/context", session).stdout.strip
          c.node_name = self.exec_ssh("cat #{c.config_path}/uts/nodename", session).stdout.strip
          c.is_running = self.exec_ssh("vserver-info #{c.name} RUNNING",session, false).succeeded?

          c.hostname = self.exec_ssh("vserver #{c.name} exec hostname -f", session).stdout.strip if c.is_running

          interface_path = "#{c.config_path}/interfaces"
          self.exec_ssh("ls -ls #{interface_path} | egrep \"^. d\" | awk '{print $10}'", session).stdout.gsub(/\r/,"").
            strip.split("\n").each do |if_n|
            device = self.exec_ssh("cat #{interface_path}/#{if_n}/dev", session).stdout.strip
            ip = self.exec_ssh("cat #{interface_path}/#{if_n}/ip", session).stdout.strip
            netmask = "255.255.255.0"
            if self.exec_ssh("test -e #{interface_path}/#{if_n}/mask", session, false).succeeded?
              netmask = self.exec_ssh("cat #{interface_path}/#{if_n}/mask", session).stdout.strip
            end
            iface = Interface.new("#{ip}/#{netmask}")
            iface.device_id = if_n.to_i
            iface.device = device
            c.interfaces << iface
          end

          if host.cgroups_enabled && self.exec_ssh("test -d #{c.config_path}/cgroup", session, false).succeeded?
            c.ram = self.exec_ssh("cat #{c.config_path}/cgroup/memory.limit_in_bytes", session).stdout.strip.to_i
            c.swap = self.exec_ssh("cat #{c.config_path}/cgroup/memory.memsw.limit_in_bytes", session).stdout.strip.to_i
          elsif exec_ssh("test -d #{c.config_path}/rlimits", session, false).succeeded?
            c.ram = self.exec_ssh("cat #{c.config_path}/rlimits/rss.soft", session).stdout.strip.to_i * 4 * 1024
            c.swap = self.exec_ssh("cat #{c.config_path}/rlimits/rss.hard", session).stdout.strip.to_i * 4 * 1024
          end

          host.containers << c 
        end
        host
      end
    end
  end
end
