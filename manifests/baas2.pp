# This puppet manifest is used to install the client side stuff needed to use
# the Safespring Backup 2.0 system (based on IBM Spectrum Protect,
# previously IBM Tivoli Storage Manager (TSM)):
# https://www.safespring.com/en/services/backup/
#
# The manifest is based on sunet::baas, sunet::baas_repo and the derivative
# nunoc::baas(_repo) and cnaas:baas(_repo) manifests.
#
# The "_repo" manifests depend on debian packages built by safespring, but this
# is not done for Backup 2.0, so we automate the installation via some custom
# tooling instead.
#
# The previous generation also depended on cron to run backups, sunet::baas2
# expects scheduling to be handled centrally via the IBM server.
#
# Steps needed to initialize backup:
#   1. Create a node in the BaaS 2.0 system and save the node password.
#   2. Use edit-secrets to give the password to the node BEFORE you run this,
#      use the syntax "baas_password: XXXXXX" in edit-secrets.
#   3. Call upon this module with the nodename, default also backs up subdirs.
#

# @param nodename          The nodename registered in the IBM system for this server
# @param tcpserveraddress  The address of the TSM server we are sending backup data to
# @param monitor_backups   If we should monitor scheduled backups
# @param version           The version of the client to install
# @param backup_dirs       Specific directories to backup, default is to backup everything
# @param exclude_list      List of exclude statements
# @param install_tbmr      If set to true it will install "Bare Machine Recovery for Tivoli TSM (TBMR)"
# @param tbmr_version      The version of TBMR to be installed (it has to match the version in $tbmr_url)
# @param tbmr_url          The download URL for the TBMR installer (it has to match the version in $tbmr_version)
class sunet::baas2(
  String        $nodename='',
  String        $tcpserveraddress='server2.backup.dco1.safedc.net',
  Boolean       $monitor_backups=true,
  String        $version='8.1.22.0',
  Array[String] $backup_dirs = [],
  Array[String] $exclude_list = [],
  Boolean       $install_tbmr=false,
  String        $tbmr_version='9.6.3.3418-1',
  String        $tbmr_url="https://s3.sto1.safedc.net/94f5b4f4aa674782b6bc4181943e67f1:tbmr/wab0snk8lrh6l8cjzgnaozm8siw7g7/tbmr_${tbmr_version}_amd64.deb",
) {

  # MUST be set properly in hiera to continue
  $baas_password = safe_hiera('baas_password')
  $baas_encryption_password = safe_hiera('baas_encryption_password')

  if $nodename and $baas_password != 'NOT_SET_IN_HIERA' and $baas_encryption_password != 'NOT_SET_IN_HIERA' {


    # The dsm.sys template expects backup_dirs to not have a trailing slash, so
    # make sure this is the case
    $backup_dirs_transformed = $backup_dirs.map |$backup_dir| {
        regsubst($backup_dir,'/$','')
    }

    file { '/usr/local/sbin/sunet-baas2-bootstrap':
      ensure  => 'file',
      mode    => '0755',
      owner   => 'root',
      content => file('sunet/baas2/sunet-baas2-bootstrap')
    }

    # Make sure the requested version is installed
    exec { 'sunet-baas2-bootstrap --install':
      command => "/usr/local/sbin/sunet-baas2-bootstrap --install --version=${version}",
    }

    # Install the configuration files
    file { '/opt/tivoli/tsm/client/ba/bin/dsm.sys':
      ensure  => 'file',
      content => template('sunet/baas2/dsm.sys.erb')
    }
    file { '/opt/tivoli/tsm/client/ba/bin/dsm.opt':
      ensure  => 'file',
      content => template('sunet/baas2/dsm.opt.erb')
    }

    file { '/etc/systemd/system/dsmcad.service.d':
      ensure => directory,
      mode   => '0755',
      owner  => 'root',
      group  => 'root',
    }

    # Override dsmcad locale stuff to support more filenames when doing scheduled backups
    file { '/etc/systemd/system/dsmcad.service.d/sunet.conf':
      ensure  => 'file',
      mode    => '0644',
      owner   => 'root',
      group   => 'root',
      content => template('sunet/baas2/dsmcad.service.drop-in.erb')
    }

    # Make sure systemctl has picked up the above drop-in file
    exec { 'reload systemctl for dsmcad drop-in file':
      command     => 'systemctl daemon-reload',
      subscribe   => File['/etc/systemd/system/dsmcad.service.d/sunet.conf'],
      refreshonly => true,
    }

    # Make sure the client is registered with the server
    exec { 'sunet-baas2-bootstrap --register':
      command     => '/usr/local/sbin/sunet-baas2-bootstrap --register',
      environment => [
          "SUNET_BAAS_PASSWORD=${baas_password}",
          "SUNET_BAAS_ENCRYPTION_PASSWORD=${baas_encryption_password}",
      ],
      require     => File['/opt/tivoli/tsm/client/ba/bin/dsm.sys'],
    }

    service { 'dsmcad':
      ensure  => 'running',
      enable  => true,
      require => Exec['sunet-baas2-bootstrap --register'],
    }

    if $monitor_backups {
      file { '/usr/local/sbin/sunet-baas2-status':
        ensure  => 'file',
        mode    => '0755',
        owner   => 'root',
        content => file('sunet/baas2/sunet-baas2-status')
      }

      sunet::scriptherder::cronjob { 'sunet-baas2-status':
        cmd         => '/usr/local/sbin/sunet-baas2-status',
        minute      => '26',
        ok_criteria => ['exit_status=0', 'max_age=3h'],
      }
    }

    # TBMR section
    # MUST be set properly in hiera to continue
    $tbmr_lic = safe_hiera('tbmr_lic')
    $tbmr_cid = safe_hiera('tbmr_cid')
    if $install_tbmr and $tbmr_lic != 'NOT_SET_IN_HIERA' and $tbmr_cid != 'NOT_SET_IN_HIERA' {
      file { '/usr/local/sbin/sunet-baas2-tbmr-bootstrap':
        ensure  => 'file',
        mode    => '0755',
        owner   => 'root',
        content => file('sunet/baas2/sunet-baas2-tbmr-bootstrap')
      }

      # Make sure the requested TBMR version is installed
      exec { 'sunet-baas2-tbmr-bootstrap --install':
        command => "/usr/local/sbin/sunet-baas2-tbmr-bootstrap --install --version=${tbmr_version} --tbmr_url=${tbmr_url}",
      }

      # Activate the TBMR license
      exec { 'sunet-baas2-tbmr-bootstrap --activate':
        command     => '/usr/local/sbin/sunet-baas2-tbmr-bootstrap --activate',
        environment => [
            "TBMR_LIC=${tbmr_lic}",
            "TBMR_CID=${tbmr_cid}",
        ]
      }
    }
  }
}
