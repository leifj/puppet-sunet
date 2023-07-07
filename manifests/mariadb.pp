# Mariadb cluster class for SUNET
class sunet::mariadb(
  String $wsrep_cluster_address,
  Array[String] $client_ips,
  Integer $id,
  String $interface = 'ens3',
)
{
  include sunet::packages::mariadb_server
  $wsrep_node_address = $facts['networking']['ip']
  $wsrep_node_name = $facts['networking']['fqdn']
  $server_id = 1000 + $id
  $mysql_root_password = lookup('mysql_root_password')
  $mysql_backup_password = lookup('mysql_backup_password')
  $ports = [3306, 4444, 4567, 4568]
  sunet::misc::ufw_allow { 'mariadb_ports':
    from => $client_ips,
    port => $ports,
  }

  file { '/etc/mysql/conf.d/credentials.cnf':
    ensure  => present,
    content => template('sunet/mariadb/credentials.cnf.erb'),
    mode    => '0744',
    owner   => 999,
    group   => 999,
  }
  file { '/etc/mysql/conf.d/mysql.cnf':
    ensure  => present,
    content => template('sunet/mariadb/my.cnf.erb'),
    mode    => '0744',
    owner   => 999,
    group   => 999,
  }
  file { '/usr/local/bin/purge-binlogs':
    ensure  => present,
    content => template('sunet/mariadb/purge-binlogs.erb.sh'),
    mode    => '0744',
    owner   => 999,
    group   => 999,
  }
  file { '/usr/local/bin/run_manual_backup_dump':
    ensure  => present,
    content => template('sunet/mariadb/run_manual_backup_dump.erb.sh'),
    mode    => '0744',
    owner   => 999,
    group   => 999,
  }
  sunet::scriptherder::cronjob { 'purge_binlogs':
    cmd           => '/usr/local/bin/purge-binlogs',
    hour          => '6',
    minute        => '0',
    ok_criteria   => ['exit_status=0','max_age=2d'],
    warn_criteria => ['exit_status=1','max_age=3d'],
  }
  file { '/usr/local/bin/cluster-size':
    ensure  => present,
    content => template('sunet/mariadb/cluster-size.erb.sh'),
    mode    => '0744',
  }
  file { '/usr/local/bin/cluster-status':
    ensure  => present,
    content => template('sunet/mariadb/cluster-status.erb.sh'),
    mode    => '0744',
  }
  file { '/etc/sudoers.d/99-size-test':
    ensure  => file,
    content => "script ALL=(root) NOPASSWD: /usr/local/bin/cluster-size\n",
    mode    => '0440',
    owner   => 'root',
    group   => 'root',
  }
  file { '/etc/sudoers.d/99-status-test':
    ensure  => file,
    content => "script ALL=(root) NOPASSWD: /usr/local/bin/cluster-status\n",
    mode    => '0440',
    owner   => 'root',
    group   => 'root',
  }
}
