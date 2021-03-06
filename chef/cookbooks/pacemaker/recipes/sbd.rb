#
# Author:: Vincent Untz
# Cookbook Name:: pacemaker
# Recipe:: sbd
#
# Copyright 2014, SUSE
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require "shellwords"

node[:pacemaker][:platform][:sbd_packages].each do |pkg|
  package pkg
end

sbd_devices = nil
sbd_devices ||= (node[:pacemaker][:stonith][:sbd][:nodes][node[:fqdn]][:devices] rescue nil)
sbd_devices ||= (node[:pacemaker][:stonith][:sbd][:nodes][node[:hostname]][:devices] rescue nil)
raise "No SBD devices defined!" if sbd_devices.nil? || sbd_devices.empty?

sbd_cmd = "sbd"
sbd_devices.each do |sbd_device|
  sbd_cmd += " -d #{Shellwords.shellescape(sbd_device)}"
end

watchdog_module = node[:pacemaker][:stonith][:sbd][:watchdog_module]

execute "Load watchdog module #{watchdog_module}" do
  command "/sbin/modprobe #{watchdog_module}"
  not_if { watchdog_module.empty? }
end

file "/etc/modules-load.d/crowbar-watchdog.conf" do
  if watchdog_module.empty?
    action :delete
  else
    content watchdog_module
    mode 0644
    owner "root"
    group "root"
  end
end

execute "Check if watchdog is present" do
  command "test -c /dev/watchdog"
end

execute "Check that SBD was initialized using '#{sbd_cmd} create'." do
  command "#{sbd_cmd} dump &> /dev/null"
end

if node[:pacemaker][:is_remote]
  cookbook_file "sbd_remote.service" do
    path "/etc/systemd/system/sbd_remote.service"
    source "sbd_remote.service"
  end

  bash "reload systemd for sbd_remote.service" do
    code "systemctl daemon-reload"
    action :nothing
    subscribes :run, "cookbook_file[sbd_remote.service]", :immediately
  end
end

service "sbd" do
  service_name "sbd_remote" if node[:pacemaker][:is_remote]
  action :enable
  # with systemd (so no SLES11), sbd needs to be enabled
  not_if { node[:platform] == "suse" && node[:platform_version].to_f < 12.0 }
end

if node[:platform_family] == "suse"
  # We will want to explicitly allocate a slot the first time we come here
  # (hence the use of a notification to trigger this execute).
  # According to the man page, it should not be required, but apparently,
  # I've hit bugs where I had to do that. So better be safe.
  slot_name = node[:pacemaker][:stonith][:sbd][:nodes][node[:fqdn]][:slot_name] rescue nil
  slot_name ||= node[:pacemaker][:stonith][:sbd][:nodes][node[:hostname]][:slot_name] rescue nil
  slot_name ||= node[:hostname]
  execute "Allocate SBD slot" do
    command "#{sbd_cmd} allocate #{slot_name}"
    not_if "#{sbd_cmd} list | grep -q \" #{slot_name} \""
    action :nothing
  end

  template "/etc/sysconfig/sbd" do
    source "sysconfig_sbd.erb"
    owner "root"
    group "root"
    mode 0644
    variables(
      sbd_devices: sbd_devices,
      node_name: slot_name
    )
    # We want to allocate slots before restarting corosync
    notifies :run, "execute[Allocate SBD slot]", :immediately
    if node[:pacemaker][:is_remote]
      notifies :restart, "service[pacemaker_remote]", :immediately
      notifies :create, "ruby_block[wait for pacemaker_remote service to be reachable]", :immediately
    else
      notifies :restart, "service[#{node[:corosync][:platform][:service_name]}]", :immediately
      # After restarting corosync, we need to wait for the cluster to be online again
      notifies :create, "ruby_block[wait for cluster to be online]", :immediately
    end
  end
end
