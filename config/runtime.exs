import Config

if config_env() in [:prod] do

  config :extracker,
    ipv4_enabled: true, # listen or not on IPv4
    ipv4_bind_address: "0.0.0.0", # IP to bind to when IPv4 is enabled. "0.0.0.0" listens on every address
    ipv6_enabled: true, # listen or not on IPv6
    ipv6_bind_address: "::", # IP to bind to when IPv6 is enabled. "::" listens on every address
    http_enabled: true, # enable the HTTP endpoint to fulfill client requests
    http_port: 6969, # port used by the HTTP endpoint if enabled
    https_enabled: false, # enable the TLS endpoint to fulfill client requests
    https_port: 7070, # port used by the TLS endpoint if enabled
    udp_enabled: true, # enable the UDP endpoint to fulfill client requests
    udp_port: 6969, # port usesd by the UDP endpoint if enabled
    udp_routers: -1, # amount of processes listening to UDP requests. -1 means one per VM scheduler
    udp_recbuf_size: -1, # kernel receive buffer size for the UDP socket. 512_000 is a good number, -1 means the OS decides
    udp_sndbuf_size: -1, # kernel send buffer size for the UDP socket. 512_000 is a good number, -1 means the OS decides
    udp_buffer_size: -1, # buffer size for the UDP socket. 1_048_576 is a good number, -1 means the OS decides
    connection_id_secret: 87178291199, # prime used as salt for connection id's generation
    scrape_enabled: false, # allow scrape requests on all enabled endpoints
    force_compact_peers: false, # always respond to HTTP(S) requests with a compact peer list
    return_external_ip: false, # return the client's visible IP as per BEP24
    max_peers_returned: 100, # non-negative maximum amount of peers sent to announcing clients
    announce_interval: (30 * 60), # seconds that clients SHOULD wait before announcing again
    announce_interval_min: 60, # seconds that clients HAVE to wait before announcing again. below this requests are ignored
    cleaning_interval: (60 * 1000), # milliseconds between cleaning passes
    swarm_clean_delay: (10 * 60 * 1_000), # milliseconds after a swarm is marked as 'needs cleaning'
    peer_cleanup_delay: (60 * 60 * 1_000), # milliseconds after a peer is considered stale and removed
    compress_lookups: true, # compressed lookup tables take less space while losing some performance
    named_lookups: false, # identify each swarm lookup table as "swarm_HASH" instead of just "swarm". Will exhaust the atom table at some point
    backup_auto_enabled: true, # enable automatic backups creation
    backup_auto_load_on_startup: true, # load the backup file specified in backup_auto_path when the tracker starts
    backup_auto_interval: (60 * 60 * 1000), # milliseconds between automatic backups
    backup_auto_path: "~/extracker.bck", # file path used for automatic backups
    backup_display_stats: true, # log how many peers and swarms are registered when a backup triggers
    debug: false # enable extra debug logs and checks

  config :logger, level: :notice # log minimum level. info and debug may get spammy

end
