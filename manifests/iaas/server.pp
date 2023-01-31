class sunet::iaas::server(
) {
  if $::sunet_nftables_opt_in == 'yes' or ( $::operatingsystem == 'Ubuntu' and versioncmp($::operatingsystemrelease, '22.04') >= 0 ) {
    # Allow DHCPv6 which is used in Safespring
    sunet::nftables::rule { 'iaas_dhcpv6':
      rule => 'add rule inet filter input ip6 saddr fe80::/10 ip6 daddr fe80::/10 udp sport 547 udp dport 546 counter accept comment "dhcpv6"'
    }
  }
}
