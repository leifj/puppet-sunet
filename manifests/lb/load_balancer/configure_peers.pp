# Create resources for Exabgp peers
define sunet::lb::load_balancer::configure_peers($router_id, $peers)
{
  $defaults = {
    router_id => $router_id,
  }
  create_resources('sunet::lb::load_balancer::peer', $peers, $defaults)
}
