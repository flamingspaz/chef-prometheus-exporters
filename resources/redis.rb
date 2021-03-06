#
# Cookbook Name:: prometheus_exporters
# Resource:: redis
#
# Copyright 2017, Evil Martians
#
# All rights reserved - Do Not Redistribute
#

resource_name :redis_exporter

property :web_listen_address, String, default: '0.0.0.0:9121'
property :web_telemetry_path, String, default: '/metrics'
property :log_format, String, default: 'txt'
property :debug, [TrueClass, FalseClass], default: false
property :check_keys, String
property :redis_addr, String, default: 'redis://localhost:6379'
property :redis_password, String
property :redis_alias, String
property :redis_file, String
property :namespace, String, default: 'redis'
property :user, String, default: 'root'

action :install do
  # Set property that can be queried with Chef search
  node.default['prometheus_exporters']['redis']['enabled'] = true

  options = "-web.listen-address #{new_resource.web_listen_address}"
  options += " -web.telemetry-path #{new_resource.web_telemetry_path}"
  options += " -log-format #{new_resource.log_format}"
  options += ' -debug' if new_resource.debug
  options += " -check-keys #{new_resource.check_keys}" if new_resource.check_keys
  options += " -redis.addr #{new_resource.redis_addr}" if new_resource.redis_addr
  options += " -redis.password #{new_resource.redis_password}" if new_resource.redis_password
  options += " -redis.alias #{new_resource.redis_alias}" if new_resource.redis_alias
  options += " -redis.file #{new_resource.redis_file}" if new_resource.redis_file
  options += " -namespace #{new_resource.namespace}"

  remote_file 'redis_exporter' do
    path "#{Chef::Config[:file_cache_path]}/redis_exporter.tar.gz"
    owner 'root'
    group 'root'
    mode '0644'
    source node['prometheus_exporters']['redis']['url']
    checksum node['prometheus_exporters']['redis']['checksum']
  end

  bash 'untar redis_exporter' do
    code "tar -xzf #{Chef::Config[:file_cache_path]}/redis_exporter.tar.gz -C /usr/local/sbin/"
    action :nothing
    subscribes :run, 'remote_file[redis_exporter]', :immediately
  end

  service 'redis_exporter' do
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

    directory '/var/log/prometheus/redis_exporter' do
      owner new_resource.user
      group 'root'
      mode '0755'
      action :create
    end

    template '/etc/init.d/redis_exporter' do
      cookbook 'prometheus_exporters'
      source 'initscript.erb'
      owner 'root'
      group 'root'
      mode '0755'
      variables(
        name: 'redis_exporter',
        user: new_resource.user,
        cmd: "/usr/local/sbin/redis_exporter #{options}",
        service_description: 'Prometheus Redis Exporter'
      )
      notifies :restart, 'service[redis_exporter]'
    end

  when /systemd/
    systemd_unit 'redis_exporter.service' do
      content(
        'Unit' => {
          'Description' => 'Systemd unit for Prometheus Redis Exporter',
          'After' => 'network.target remote-fs.target apiserver.service',
        },
        'Service' => {
          'Type' => 'simple',
          'User' => new_resource.user,
          'ExecStart' => "/usr/local/sbin/redis_exporter #{options}",
          'WorkingDirectory' => '/',
          'Restart' => 'on-failure',
          'RestartSec' => '30s',
        },
        'Install' => {
          'WantedBy' => 'multi-user.target',
        }
      )
      notifies :restart, 'service[redis_exporter]'
      action :create
    end

  when /upstart/
    template '/etc/init/redis_exporter.conf' do
      cookbook 'prometheus_exporters'
      source 'upstart.conf.erb'
      owner 'root'
      group 'root'
      mode '0644'
      variables(
        env: environment_list,
        user: new_resource.user,
        cmd: "/usr/local/sbin/redis_exporter #{options}",
        service_description: 'Prometheus Redis Exporter'
      )
      notifies :restart, 'service[redis_exporter]'
    end

  else
    raise "Init system '#{node['init_package']}' is not supported by the 'prometheus_exporters' cookbook"
  end
end

action :enable do
  action_install
  service 'redis_exporter' do
    action :enable
  end
end

action :start do
  service 'redis_exporter' do
    action :start
  end
end

action :disable do
  service 'redis_exporter' do
    action :disable
  end
end

action :stop do
  service 'redis_exporter' do
    action :stop
  end
end
