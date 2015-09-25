module Eye::Process::Monitor

private

  def load_external_pid_file
    newpid = load_pid_from_file
    if !newpid
      self.pid = nil
      info "load_external_pid_file: no pid_file"
      return :no_pid_file
    end

    if process_pid_running?(newpid)
      self.pid = newpid
      res = compare_identity
      if res == :fail
        warn "load_external_pid_file: process <#{self.pid}> from pid_file failed check_identity"
        :bad_identity
      else
        str = "load_external_pid_file: process <#{self.pid}> from pid_file found and already running"
        str += ", (id: #{res})" if res != :ok
        info str
        :ok
      end
    else
      @last_loaded_pid = newpid
      self.pid = nil
      info "load_external_pid_file: pid_file found, but process <#{newpid}> not found"
      :not_running
    end
  end

  def check_alive
    if up?

      # check that process runned
      unless process_really_running?
        warn "check_alive: process <#{self.pid}> not found"
        notify :info, 'crashed!'
        clear_pid_file if control_pid? && self.pid && load_pid_from_file == self.pid

        switch :crashed, Eye::Reason.new(:crashed)
      else
        check_pid_file
      end
    end
  end

  def check_pid_file
    ppid = failsafe_load_pid
    return if ppid == self.pid

    msg = "check_alive: pid_file (#{self[:pid_file]}) changed by itself (<#{self.pid}> => <#{ppid}>)"
    if control_pid?
      msg += ", reverting to <#{self.pid}> (the pid_file is controlled by eye)"
      unless failsafe_save_pid
        msg += ", pid_file write failed! O_o"
      end
    else
      changed_ago_s = Time.now - pid_file_ctime

      if ppid == nil
        msg += ", reverting to <#{self.pid}> (the pid_file is empty)"
        unless failsafe_save_pid
          msg += ", pid_file write failed! O_o"
        end

      elsif (changed_ago_s > self[:auto_update_pidfile_grace]) && process_pid_running?(ppid) && (compare_identity(ppid) != :fail)
        msg += ", trusting this change, and now monitor <#{ppid}>"
        self.pid = ppid

      elsif (changed_ago_s > self[:revert_fuckup_pidfile_grace])
        msg += " over #{self[:revert_fuckup_pidfile_grace]}s ago, reverting to <#{self.pid}>, because <#{ppid}> not alive"
        unless failsafe_save_pid
          msg += ", pid_file write failed! O_o"
        end

      else
        msg += ', ignoring self-managed pid change'
      end
    end

    warn msg
  end

  def check_identity
    res = compare_identity
    if res == :fail
      warn "check_identity: process <#{self.pid}> identity is bad"
      notify :info, 'crashed by identity!'
      switch :crashed, Eye::Reason.new(:crashed_by_identity)
      self.pid = nil
      false
    else
      info "check_identity: process <#{self.pid}> identity is #{res}" if res != :ok
      true
    end
  end

  def check_crash
    if down?
      if self[:keep_alive]
        warn 'check crashed: process is down'

        if self[:restore_in]
          schedule_in self[:restore_in].to_f, :restore, Eye::Reason.new(:crashed)
        else
          schedule :restore, Eye::Reason.new(:crashed)
        end
      else
        warn 'check crashed: process without keep_alive'
        schedule :unmonitor, Eye::Reason.new(:crashed)
      end
    else
      debug { 'check crashed: skipped, process is not in down' }
    end
  end

  def restore
    start if down?
  end

end
