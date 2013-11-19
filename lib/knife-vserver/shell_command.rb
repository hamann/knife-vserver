module Knife
  module Vserver
    class ShellCommand

      def self.exec(cmd, session, opts = {}, password = '')

        stdout_data, stderr_data = "", ""
        exit_code, exit_signal = nil, nil
        session.open_channel do |channel|
          channel.request_pty
          channel.exec(cmd) do |_, success|
            raise RuntimeError, "Command \"#{@cmd}\" could not be executed!" if !success
            channel.on_data do |_, data|
              if data =~ /^knife sudo password: /
                Chef::Log.debug("sudo password required, sending password")
                channel.send_data(password + "\n")
              else
                stdout_data += data
              end
            end

            channel.on_extended_data do |_,_,data|
              stderr_data += data
            end

            channel.on_request("exit-status") do |_,data|
              exit_code = data.read_long
            end

            channel.on_request("exit-signal") do |_, data|
              exit_signal = data.read_long
            end
          end
        end
        session.loop

        result = ShellCommandResult.new(cmd, stdout_data, stderr_data, exit_code.to_i)

        raise_error!(result) if opts[:abort_on_error] && !result.succeeded?

        return result
      end

      def self.raise_error!(result)
        raise RuntimeError, "Command failed! #{result.to_s}" 
      end

    end
  end
end

