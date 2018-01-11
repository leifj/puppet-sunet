class sunet::ipam {

  $bind9_allow_servers = hiera_array('bind9_allow_servers',[])
  $https_allow_servers = hiera_array('https_allow_servers',[])
  $db_password         = safe_hiera('nipap_db_password',[])
  $web_ui_username     = nipap-www
  $web_ui_password     = safe_hiera('web_UI_password',[])
  $welcome_message     = 'Welcome to SUNET IPAM. Please login using your SSO credentials.'
  $template_directory  = 'sunet/ipam'
  $domain              = $::domain
  $root_nipap_password = safe_hiera('root_nipap_password',[])

  ufw::allow {'allow_nagios_nipap': ip => 'any', from => '109.105.111.111', port => '1337'}
  ufw::allow {'allow_http': ip => 'any', port => '80'}

  $bind9_allow_servers.each |$server| {
    ufw::allow { "allow_bind9_${server}":
      from => $server,
      ip   => 'any',
      port => '53',
    }
  }
  $https_allow_servers.each |$server| {
      ufw::allow { "allow_web_${server}_to_${port}":
      from => $server,
      ip   => 'any',
      port => '443',
      }
  }
  package { ['postgresql',
            'postgresql-9.5-ip4r', 
            'postgresql-contrib', 
            'apache2', 
            'bind9', 
            'libapache2-mod-wsgi',
            'libldap2-dev', 
            'libsasl2-dev',
            'autopostgresqlbackup']:
    ensure => 'present',
  }
  -> class { 'python':
      version => 'system',
      pip     => true,
      dev     => true,
  }
  -> python::pip {'python-ldap': ensure => present, pkgname => 'python-ldap'}
  -> apt::source {'nipap':
      location      => 'http://spritelink.github.io/NIPAP/repos/apt',
      release       => 'stable',
      repos         => 'main extra',
      key           => {
      'id'     => '58E66DF09A12C9D752FD924C4481633C2094AABD',
      'source' => 'https://spritelink.github.io/NIPAP/nipap.gpg.key',
      },
      include       => {
      'deb' => true,
      },
      notify_update => true,
      }
  -> file {'/root/nipapd.preseed':
      ensure  => file,
      mode    => '0644',
      content => template("${template_directory}/nipapd.preseed.erb"),
      }
  -> package {'nipapd':
      ensure       => present,
      responsefile => '/root/nipapd.preseed'
      }
  -> package {[nipap-cli, nipap-www]:
      ensure => present,
      }
  -> service {'nipapd':
      ensure => running,
      enable => true,
      }
  -> service {'apache2':
      ensure => running,
      enable => true,
      }

  file {'/root/change_db_password.sql':
    ensure  => file,
    mode    => '0644',
    content => template("${template_directory}/change_db_password.sql.erb"),
    require => Package['nipapd'],
  }
  -> exec {'change_db_password':
      user        => 'postgres',
      command     => 'psql -f /root/change_db_password.sql',
      subscribe   => File['/root/change_db_password.sql'],
      refreshonly => true,
      }
  -> exec {'create_web_ui_user':
      command => "nipap-passwd add --username ${web_ui_username} --password ${web_ui_password} --name 'User account for the web UI' --trusted",
      unless  => '/usr/sbin/nipap-passwd list | grep nipap-www',
      }
  -> exec {'create_root_local_user':
      command => "nipap-passwd add --username root --password ${root_nipap_password} --name 'local root user'",
      unless  => '/usr/sbin/nipap-passwd list | grep root',
      }
  -> file {'/etc/nipap/nipap.conf':
      ensure  => file,
      mode    => '0644',
      content => template("${template_directory}/nipap.conf.erb"),
      notify  => Service['nipapd'],
      }
  -> file { '/root/.nipaprc':
      ensure  => file,
      owner   => 'root',
      group   => 'root',
      mode    => '0600',
      content => template("${template_directory}/.nipaprc.erb")
      }
  -> file {'/etc/apache2/sites-available/nipap-default.conf':
      ensure  => file,
      mode    => '0644',
      content => template("${template_directory}/nipap-default.conf.erb"),
      notify  => Service['apache2'],
      }
  -> file {'/etc/apache2/sites-available/nipap-ssl.conf':
      ensure  => file,
      mode    => '0644',
      content => template("${template_directory}/nipap-ssl.conf.erb"),
      }
  -> file { '/etc/apache2/sites-enabled/nipap-ssl.conf':
      ensure => link,
      target => '/etc/apache2/sites-available/nipap-ssl.conf',
      }
  -> file { '/etc/apache2/sites-enabled/nipap-default.conf':
      ensure => link,
      target => '/etc/apache2/sites-available/nipap-default.conf',
      }
  -> exec { 'enables_apache_modules':
      command => 'a2enmod ssl && a2enmod proxy_http && a2enmod wsgi',
      subscribe => File['/etc/apache2/sites-available/nipap-ssl.conf'],
      refreshonly => true,
      notify  => Service['apache2']
      }
  -> file {'/etc/nipap/nipap-www.ini':
      ensure  => file,
      mode    => '0644',
      content => template("${template_directory}/nipap-www.ini.erb"),
      }
  -> file { '/var/cache/nipap-www':
      ensure  => directory,
      owner   => 'www-data',
      group   => 'www-data',
      mode    => '0755',
      recurse => true,
      }
  -> file_line { 'db_name':
      line   => 'DBNAMES="nipap postgres"',
      path   => '/etc/default/autopostgresqlbackup',
      ensure => 'present',
      match  => 'DBNAMES="all"',
     }
}
