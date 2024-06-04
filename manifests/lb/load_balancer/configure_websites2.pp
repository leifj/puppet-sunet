
define sunet::lb::load_balancer::configure_websites2($websites, $basedir, $confdir, $scriptdir)
{
  each($websites) | $site, $config | {
    create_resources('sunet::lb::load_balancer::website2', {$site => {}}, {
      'basedir'         => $basedir,
      'confdir'         => $confdir,
      'scriptdir'       => $scriptdir,
      'config'          => $config,
      })
  }
}
