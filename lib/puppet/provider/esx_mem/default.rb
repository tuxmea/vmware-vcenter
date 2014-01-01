provider_path = Pathname.new(__FILE__).parent.parent
require File.join(provider_path, 'vcenter')
require 'rbvmomi'

Puppet::Type.type(:esx_mem).provide(:esx_mem, :parent => Puppet::Provider::Vcenter) do
  @doc = "Export Import OVF"
  def create
    #Install MEM

    begin

      Puppet.notice "Installing MEM on server"

      flag = install_mem
    rescue Exception => exc
      flag = 1
      Puppet.err(exc.message)
    end

    if flag.eql?(0)
      Puppet.notice "Successfully installed MEM on server '#{name}'."
    else
      Puppet.err "Unable to install MEM on server '#{name}'."
    end

  end

  # Intalling MEM
  def install_mem
    flag = esx_main_enter_exists("enter")
    if flag.eql?(0)
      cmd = "#{resource[:script_executable_path]} #{resource[:setup_script_filepath]}  --install --username #{resource[:host_username]} --password #{resource[:host_password ]} --server=#{resource[:name ]} --reboot"

      error_log_filename = "/tmp/installmem_err_log.#{Process.pid}"
      log_filename = "/tmp/installmem_log.#{Process.pid}"

      flag = execute_system_cmd(cmd , log_filename , error_log_filename)

      if flag.eql?(0)
        # Exiting from maintenance mode
        esx_main_enter_exists("exit")
      end
    end
    return flag
  end

  def get_esx_currentstate

    flag = 0
    host_ip = resource[:name]

    error_log_filename = "/tmp/err_#{host_ip}_state.#{Process.pid}"
    log_filename = "/tmp/log.#{host_ip}_state.#{Process.pid}"

    cmd = "vicfg-hostops --server #{host_ip} --username #{resource[:host_username]} --password #{resource[:host_password ]} --operation info"
    system(cmd , :out => [log_filename, 'a'], :err => [error_log_filename, 'a'])
    if $? != 0
      flag = 1
      err_content = File.open(error_log_filename, 'rb') { |file| file.read }
      Puppet.err err_content
    else
      content = File.open(log_filename, 'rb') { |file| file.read }
      if (/SOAP|Error|operation is not allowed/.match(content))
        # got some error
        Puppet.err content
        flag = 1
      else
        maintenanceStatus = /In Maintenance Mode\s+:\s+(\S+)/.match(content)
        if (maintenanceStatus[1].downcase.eql?('yes'))
          flag = 2
        else
          flag = 3
        end
      end

    end
    remove_files(log_filename, error_log_filename)
    return flag
  end

  # Enter and exit ESX host in maintenance mode
  def esx_main_enter_exists(operation)
    flag = 0

    host_ip = resource[:name]
    error_log_filename = "/tmp/err_#{host_ip}_#{operation}.#{Process.pid}"
    log_filename = "/tmp/log.#{host_ip}_#{operation}.#{Process.pid}"

    # Getting current state
    retVal = get_esx_currentstate

    if retVal == 2 and operation.eql?('enter')
      Puppet.notice "Host '#{host_ip}' is already in maintenance mode"
    elsif retVal == 3 and operation.eql?('exit')
      Puppet.notice "Host '#{host_ip}' is not in maintenance mode. Hence no need to perform 'exit' operation"
    elsif retVal == 1
      flag = 1

    else

      if operation.eql?('enter')
        cmd = "vicfg-hostops --server #{host_ip} --username #{resource[:host_username]} --password #{resource[:host_password ]} --operation enter"
      else
        cmd = "vicfg-hostops --server #{host_ip} --username #{resource[:host_username]} --password #{resource[:host_password ]} --operation exit"
      end

      flag = execute_system_cmd(cmd , log_filename , error_log_filename)
    end

    return flag
  end

  def configure_mem
    return false
  end

  def configure_mem=(value)
    flag = 0
    error_log_filename = "/tmp/configuremem_err_log.#{Process.pid}"
    log_filename = "/tmp/configuremem_log.#{Process.pid}"

    script_executable_path = resource[:script_executable_path]
    setup_script_filepath = resource[:setup_script_filepath]
    host_username = resource[:host_username]
    host_password = resource[:host_password ]
    host_ip = resource[:name ]
    vnics = resource[:vnics]
    vnics_ipaddress = resource[:vnics_ipaddress]
    iscsi_vswitch = resource[:iscsi_vswitch]
    mtu = resource[:mtu]
    iscsi_vmkernal_prefix = resource[:iscsi_vmkernal_prefix]
    iscsi_netmask = resource[:iscsi_netmask]
    storage_groupip = resource[:storage_groupip]
    iscsi_chapuser = resource[:iscsi_chapuser]
    iscsi_chapsecret = resource[:iscsi_chapsecret]
    if validate_configure_param.eql?(1)
      return 1
    end

    begin
      flag = esx_main_enter_exists("enter")
      if flag.eql?(0)

        chapExtension = ""
        if !iscsi_chapuser.nil?
          chapExtension = "--chapuser #{iscsi_chapuser} --chapsecret #{iscsi_chapsecret}"
        end

        if resource[:disable_hw_iscsi].eql?('true')
          cmd = "#{script_executable_path} #{setup_script_filepath} --configure --username #{host_username} --password #{host_password} --server=#{host_ip} --nics #{vnics} --ips #{vnics_ipaddress} --vswitch #{iscsi_vswitch} --mtu #{mtu} --vmkernel #{iscsi_vmkernal_prefix} --netmask #{iscsi_netmask} --groupip #{storage_groupip} #{chapExtension} --enableswiscsi --nohwiscsi"
        else
          cmd =  "#{script_executable_path} #{setup_script_filepath} --configure --username #{host_username} --password #{host_password} --server=#{host_ip} --nics #{vnics} --ips #{vnics_ipaddress} --vswitch #{iscsi_vswitch} --mtu #{mtu} --vmkernel #{iscsi_vmkernal_prefix} --netmask #{iscsi_netmask} --groupip #{storage_groupip} #{chapExtension}"
        end
        flag = execute_system_cmd(cmd , log_filename , error_log_filename)
      end

    rescue Exception => exc
      flag = 1
      Puppet.err(exc.message)
    end
    esx_main_enter_exists("exit")

    if flag.eql?(0)
      Puppet.notice "Successfully configured MEM on server '#{name}'."
    else
      Puppet.err "Unable to configure MEM on server '#{name}'."
    end

    return flag
  end

  # Check whether MEM is installed
  def exists?
    mem
  end

  private

  # Removing files
  def remove_files(logfile , errorfile)
    if File.exist?(logfile)
      File.delete(logfile)
    end

    if File.exist?(errorfile)
      File.delete(errorfile)
    end
  end

  # Check whether mem is installed on the ESX host
  def mem
    flag = 0

    cmd = "#{resource[:script_executable_path]} #{resource[:setup_script_filepath]} --query --username #{resource[:host_username]} --password #{resource[:host_password ]} --server=#{resource[:name ]}"

    error_log_filename = "/tmp/err_log.#{Process.pid}"
    log_filename = "/tmp/log.#{Process.pid}"
    ENV['PERL_LWP_SSL_VERIFY_HOSTNAME']= '0' ;
    system(cmd , :out => [log_filename, 'a'], :err => [error_log_filename, 'a'])
    if $? != 0
      flag = 1
      err_content = File.open(error_log_filename, 'rb') { |file| file.read }
      Puppet.err err_content
    else
      content = File.open(log_filename, 'rb') { |file| file.read }
      if (/(?i:installed)/.match(content))
        Puppet.notice content
      else
        flag = 1
        Puppet.notice content
      end
    end

    remove_files( error_log_filename , log_filename)

    if flag.eql?(0)
      Puppet.info "MEM is already installed on server"
      return true

    else
      Puppet.notice "MEM is not installed on server"
      return false

    end
  end

  def execute_system_cmd(cmd,log_filename,error_log_filename)
    flag = 0
    ENV['PERL_LWP_SSL_VERIFY_HOSTNAME']= '0' ;
    system(cmd , :out => [log_filename, 'a'], :err => [error_log_filename, 'a'])
    if $? != 0
      flag = 1
      err_content = File.open(error_log_filename, 'rb') { |file| file.read }
      Puppet.err err_content
    else
      content = File.open(log_filename, 'rb') { |file| file.read }
      if (/(?i:Error|failed|SOAP|Enter maintenance mode|Could not find requested datastore|called at|pm line|does not exist|Could not bind)/.match(content))
        # got some error
        Puppet.err content
        flag = 1
      else
        Puppet.notice content
      end
    end
    remove_files(log_filename, error_log_filename)

    return flag

  end

  def validate_configure_param
    flag = 1
    if resource[:storage_groupip].nil?
      Puppet.err "Unable to configure MEM, because 'storage_groupip' value is not provided."
    elsif resource[:mtu].nil?
      Puppet.err "Unable to configure MEM, because 'mtu' value is not provided."
    elsif resource[:iscsi_vmkernal_prefix].nil?
      Puppet.err "Unable to configure MEM, because 'iscsi_vmkernal_prefix' value is not provided."
    elsif resource[:iscsi_netmask].nil?
      Puppet.err "Unable to configure MEM, because 'iscsi_netmask' value is not provided."
    elsif resource[:iscsi_vswitch].nil?
      Puppet.err "Unable to configure MEM, because 'iscsi_vswitch' value is not provided."
    elsif resource[:vnics_ipaddress].nil?
      Puppet.err "Unable to configure MEM, because 'vnics_ipaddress' value is not provided."
    elsif resource[:vnics].nil?
      Puppet.err "Unable to configure MEM, because 'vnics' value is not provided."
    elsif !resource[:iscsi_chapuser].nil? and resource[:iscsi_chapsecret].nil?
        Puppet.err "Unable to configure MEM, because 'iscsi_chapsecret' value is not provided."
    else
      flag = 0

    end
    return flag
  end
end