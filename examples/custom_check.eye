# This example shows how to write custom checks:
#   here every 1.second we check process procline, and if it matches `Hahaha`
#   send TERM signal

class MyCheck < Eye::Checker::Custom
  def get_value
    if a = (Eye::Sigar.proc_args(@pid) rescue nil)
      a.first
    end
  end

  def good?(value)
    !(value =~ /Hahaha/)
  end
end

Eye.app :bla do
  process :a do
    start_command "ruby -e 'sleep 30; $0 = %{Hahaha}; sleep'"
    daemonize true
    pid_file "/tmp/1.pid"
    check :my_check, every: 1.second, fires: -> { send_signal(:TERM) }
  end
end
