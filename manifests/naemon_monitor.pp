# @summary Run naemon with Thruk.
# @param receive_otel Feature flag to enable the LGTM stack
# @param otel_retention Number of hours to keep logs, metrics and traces, defaults to 3 months
#
class sunet::naemon_monitor (
  String $domain,
  String $influx_password = lookup('influx_password', String, undef, ''),
  String $naemon_tag = 'latest',
  Array $naemon_extra_volumes = [],
  Array $thruk_extra_volumes = [],
  Array $resolvers = [],
  String $thruk_tag = 'latest',
  Array $thruk_admins = ['placeholder'],
  Array $thruk_users = [],
  String $influxdb_tag = '1.8',
  String $histou_tag = 'latest',
  String $nagflux_tag = 'latest',
  String $grafana_tag = '11.0',
  String $loki_tag = '3.0.0',
  String $mimir_tag = '2.12.0',
  String $tempo_tag = '2.4.2',
  String $alloy_tag = 'v1.1.0',
  Hash $manual_hosts = {},
  Hash $additional_entities = {},
  String $nrpe_group = 'nrpe',
  String $interface = 'ens3',
  Array $exclude_hosts = [],
  Optional[String] $default_host_group = undef,
  Array[Optional[String]] $optout_checks = [],
  Optional[Boolean] $receive_otel = false,
  String $otel_retention = '2232h',
) {
  $naemon_container = $::facts['dockerhost2'] ? {
    'yes' => 'naemon_monitor-naemon-1',
    default => 'naemon_monitor_naemon_1',
  }

  if $::facts['sunet_nftables_enabled'] == 'yes' {
    sunet::nftables::docker_expose { 'allow_http' :
      iif           => $interface,
      allow_clients => 'any',
      port          => 80,
    }
    sunet::nftables::docker_expose { 'allow_https' :
      iif           => $interface,
      allow_clients => 'any',
      port          => 443,
    }
    if $receive_otel {
      sunet::nftables::docker_expose { 'allow_otel_grpc' :
        iif           => $interface,
        allow_clients => 'any',
        port          => 4317,
      }
      sunet::nftables::docker_expose { 'allow_otel_http' :
        iif           => $interface,
        allow_clients => 'any',
        port          => 4318,
      }
    }
  } else {
    sunet::misc::ufw_allow { 'allow-http':
      from => 'any',
      port => '80',
    }
    sunet::misc::ufw_allow { 'allow-https':
      from => 'any',
      port => '443',
    }
    if $receive_otel {
      sunet::misc::ufw_allow { 'allow-otel-grpc':
        from => 'any',
        port => '4317',
      }
      sunet::misc::ufw_allow { 'allow-otel-http':
        from => 'any',
        port => '4318',
      }
    }
  }

  class { 'sunet::dehydrated::client': domain => $domain, ssl_links => true }

  if lookup('shib_key', undef, undef, undef) != undef {
    sunet::snippets::secret_file { '/opt/naemon_monitor/shib-certs/sp-key.pem': hiera_key => 'shib_key' }
    # assume cert is in cosmos repo (overlay)
  }

  $thruk_admins_string = inline_template('ADMIN_USERS=<%- @thruk_admins.each do |user| -%><%= user %>,<%- end -%>')
  $thruk_users_string = inline_template('READONLY_USERS=<%- @thruk_users.each do |user| -%><%= user %>,<%- end -%>')
  $thruk_env = [$thruk_admins_string, $thruk_users_string]

  if $influx_password == '' {
    err('ERROR: influx password not set')
  }
  $influx_env = ['INFLUXDB_ADMIN_USER=admin',"INFLUXDB_ADMIN_PASSWORD=${influx_password}", 'INFLUXDB_DB=nagflux']
  $nagflux_env = ["INFLUXDB_ADMIN_PASSWORD=${influx_password}"]

  file { '/etc/systemd/system/sunet-naemon_monitor.service.d/':
    ensure  => directory,
    recurse => true,
  }

  file { '/etc/systemd/system/sunet-naemon_monitor.service.d/override.conf':
    ensure  => file,
    content => template('sunet/naemon_monitor/service-override.conf.erb'),
    require => File['/etc/systemd/system/sunet-naemon_monitor.service.d/'],
  }

  sunet::docker_compose { 'naemon_monitor':
    content          => template('sunet/naemon_monitor/docker-compose.yml.erb'),
    service_name     => 'naemon_monitor',
    compose_dir      => '/opt/',
    compose_filename => 'docker-compose.yml',
    description      => 'Naemon monitoring (with Thruk)',
    require          => File['/etc/systemd/system/sunet-naemon_monitor.service.d/override.conf'],
  }

  file { '/opt/naemon_monitor/stop-monitor.sh':
    ensure  => file,
    content => template('sunet/naemon_monitor/stop-monitor.sh.erb'),
    mode    => '0644',
    group   => 'root',
    owner   => 'root',
  }

  file { '/etc/logrotate.d/naemon_monitor':
    ensure  => file,
    content => template('sunet/naemon_monitor/logrotate.erb'),
    mode    => '0644',
    group   => 'root',
    owner   => 'root',
  }

  file { '/opt/naemon_monitor/grafana.ini':
    ensure  => file,
    content => template('sunet/naemon_monitor/grafana.ini'),
    mode    => '0644',
    group   => 'root',
    owner   => 'root',
  }
  file { '/opt/naemon_monitor/histou.js':
    ensure  => file,
    content => template('sunet/naemon_monitor/histou.js'),
    mode    => '0644',
    group   => 'root',
    owner   => 'root',
  }
  file { '/opt/naemon_monitor/grafana-provisioning':
    ensure => directory,
    mode   => '0644',
    group  => 'root',
    owner  => 'root',
  }
  file { '/opt/naemon_monitor/grafana-provisioning/datasources':
    ensure => directory,
    mode   => '0644',
    group  => 'root',
    owner  => 'root',
  }
  file { '/opt/naemon_monitor/grafana-provisioning/dashboards':
    ensure => directory,
    mode   => '0644',
    group  => 'root',
    owner  => 'root',
  }
  file { '/opt/naemon_monitor/grafana-provisioning/datasources/influxdb.yaml':
    ensure  => file,
    content => template('sunet/naemon_monitor/grafana-provisioning/datasources/influxdb.yaml'),
    mode    => '0644',
    group   => 'root',
    owner   => 'root',
  }
  file { '/opt/naemon_monitor/data':
    ensure => directory,
    owner  => 'www-data',
    mode   => '0644',
    group  => 'root',
  }
  if $receive_otel {
    file { '/opt/naemon_monitor/grafana-provisioning/datasources/loki.yaml':
      ensure  => file,
      content => template('sunet/naemon_monitor/grafana-provisioning/datasources/loki.yaml'),
      mode    => '0644',
      group   => 'root',
      owner   => 'root',
    }
    file { '/opt/naemon_monitor/grafana-provisioning/datasources/mimir.yaml':
      ensure  => file,
      content => template('sunet/naemon_monitor/grafana-provisioning/datasources/mimir.yaml'),
      mode    => '0644',
      group   => 'root',
      owner   => 'root',
    }
    file { '/opt/naemon_monitor/grafana-provisioning/datasources/tempo.yaml':
      ensure  => file,
      content => template('sunet/naemon_monitor/grafana-provisioning/datasources/tempo.yaml'),
      mode    => '0644',
      group   => 'root',
      owner   => 'root',
    }
    file { '/opt/naemon_monitor/grafana-provisioning/dashboards/default.yaml':
      ensure  => file,
      content => template('sunet/naemon_monitor/grafana-provisioning/dashboards/default.yaml'),
      mode    => '0644',
      group   => 'root',
      owner   => 'root',
    }
    file { '/opt/naemon_monitor/grafana-provisioning/dashboards/overview.json':
      ensure  => file,
      content => template('sunet/naemon_monitor/grafana-provisioning/dashboards/overview.json'),
      mode    => '0644',
      group   => 'root',
      owner   => 'root',
    }
    file { '/opt/naemon_monitor/grafana-provisioning/dashboards/node-export-full.json':
      ensure  => file,
      content => template('sunet/naemon_monitor/grafana-provisioning/dashboards/node-export-full.json'),
      mode    => '0644',
      group   => 'root',
      owner   => 'root',
    }
    file { '/opt/naemon_monitor/loki-server.yaml':
      ensure  => file,
      content => template('sunet/naemon_monitor/loki-server.yaml'),
      mode    => '0644',
      group   => 'root',
      owner   => 'root',
    }
    file { '/opt/naemon_monitor/loki':
      ensure => directory,
      owner  => 'root',
      mode   => '0644',
      group  => 'root',
    }
    file { '/opt/naemon_monitor/mimir':
      ensure => directory,
      owner  => 'root',
      mode   => '0644',
      group  => 'root',
    }
    file { '/opt/naemon_monitor/mimir-server.yaml':
      ensure  => file,
      content => template('sunet/naemon_monitor/mimir-server.yaml'),
      mode    => '0644',
      group   => 'root',
      owner   => 'root',
    }
    file { '/opt/naemon_monitor/tempo':
      ensure => directory,
      owner  => 'root',
      mode   => '0644',
      group  => 'root',
    }
    file { '/opt/naemon_monitor/tempo-server.yaml':
      ensure  => file,
      content => template('sunet/naemon_monitor/tempo-server.yaml'),
      mode    => '0644',
      group   => 'root',
      owner   => 'root',
    }
    file { '/opt/naemon_monitor/alloy-server.alloy':
      ensure  => file,
      content => template('sunet/naemon_monitor/alloy-server.alloy'),
      mode    => '0644',
      group   => 'root',
      owner   => 'root',
    }
  }
  file { '/opt/naemon_monitor/grafana':
    ensure => directory,
    owner  => 'www-data',
    mode   => '0664',
    group  => 'root',
  }

  file { '/usr/lib/nagios/plugins/cosmos':
    ensure  => directory,
    recurse => true,
    mode    => '0644',
    group   => 'root',
    owner   => 'root',
  }

  $nagioscfg_dirs = ['/etc/', '/etc/naemon/', '/etc/naemon/conf.d/', '/etc/naemon/conf.d/nagioscfg/', '/etc/naemon/conf.d/cosmos/']
  $nagioscfg_dirs.each |$dir| {
    ensure_resource('file',$dir, {
        ensure => directory,
        mode   => '0644',
        group  => 'root',
        owner  => 'root',
    })
  }

  nagioscfg::contactgroup { 'alerts': }

  unless 'load' in $optout_checks {
    nagioscfg::service { 'check_load':
      use            => 'naemon-service',
      hostgroup_name => [$nrpe_group],
      check_command  => 'check_nrpe!check_load',
      description    => 'System Load',
      require        => File['/etc/naemon/conf.d/nagioscfg/'],
    }
  }
  unless 'users' in $optout_checks {
    nagioscfg::service { 'check_users':
      use            => 'naemon-service',
      hostgroup_name => [$nrpe_group],
      check_command  => 'check_nrpe!check_users',
      description    => 'Active Users',
      require        => File['/etc/naemon/conf.d/nagioscfg/'],
    }
  }
  unless 'zombie_procs' in $optout_checks {
    nagioscfg::service { 'check_zombie_procs':
      use            => 'naemon-service',
      hostgroup_name => [$nrpe_group],
      check_command  => 'check_nrpe!check_zombie_procs',
      description    => 'Zombie Processes',
      require        => File['/etc/naemon/conf.d/nagioscfg/'],
    }
  }
  unless 'total_procs' in $optout_checks {
    nagioscfg::service { 'check_total_procs':
      use            => 'naemon-service',
      hostgroup_name => [$nrpe_group],
      check_command  => 'check_nrpe!check_total_procs_lax',
      description    => 'Total Processes',
      require        => File['/etc/naemon/conf.d/nagioscfg/'],
    }
  }
  unless 'dynamic_disk' in $optout_checks {
    nagioscfg::service { 'check_dynamic_disk':
      use            => 'naemon-service',
      hostgroup_name => [$nrpe_group],
      check_command  => 'check_nrpe!check_dynamic_disk',
      description    => 'Disk',
      require        => File['/etc/naemon/conf.d/nagioscfg/'],
    }
  }
  unless 'uptime' in $optout_checks {
    nagioscfg::service { 'check_uptime':
      use            => 'naemon-service',
      hostgroup_name => [$nrpe_group],
      check_command  => 'check_nrpe!check_uptime',
      description    => 'Uptime',
      require        => File['/etc/naemon/conf.d/nagioscfg/'],
    }
  }
  unless 'reboot' in $optout_checks {
    nagioscfg::service { 'check_reboot':
      hostgroup_name => [$nrpe_group],
      check_command  => 'check_nrpe!check_reboot',
      description    => 'Reboot Needed',
      contact_groups => ['alerts'],
      require        => File['/etc/naemon/conf.d/nagioscfg/'],
    }
  }
  unless 'memory' in $optout_checks {
    nagioscfg::service { 'check_memory':
      use            => 'naemon-service',
      hostgroup_name => [$nrpe_group],
      check_command  => 'check_nrpe!check_memory',
      description    => 'System Memory',
      require        => File['/etc/naemon/conf.d/nagioscfg/'],
    }
  }
  unless 'entropy' in $optout_checks {
    nagioscfg::service { 'check_entropy':
      use            => 'naemon-service',
      hostgroup_name => [$nrpe_group],
      check_command  => 'check_nrpe!check_entropy',
      description    => 'System Entropy',
      require        => File['/etc/naemon/conf.d/nagioscfg/'],
    }
  }
  unless 'ntp_time' in $optout_checks {
    nagioscfg::service { 'check_ntp_time':
      use            => 'naemon-service',
      hostgroup_name => [$nrpe_group],
      check_command  => 'check_nrpe!check_ntp_time',
      description    => 'System NTP Time',
      require        => File['/etc/naemon/conf.d/nagioscfg/'],
    }
  }
  unless 'scriptherder' in $optout_checks {
    nagioscfg::service { 'check_scriptherder':
      hostgroup_name => [$nrpe_group],
      check_command  => 'check_nrpe!check_scriptherder',
      description    => 'Scriptherder Status',
      contact_groups => ['naemon-admins'],
      require        => File['/etc/naemon/conf.d/nagioscfg/'],
    }
  }
  unless 'apt' in $optout_checks {
    nagioscfg::service { 'check_apt':
      use            => 'naemon-service',
      hostgroup_name => [$nrpe_group],
      check_command  => 'check_nrpe!check_apt',
      description    => 'Packages available for upgrade',
      require        => File['/etc/naemon/conf.d/nagioscfg/'],
    }
  }

  file { '/etc/naemon/conf.d/cosmos/naemon-hostgroups.cfg':
    ensure  => file,
    mode    => '0644',
    group   => 'root',
    owner   => 'root',

    content => template('sunet/naemon_monitor/naemon-hostgroups.cfg.erb'),
    require => File['/etc/naemon/conf.d/cosmos/'],
  }
  file { '/etc/naemon/conf.d/cosmos/naemon-host.cfg':
    ensure  => file,
    mode    => '0644',
    group   => 'root',
    owner   => 'root',
    content => template('sunet/naemon_monitor/naemon-host.cfg.erb'),
    require => File['/etc/naemon/conf.d/cosmos/'],
  }

  file { '/etc/naemon/conf.d/cosmos/naemon-service.cfg':
    ensure  => file,
    mode    => '0644',
    group   => 'root',
    owner   => 'root',
    content => template('sunet/naemon_monitor/naemon-service.cfg.erb'),
    require => File['/etc/naemon/conf.d/cosmos/'],
  }

  file { '/etc/naemon/conf.d/cosmos/naemon-contactgroups.cfg':
    ensure  => file,
    mode    => '0644',
    group   => 'root',
    owner   => 'root',
    content => template('sunet/naemon_monitor/naemon-contactgroups.cfg.erb'),
    require => File['/etc/naemon/conf.d/cosmos/'],
  }

  sunet::scriptherder::cronjob { 'thrukmaintenance':
    cmd           => '/usr/bin/docker exec --user www-data naemon_monitor-thruk-1 /usr/bin/thruk maintenance',
    minute        => '50',
    ok_criteria   => ['exit_status=0'],
    warn_criteria => ['exit_status=1', 'max_age=24h'],
  }

  class { 'nagioscfg':
    additional_entities => $additional_entities,
    config              => 'naemon_monitor',
    default_host_group  => $default_host_group,
    manage_package      => false,
    manage_service      => false,
    cfgdir              => '/etc/naemon/conf.d/nagioscfg',
    host_template       => 'naemon-host',
    service             => 'sunet-naemon_monitor',
    single_ip           => true,
    require             => File['/etc/naemon/conf.d/nagioscfg/'],
    exclude_hosts       => $exclude_hosts,
  }
}
