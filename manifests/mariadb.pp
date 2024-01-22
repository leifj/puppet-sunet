# Mariadb cluster class for SUNET
define sunet::mariadb(
  $mariadb_version=latest,
  $bootstrap=0,
  $clients= ['127.0.0.1'],
  $cluster_nodes= ['127.0.0.1'],
  $ports = [3306, 4444, 4567, 4568],
)
{
  # Config from group.yaml
  $mysql_root_password = safe_hiera('mysql_root_password')
  $mysql_backup_password = safe_hiera('mysql_backup_password')
  $mariadb_dir = '/opt/mariadb'
  $server_id = 1000 + Integer($facts['networking']['hostname'][-1])

  # Hack to not clash with docker_compose which tries to create the same directory
  exec {'mariadb_dir_create':
    command => "mkdir -p ${mariadb_dir}",
    unless  =>  "test -d ${mariadb_dir}",
    }

  $dirs = ['datadir', 'init', 'conf', 'backups', 'scripts' ]
  $dirs.each |$dir| {
    ensure_resource('file',"${mariadb_dir}/${dir}", { ensure => directory, recurse => true } )
  }

  $_from = $clients + $cluster_nodes
  sunet::misc::ufw_allow { 'mariadb_ports':
    from => $_from,
    port => $ports,
  }

  $sql_files = ['02-backup_user.sql']
  $sql_files.each |$sql_file|{
    file { "${mariadb_dir}/init/${sql_file}":
      ensure  => present,
      content => template("sunet/mariadb/${sql_file}.erb"),
      mode    => '0744',
    }
  }
  file { "${mariadb_dir}/conf/credentials.cnf":
    ensure  => present,
    content => template('sunet/mariadb/credentials.cnf.erb'),
    mode    => '0744',
  }
  file { "${mariadb_dir}/conf/my.cnf":
    ensure  => present,
    content => template('sunet/mariadb/my.cnf.erb'),
    mode    => '0744',
  }
  $docker_compose = sunet::docker_compose { 'sunet_mariadb_docker_compose':
    content          => template('sunet/mariadb/docker-compose_mariadb.yml.erb'),
    service_name     => 'mariadb',
    compose_dir      => '/opt/',
    compose_filename => 'docker-compose.yml',
    description      => 'Mariadb server',
  }
}
