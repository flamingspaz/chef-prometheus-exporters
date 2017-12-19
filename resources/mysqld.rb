#
# Cookbook Name:: prometheus_exporters
# Resource:: mysqld
#
# Copyright 2017, Evil Martians
#
# All rights reserved - Do Not Redistribute
#

resource_name :mysqld_exporter

property :instance_name, String, name_property: true
property :data_source_name, String, required: true
property :log_format, String, default: 'logger:stdout?json=false'
property :log_level, String
property :web_listen_address, String, default: '0.0.0.0:9104'
property :web_telemetry_path, String
property :config_my_cnf, String, default: '~/.my.cnf'
property :user, String, default: 'mysql'

action :install do
  # Set property that can be queried with Chef search
  node.default['prometheus_exporters']['mysqld']['enabled'] = true

  service_name = "mysqld_exporter_#{instance_name}"

  options = "-web.listen-address '#{web_listen_address}'"
  options += " -web.telemetry-path '#{web_telemetry_path}'" if web_telemetry_path
  options += " -config.my-cnf '#{config_my_cnf}'" if config_my_cnf
  options += " -log.level #{log_level}" if log_level
  options += " -log.format '#{log_format}'"

  env = {
    'DATA_SOURCE_NAME' => data_source_name,
  }

  remote_file 'mysqld_exporter' do
    path "#{Chef::Config[:file_cache_path]}/mysqld_exporter.tar.gz"
    owner 'root'
    group 'root'
    mode '0644'
    source node['prometheus_exporters']['mysqld']['url']
    checksum node['prometheus_exporters']['mysqld']['checksum']
  end

  bash 'untar mysqld_exporter' do
    code "tar -xzf #{Chef::Config[:file_cache_path]}/mysqld_exporter.tar.gz -C /opt"
    action :nothing
    subscribes :run, 'remote_file[mysqld_exporter]', :immediately
  end

  link '/usr/local/sbin/mysqld_exporter' do
    to "/opt/mysqld_exporter-#{node['prometheus_exporters']['mysqld']['version']}.linux-amd64/mysqld_exporter"
  end

  service service_name do
    action :nothing
  end

  case node['init_package']
  when /init/
    %w(
      /var/run/prometheus
      /var/log/prometheus
    ).each do |dir|
      directory dir do
        owner 'root'
        group 'root'
        mode '0755'
        recursive true
        action :create
      end
    end

    directory "/var/log/prometheus/#{service_name}" do
      owner new_resource.user
      group 'root'
      mode '0755'
      action :create
    end

    template "/etc/init.d/#{service_name}" do
      cookbook 'prometheus_exporters'
      source 'initscript.erb'
      owner 'root'
      group 'root'
      mode '0755'
      variables(
        env: env,
        user: new_resource.user,
        name: service_name,
        cmd: "/usr/local/sbin/mysqld_exporter #{options}",
        service_description: 'Prometheus MySQL Exporter'
      )
      notifies :restart, "service[#{service_name}]"
    end

  when /systemd/
    systemd_unit "#{service_name}.service" do
      content(
        'Unit' => {
          'Description' => 'Systemd unit for Prometheus MySQL Exporter',
          'After' => 'network.target remote-fs.target apiserver.service',
        },
        'Service' => {
          'Type' => 'simple',
          'User' => new_resource.user,
          'ExecStart' => "/usr/local/sbin/mysqld_exporter #{options}",
          'Environment' => env.map { |k, v| "'#{k}=#{v}'" }.join(' '),
          'WorkingDirectory' => '/',
          'Restart' => 'on-failure',
          'RestartSec' => '30s',
        },
        'Install' => {
          'WantedBy' => 'multi-user.target',
        }
      )
      notifies :restart, "service[#{service_name}]"
      action :create
    end

  when /upstart/
    template "/etc/init/#{service_name}.conf" do
      cookbook 'prometheus_exporters'
      source 'upstart.conf.erb'
      owner 'root'
      group 'root'
      mode '0644'
      variables(
        env: env,
        setuid: new_resource.user,
        cmd: "/usr/local/sbin/mysqld_exporter #{options}",
        service_description: 'Prometheus MySQL Exporter'
      )
      notifies :restart, "service[#{service_name}]"
    end

  else
    raise "Init system '#{node['init_package']}' is not supported by the 'prometheus_exporters' cookbook"
  end
end

action :enable do
  action_install
  service "mysqld_exporter_#{instance_name}" do
    action :enable
  end
end

action :start do
  service "mysqld_exporter_#{instance_name}" do
    action :start
  end
end

action :disable do
  service "mysqld_exporter_#{instance_name}" do
    action :disable
  end
end

action :stop do
  service "mysqld_exporter_#{instance_name}" do
    action :stop
  end
end
