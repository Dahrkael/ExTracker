import Config

config :extracker,
  debug: false,
  compress_lookups: false,
  named_lookups: true,
  bind_address_ip: {0,0,0,0},
  http_enabled: true,
  http_port: 6969,
  https_enabled: false,
  https_port: 7070,
  udp_enabled: true,
  udp_port: 6969,
  udp_routers: 1,
  udp_recbuf_size: -1,
  udp_sndbuf_size: -1,
  udp_buffer_size: -1,
  connection_id_secret: 87178291199,
  scrape_enabled: true,
  force_compact_peers: false,
  return_external_ip: true,
  max_peers_returned: 25

config :logger,
  level: :debug
